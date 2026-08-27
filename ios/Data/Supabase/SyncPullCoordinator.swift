import Foundation
import OSLog
import SwiftData

enum SyncPullCoordinatorError: Error, LocalizedError {
    case alreadyRunning
    case invalidBounds
    case cursorReadFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A sync pull run is already in progress."
        case .invalidBounds:
            "The sync pull page bounds are invalid."
        case .cursorReadFailed:
            "The persistent sync pull cursor could not be read."
        }
    }
}

enum SyncPullFailure: Equatable, Sendable {
    case invalidRemoteRecord
    case invalidPayload
    case immutableCollision
    case invariantViolation
    case metadata
    case persistence
}

private enum SyncRemoteApplyFailureCategory: String {
    case syncLocalStoreUnsupportedPayloadSchema
    case syncLocalStoreMissingEntity
    case syncLocalStoreInvalidPayload
    case syncLocalStoreInconsistentIdentity
    case syncLocalStoreImmutableCollision
    case syncMetadata
    case persistence
}

private struct SyncRemoteApplyFailureDiagnostic {
    let reason: SyncPullFailure
    let category: SyncRemoteApplyFailureCategory
    let safeErrorDescription: String

    var requiresCanonicalDifferenceSummary: Bool {
        switch reason {
        case .immutableCollision, .invariantViolation:
            true
        case .invalidRemoteRecord, .invalidPayload, .metadata, .persistence:
            false
        }
    }
}

enum SyncPullRunFailure: Equatable, Sendable {
    case transport(SupabaseInfrastructureError)
    case cursorPersistence
}

enum SyncPullItemOutcome: Equatable, Sendable {
    case remoteApplied(
        key: SyncEntityKey,
        serverRevision: Int64,
        republishKeys: [SyncEntityKey],
        staleOutboxAcknowledged: Bool,
    )
    case localWon(
        key: SyncEntityKey,
        serverRevision: Int64,
        republishKeys: [SyncEntityKey],
    )
    case idempotent(key: SyncEntityKey, serverRevision: Int64)
    case deferred(key: SyncEntityKey, serverRevision: Int64, missing: [SyncEntityKey])
    case superseded(key: SyncEntityKey, serverRevision: Int64, supersededBy: Int64)
    case failed(key: SyncEntityKey, serverRevision: Int64, reason: SyncPullFailure)
}

struct SyncPullReport: Equatable, Sendable {
    let startingCursor: Int64
    let endingCursor: Int64
    let fetched: Int
    let pagesFetched: Int
    let caughtUpToRemoteState: Bool
    let outcomes: [SyncPullItemOutcome]
    let runFailure: SyncPullRunFailure?

    var processed: Int {
        outcomes.count(where: { outcome in
            switch outcome {
            case .remoteApplied, .localWon, .idempotent, .superseded:
                true
            case .deferred, .failed:
                false
            }
        })
    }

    var remoteApplied: Int {
        outcomes.count(where: { if case .remoteApplied = $0 { true } else { false } })
    }

    var localWon: Int {
        outcomes.count(where: { if case .localWon = $0 { true } else { false } })
    }

    var idempotent: Int {
        outcomes.count(where: { if case .idempotent = $0 { true } else { false } })
    }

    var republishQueued: Int {
        Set(outcomes.flatMap(\.republishKeys)).count
    }

    var deferred: Int {
        outcomes.count(where: { if case .deferred = $0 { true } else { false } })
    }

    var failed: Int {
        outcomes.count(where: { if case .failed = $0 { true } else { false } }) + (runFailure == nil ? 0 : 1)
    }
}

private extension SyncPullItemOutcome {
    var republishKeys: [SyncEntityKey] {
        switch self {
        case let .remoteApplied(_, _, republishKeys, _), let .localWon(_, _, republishKeys):
            republishKeys
        case .idempotent, .deferred, .superseded, .failed:
            []
        }
    }
}

private extension SyncMergeResult {
    var republishKeys: [SyncEntityKey] {
        switch self {
        case let .inserted(_, needsRepublish), let .remoteApplied(_, needsRepublish), let .localKept(_, needsRepublish):
            needsRepublish
        case .identical, .deferred:
            []
        }
    }
}

private let syncPullLogger = Logger(subsystem: "com.caloriestracker.ios", category: "SyncPull")
private let defaultSyncPullPageSize = 200
private let defaultSyncPullMaximumPages = 5

/// Explicit incremental-pull infrastructure; `SyncOrchestrator` decides when to invoke it.
@MainActor
final class SyncPullCoordinator {
    static let defaultPageSize = defaultSyncPullPageSize
    static let defaultMaximumPages = defaultSyncPullMaximumPages
    static let maximumFetchedRecords = 1_000

    private let modelContainer: ModelContainer
    private let localStore: SyncLocalStore
    private let authService: SupabaseAuthService
    private let transport: SupabaseSyncTransport
    private var isPullRunning = false
    private var didLogAccountChangedAbort = false

    init(
        modelContainer: ModelContainer,
        localStore: SyncLocalStore,
        authService: SupabaseAuthService,
        transport: SupabaseSyncTransport,
    ) {
        self.modelContainer = modelContainer
        self.localStore = localStore
        self.authService = authService
        self.transport = transport
    }

    /// Pulls a bounded incremental scan. A deferred dependency never advances the persistent cursor.
    func pullIncrementally(
        expectedAccountID: UUID,
        pageSize: Int = defaultSyncPullPageSize,
        maximumPages: Int = defaultSyncPullMaximumPages,
    ) async throws -> SyncPullReport {
        guard pageSize > 0, maximumPages > 0 else {
            throw SyncPullCoordinatorError.invalidBounds
        }
        guard !isPullRunning else {
            throw SyncPullCoordinatorError.alreadyRunning
        }
        isPullRunning = true
        didLogAccountChangedAbort = false
        defer { isPullRunning = false }

        try await verifyCurrentAccount(expectedAccountID)
        do {
            try localStore.normalizeWeeklyGoalIdentities()
        } catch {
            syncPullLogger.error("Sync pull could not normalize WeeklyGoal identities")
            throw SyncPullCoordinatorError.cursorReadFailed
        }
        let startingCursor: Int64
        do {
            let modelContext = ModelContext(modelContainer)
            startingCursor = try SyncMetadataStore.pullCursor(accountID: expectedAccountID, in: modelContext)
        } catch {
            syncPullLogger.error("Sync pull could not read its persistent cursor")
            throw SyncPullCoordinatorError.cursorReadFailed
        }

        var endingCursor = startingCursor
        var scanAfterRevision = startingCursor
        var fetched = 0
        var pagesFetched = 0
        var pendingRecords: [Int64: SupabaseRemoteSyncRecord] = [:]
        var deferredDependencies: [Int64: [SyncEntityKey]] = [:]
        var outcomes: [Int64: SyncPullItemOutcome] = [:]
        var runFailure: SyncPullRunFailure?
        var shouldContinue = true
        var caughtUpToRemoteState = false

        while shouldContinue,
              pagesFetched < maximumPages,
              fetched < Self.maximumFetchedRecords
        {
            let requestLimit = min(pageSize, Self.maximumFetchedRecords - fetched)
            let page: [SupabaseRemoteSyncRecord]
            do {
                try await verifyCurrentAccount(expectedAccountID)
                page = try await transport.fetchChanges(
                    after: scanAfterRevision,
                    limit: requestLimit,
                    expectedAccountID: expectedAccountID,
                )
                try await verifyCurrentAccount(expectedAccountID)
                pagesFetched += 1
            } catch let error as SupabaseInfrastructureError where error == .accountChanged {
                logAccountChangedAbort()
                throw error
            } catch let error as SupabaseInfrastructureError {
                syncPullLogger.error("Sync pull transport failed")
                runFailure = .transport(error)
                break
            } catch {
                syncPullLogger.error("Sync pull transport failed")
                runFailure = .transport(.server)
                break
            }

            guard !page.isEmpty else {
                caughtUpToRemoteState = true
                break
            }

            fetched += page.count

            for record in page {
                guard record.serverRevision > scanAfterRevision,
                      record.payload.key == record.key,
                      record.payloadSchemaVersion == SyncPayloadFormat.currentSchemaVersion
                else {
                    outcomes[record.serverRevision] = .failed(
                        key: record.key,
                        serverRevision: record.serverRevision,
                        reason: .invalidRemoteRecord,
                    )
                    shouldContinue = false
                    break
                }

                // A row can be updated while a bounded scan is in progress. A newer
                // snapshot safely replaces only an unresolved dependency deferral.
                let supersededRevisions = pendingRecords.compactMap { revision, pendingRecord in
                    pendingRecord.key == record.key ? revision : nil
                }
                for revision in supersededRevisions {
                    guard let pendingRecord = pendingRecords[revision] else {
                        continue
                    }
                    pendingRecords.removeValue(forKey: revision)
                    deferredDependencies.removeValue(forKey: revision)
                    outcomes[revision] = .superseded(
                        key: pendingRecord.key,
                        serverRevision: revision,
                        supersededBy: record.serverRevision,
                    )
                }
                pendingRecords[record.serverRevision] = record
            }

            scanAfterRevision = page[page.count - 1].serverRevision
            resolveAvailableRecords(
                pendingRecords: &pendingRecords,
                deferredDependencies: &deferredDependencies,
                outcomes: &outcomes,
                accountID: expectedAccountID,
            )

            let safeCursor = safeCursor(
                startingAt: endingCursor,
                scannedThrough: scanAfterRevision,
                pendingRecords: pendingRecords,
                outcomes: outcomes,
            )
            if safeCursor > endingCursor {
                guard advanceCursor(safeCursor, accountID: expectedAccountID) else {
                    runFailure = .cursorPersistence
                    break
                }
                endingCursor = safeCursor
            }

            if outcomes.values.contains(where: { if case .failed = $0 { true } else { false } }) {
                shouldContinue = false
            } else if page.count < requestLimit {
                shouldContinue = false
                caughtUpToRemoteState = true
            }
        }

        for (revision, record) in pendingRecords {
            outcomes[revision] = .deferred(
                key: record.key,
                serverRevision: revision,
                missing: deferredDependencies[revision] ?? [],
            )
        }

        let report = SyncPullReport(
            startingCursor: startingCursor,
            endingCursor: endingCursor,
            fetched: fetched,
            pagesFetched: pagesFetched,
            caughtUpToRemoteState: caughtUpToRemoteState,
            outcomes: outcomes.keys.sorted().compactMap { outcomes[$0] },
            runFailure: runFailure,
        )
        syncPullLogger.debug(
            "Sync pull summary fetched=\(report.fetched, privacy: .public) processed=\(report.processed, privacy: .public) deferred=\(report.deferred, privacy: .public) failed=\(report.failed, privacy: .public) pages=\(report.pagesFetched, privacy: .public)",
        )
        return report
    }

    private func resolveAvailableRecords(
        pendingRecords: inout [Int64: SupabaseRemoteSyncRecord],
        deferredDependencies: inout [Int64: [SyncEntityKey]],
        outcomes: inout [Int64: SyncPullItemOutcome],
        accountID: UUID,
    ) {
        var madeProgress = true
        while madeProgress {
            madeProgress = false
            for revision in pendingRecords.keys.sorted() {
                guard let record = pendingRecords[revision] else {
                    continue
                }

                let outcome = apply(record, accountID: accountID)
                switch outcome {
                case let .deferred(_, _, missing):
                    deferredDependencies[revision] = missing
                case .remoteApplied, .localWon, .idempotent, .superseded, .failed:
                    pendingRecords.removeValue(forKey: revision)
                    deferredDependencies.removeValue(forKey: revision)
                    outcomes[revision] = outcome
                    madeProgress = true
                }
            }
        }
    }

    private func apply(
        _ record: SupabaseRemoteSyncRecord,
        accountID: UUID,
    ) -> SyncPullItemOutcome {
        guard record.serverRevision > 0,
              record.payload.key == record.key,
              record.payloadSchemaVersion == SyncPayloadFormat.currentSchemaVersion
        else {
            return .failed(
                key: record.key,
                serverRevision: record.serverRevision,
                reason: .invalidRemoteRecord,
            )
        }

        let modelContext = ModelContext(modelContainer)
        do {
            let canonicalWeeklyGoalKey = canonicalWeeklyGoalKey(for: record)
            // This token is captured before the merge and acknowledged only if that
            // exact local state loses to the remote record.
            let staleOutboxItem = try SyncOutboxStore.pendingItem(key: record.key, in: modelContext)
            let mergeResult = try localStore.applyRemote(record.envelope, in: modelContext)
            if case let .deferred(key, missing) = mergeResult {
                modelContext.rollback()
                return .deferred(key: key, serverRevision: record.serverRevision, missing: missing)
            }

            try SyncMetadataStore.setRemoteRevision(
                record.serverRevision,
                accountID: accountID,
                entityKey: record.key,
                in: modelContext,
            )

            var republishKeys = Set(mergeResult.republishKeys)
            if let canonicalWeeklyGoalKey,
               try shouldRepublishCanonicalWeeklyGoal(
                   after: mergeResult,
                   canonicalKey: canonicalWeeklyGoalKey,
                   accountID: accountID,
                   in: modelContext,
               )
            {
                // The remote alias remains authoritative only for its own server
                // revision. The local aggregate is canonical, so make sure the
                // winning content is eventually present under the canonical key.
                republishKeys.insert(canonicalWeeklyGoalKey)
            }
            let orderedRepublishKeys = republishKeys.sorted { $0.rawValue < $1.rawValue }
            for key in orderedRepublishKeys {
                try SyncOutboxStore.ensurePending(key: key, in: modelContext)
            }

            let staleOutboxAcknowledged: Bool
            if canonicalWeeklyGoalKey != nil,
               let staleOutboxItem
            {
                // An alias key cannot be exported after local normalization. Its
                // exact token is removed in this same transaction, while any
                // canonical marker above stays pending for normal push handling.
                staleOutboxAcknowledged = try SyncOutboxStore.acknowledge(
                    key: staleOutboxItem.key,
                    token: staleOutboxItem.changeToken,
                    in: modelContext,
                )
            } else if case .remoteApplied = mergeResult,
                      !republishKeys.contains(record.key),
               let staleOutboxItem
            {
                staleOutboxAcknowledged = try SyncOutboxStore.acknowledge(
                    key: staleOutboxItem.key,
                    token: staleOutboxItem.changeToken,
                    in: modelContext,
                )
            } else {
                staleOutboxAcknowledged = false
            }

            // The remote merge, per-entity server revision and all outbox work share
            // one persistence boundary. Remote application never calls markChanged.
            try modelContext.save()
            return outcome(
                for: mergeResult,
                remoteKey: record.key,
                serverRevision: record.serverRevision,
                republishKeys: orderedRepublishKeys,
                staleOutboxAcknowledged: staleOutboxAcknowledged,
            )
        } catch {
            modelContext.rollback()
            let diagnostic = failureDiagnostic(for: error)
            logRemoteApplyFailure(
                record,
                diagnostic: diagnostic,
                canonicalDifferenceSummary: diagnostic.requiresCanonicalDifferenceSummary
                    ? canonicalDifferenceSummary(for: record)
                    : nil,
            )
            return .failed(
                key: record.key,
                serverRevision: record.serverRevision,
                reason: diagnostic.reason,
            )
        }
    }

    /// Returns the canonical local identity only when a valid WeeklyGoal row is
    /// a legacy server alias. The caller must still store its revision under the
    /// actual remote key.
    private func canonicalWeeklyGoalKey(for record: SupabaseRemoteSyncRecord) -> SyncEntityKey? {
        guard case let .weeklyGoal(payload) = record.payload else {
            return nil
        }
        let canonicalKey = SyncEntityKey(
            entityType: .weeklyGoal,
            entityID: WeeklyGoalIdentity.id(for: payload.effectiveFrom),
        )
        return canonicalKey == record.key ? nil : canonicalKey
    }

    /// An unchanged alias needs a canonical push only when the account has not
    /// observed a canonical server row. A merge that inserted, changed or kept
    /// a locally newer aggregate already needs that republish independently.
    private func shouldRepublishCanonicalWeeklyGoal(
        after mergeResult: SyncMergeResult,
        canonicalKey: SyncEntityKey,
        accountID: UUID,
        in modelContext: ModelContext,
    ) throws -> Bool {
        switch mergeResult {
        case .identical:
            try SyncMetadataStore.remoteRevision(
                accountID: accountID,
                entityKey: canonicalKey,
                in: modelContext,
            ) == nil
        case .inserted, .remoteApplied, .localKept:
            true
        case .deferred:
            false
        }
    }

    private func outcome(
        for mergeResult: SyncMergeResult,
        remoteKey: SyncEntityKey,
        serverRevision: Int64,
        republishKeys: [SyncEntityKey],
        staleOutboxAcknowledged: Bool,
    ) -> SyncPullItemOutcome {
        switch mergeResult {
        case .inserted, .remoteApplied:
            return .remoteApplied(
                key: remoteKey,
                serverRevision: serverRevision,
                republishKeys: republishKeys,
                staleOutboxAcknowledged: staleOutboxAcknowledged,
            )
        case .localKept:
            return .localWon(
                key: remoteKey,
                serverRevision: serverRevision,
                republishKeys: republishKeys,
            )
        case .identical:
            return .idempotent(key: remoteKey, serverRevision: serverRevision)
        case let .deferred(key, missing):
            return .deferred(key: key, serverRevision: serverRevision, missing: missing)
        }
    }

    private func failureDiagnostic(for error: Error) -> SyncRemoteApplyFailureDiagnostic {
        guard let error = error as? SyncLocalStoreError else {
            if error is SyncMetadataStoreError {
                return SyncRemoteApplyFailureDiagnostic(
                    reason: .metadata,
                    category: .syncMetadata,
                    safeErrorDescription: "sync metadata rejected the remote record",
                )
            }
            return SyncRemoteApplyFailureDiagnostic(
                reason: .persistence,
                category: .persistence,
                safeErrorDescription: "persistence operation failed",
            )
        }

        switch error {
        case let .unsupportedPayloadSchema(version):
            return SyncRemoteApplyFailureDiagnostic(
                reason: .invalidPayload,
                category: .syncLocalStoreUnsupportedPayloadSchema,
                safeErrorDescription: "unsupported payload schema \(version)",
            )
        case .missingEntity:
            return SyncRemoteApplyFailureDiagnostic(
                reason: .persistence,
                category: .syncLocalStoreMissingEntity,
                safeErrorDescription: "local entity is missing",
            )
        case .invalidPayload:
            return SyncRemoteApplyFailureDiagnostic(
                reason: .invalidPayload,
                category: .syncLocalStoreInvalidPayload,
                safeErrorDescription: "payload validation rejected the remote record",
            )
        case .inconsistentIdentity:
            return SyncRemoteApplyFailureDiagnostic(
                reason: .invariantViolation,
                category: .syncLocalStoreInconsistentIdentity,
                safeErrorDescription: "local identity invariant rejected the remote record",
            )
        case .immutableCollision:
            return SyncRemoteApplyFailureDiagnostic(
                reason: .immutableCollision,
                category: .syncLocalStoreImmutableCollision,
                safeErrorDescription: "immutable canonical payload differs from the local record",
            )
        }
    }

    private func logRemoteApplyFailure(
        _ record: SupabaseRemoteSyncRecord,
        diagnostic: SyncRemoteApplyFailureDiagnostic,
        canonicalDifferenceSummary: String?,
    ) {
        if let canonicalDifferenceSummary {
            syncPullLogger.error(
                "Sync pull remote apply failure serverRevision=\(record.serverRevision, privacy: .public) entityType=\(record.key.entityType.rawValue, privacy: .public) entityID=\(record.key.entityID.uuidString.lowercased(), privacy: .public) failureCategory=\(diagnostic.category.rawValue, privacy: .public) error=\(diagnostic.safeErrorDescription, privacy: .public) difference=\(canonicalDifferenceSummary, privacy: .public)",
            )
        } else {
            syncPullLogger.error(
                "Sync pull remote apply failure serverRevision=\(record.serverRevision, privacy: .public) entityType=\(record.key.entityType.rawValue, privacy: .public) entityID=\(record.key.entityID.uuidString.lowercased(), privacy: .public) failureCategory=\(diagnostic.category.rawValue, privacy: .public) error=\(diagnostic.safeErrorDescription, privacy: .public)",
            )
        }
    }

    /// Rebuilds the persisted payload after the failed transaction has rolled back. This is
    /// diagnostic-only; no merge result, cursor or local record is changed by this read.
    private func canonicalDifferenceSummary(for record: SupabaseRemoteSyncRecord) -> String {
        do {
            let localPayload = try localStore.payload(for: record.key)
            return canonicalDifferenceSummary(local: localPayload, incoming: record.payload)
        } catch {
            return "localCanonicalPayload=unavailable"
        }
    }

    private func canonicalDifferenceSummary(local: SyncPayload, incoming: SyncPayload) -> String {
        switch (local, incoming) {
        case let (.productVersion(local), .productVersion(incoming)):
            return productVersionDifferenceSummary(local: local, incoming: incoming)
        case let (.recipeVersion(local), .recipeVersion(incoming)):
            return recipeVersionDifferenceSummary(local: local, incoming: incoming)
        default:
            return genericCanonicalDifferenceSummary(local: local, incoming: incoming)
        }
    }

    /// Non-version invariants do not need scalar values in logs. Their canonical JSON is used
    /// only to name differing fields, never to emit a payload or a user-provided value.
    private func genericCanonicalDifferenceSummary(local: SyncPayload, incoming: SyncPayload) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let localJSON = try JSONSerialization.jsonObject(with: encoder.encode(local))
            let incomingJSON = try JSONSerialization.jsonObject(with: encoder.encode(incoming))
            var differences: [String] = []
            appendCanonicalFieldDifferences(
                local: localJSON,
                incoming: incomingJSON,
                path: "payload",
                to: &differences,
            )
            return boundedDifferenceSummary(differences)
        } catch {
            return "canonicalPayload=changed(fieldSummaryUnavailable)"
        }
    }

    private func appendCanonicalFieldDifferences(
        local: Any,
        incoming: Any,
        path: String,
        to differences: inout [String],
    ) {
        if let localDictionary = local as? [String: Any],
           let incomingDictionary = incoming as? [String: Any]
        {
            let keys = Set(localDictionary.keys).union(incomingDictionary.keys).sorted()
            for key in keys {
                let fieldPath = "\(path).\(key)"
                guard let localValue = localDictionary[key] else {
                    differences.append("\(fieldPath) local=missing incoming=present")
                    continue
                }
                guard let incomingValue = incomingDictionary[key] else {
                    differences.append("\(fieldPath) local=present incoming=missing")
                    continue
                }
                appendCanonicalFieldDifferences(
                    local: localValue,
                    incoming: incomingValue,
                    path: fieldPath,
                    to: &differences,
                )
            }
            return
        }

        if let localArray = local as? [Any],
           let incomingArray = incoming as? [Any]
        {
            if localArray.count != incomingArray.count {
                differences.append("\(path).count local=\(localArray.count) incoming=\(incomingArray.count)")
            }
            for index in 0 ..< min(localArray.count, incomingArray.count) {
                appendCanonicalFieldDifferences(
                    local: localArray[index],
                    incoming: incomingArray[index],
                    path: "\(path)[\(index)]",
                    to: &differences,
                )
            }
            return
        }

        let localValue = local as? NSObject
        let incomingValue = incoming as? NSObject
        guard localValue?.isEqual(incomingValue) == true else {
            differences.append("\(path) differs")
            return
        }
    }

    private func productVersionDifferenceSummary(
        local: ProductVersionPayload,
        incoming: ProductVersionPayload,
    ) -> String {
        var differences: [String] = []
        appendDifference("id", local.id, incoming.id, format: formatUUID, to: &differences)
        appendDifference("productID", local.productID, incoming.productID, format: formatUUID, to: &differences)
        appendDifference(
            "basedOnVersionID",
            local.basedOnVersionID,
            incoming.basedOnVersionID,
            format: formatOptionalUUID,
            to: &differences,
        )
        appendDifference("versionNumber", local.versionNumber, incoming.versionNumber, format: formatInteger, to: &differences)
        appendDifference("baseUnit", local.baseUnit.rawValue, incoming.baseUnit.rawValue, format: { $0 }, to: &differences)
        appendDifference("baseAmount", local.baseAmount, incoming.baseAmount, format: formatNumber, to: &differences)
        appendDifference(
            "nutrition.calories",
            local.nutrition.calories,
            incoming.nutrition.calories,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "nutrition.protein",
            local.nutrition.protein,
            incoming.nutrition.protein,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "nutrition.fat",
            local.nutrition.fat,
            incoming.nutrition.fat,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "nutrition.carbs",
            local.nutrition.carbs,
            incoming.nutrition.carbs,
            format: formatNumber,
            to: &differences,
        )
        appendDifference("createdAt", local.createdAt, incoming.createdAt, format: formatDate, to: &differences)
        return boundedDifferenceSummary(differences)
    }

    private func recipeVersionDifferenceSummary(
        local: RecipeVersionPayload,
        incoming: RecipeVersionPayload,
    ) -> String {
        var differences: [String] = []
        appendDifference("id", local.id, incoming.id, format: formatUUID, to: &differences)
        appendDifference("recipeID", local.recipeID, incoming.recipeID, format: formatUUID, to: &differences)
        appendDifference(
            "basedOnVersionID",
            local.basedOnVersionID,
            incoming.basedOnVersionID,
            format: formatOptionalUUID,
            to: &differences,
        )
        appendDifference("versionNumber", local.versionNumber, incoming.versionNumber, format: formatInteger, to: &differences)
        appendDifference(
            "totalNutrition.calories",
            local.totalNutrition.calories,
            incoming.totalNutrition.calories,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "totalNutrition.protein",
            local.totalNutrition.protein,
            incoming.totalNutrition.protein,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "totalNutrition.fat",
            local.totalNutrition.fat,
            incoming.totalNutrition.fat,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "totalNutrition.carbs",
            local.totalNutrition.carbs,
            incoming.totalNutrition.carbs,
            format: formatNumber,
            to: &differences,
        )
        appendDifference(
            "cookedWeight",
            local.cookedWeight,
            incoming.cookedWeight,
            format: formatOptionalNumber,
            to: &differences,
        )
        appendDifference(
            "servingsCount",
            local.servingsCount,
            incoming.servingsCount,
            format: formatOptionalNumber,
            to: &differences,
        )
        appendDifference("createdAt", local.createdAt, incoming.createdAt, format: formatDate, to: &differences)
        appendIngredientDifferences(local: local.ingredients, incoming: incoming.ingredients, to: &differences)
        return boundedDifferenceSummary(differences)
    }

    private func appendIngredientDifferences(
        local: [RecipeVersionPayload.Ingredient],
        incoming: [RecipeVersionPayload.Ingredient],
        to differences: inout [String],
    ) {
        appendDifference("ingredients.count", local.count, incoming.count, format: formatInteger, to: &differences)

        let sharedCount = min(local.count, incoming.count)
        for index in 0 ..< sharedCount where local[index] != incoming[index] {
            differences.append(
                "ingredient[index=\(index)] local={\(formatIngredient(local[index]))} incoming={\(formatIngredient(incoming[index]))}",
            )
        }

        if local.count > sharedCount {
            for index in sharedCount ..< local.count {
                differences.append("ingredient[index=\(index)] local={\(formatIngredient(local[index]))} incoming=missing")
            }
        }
        if incoming.count > sharedCount {
            for index in sharedCount ..< incoming.count {
                differences.append("ingredient[index=\(index)] local=missing incoming={\(formatIngredient(incoming[index]))}")
            }
        }
    }

    private func appendDifference<Value: Equatable>(
        _ field: String,
        _ local: Value,
        _ incoming: Value,
        format: (Value) -> String,
        to differences: inout [String],
    ) {
        guard local != incoming else {
            return
        }
        differences.append("\(field) local=\(format(local)) incoming=\(format(incoming))")
    }

    private func boundedDifferenceSummary(_ differences: [String]) -> String {
        guard !differences.isEmpty else {
            return "canonicalPayload=identical"
        }

        let maximumEntries = 24
        let displayed = differences.prefix(maximumEntries)
        let suffix = differences.count > maximumEntries
            ? " additionalDifferences=\(differences.count - maximumEntries)"
            : ""
        return "changedFields=\(displayed.joined(separator: "; "))\(suffix)"
    }

    private func formatIngredient(_ ingredient: RecipeVersionPayload.Ingredient) -> String {
        "position=\(ingredient.position),id=\(formatUUID(ingredient.id)),recipeVersionID=\(formatUUID(ingredient.recipeVersionID)),productID=\(formatUUID(ingredient.productID)),productVersionID=\(formatUUID(ingredient.productVersionID)),amount=\(formatNumber(ingredient.amount)),unit=\(ingredient.unitToken),normalizedAmount=\(formatNumber(ingredient.normalizedAmount))"
    }

    private func formatUUID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private func formatOptionalUUID(_ value: UUID?) -> String {
        value.map(formatUUID) ?? "nil"
    }

    private func formatInteger(_ value: Int) -> String {
        String(value)
    }

    private func formatNumber(_ value: Double) -> String {
        String(format: "%.17g", value)
    }

    private func formatOptionalNumber(_ value: Double?) -> String {
        value.map(formatNumber) ?? "nil"
    }

    private func formatDate(_ value: Date) -> String {
        formatNumber(value.timeIntervalSince1970)
    }

    private func safeCursor(
        startingAt currentCursor: Int64,
        scannedThrough: Int64,
        pendingRecords: [Int64: SupabaseRemoteSyncRecord],
        outcomes: [Int64: SyncPullItemOutcome],
    ) -> Int64 {
        let blockingRevisions = outcomes.compactMap { revision, outcome -> Int64? in
            if case .failed = outcome {
                revision
            } else {
                nil
            }
        }
        if let earliestUnresolved = (Array(pendingRecords.keys) + blockingRevisions).min() {
            return max(currentCursor, earliestUnresolved - 1)
        }
        return max(currentCursor, scannedThrough)
    }

    private func advanceCursor(_ revision: Int64, accountID: UUID) -> Bool {
        let modelContext = ModelContext(modelContainer)
        do {
            try SyncMetadataStore.setPullCursor(revision, accountID: accountID, in: modelContext)
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            syncPullLogger.error("Sync pull could not persist its safe cursor")
            return false
        }
    }

    private func verifyCurrentAccount(_ expectedAccountID: UUID) async throws {
        guard try await authService.currentSession()?.userID == expectedAccountID else {
            logAccountChangedAbort()
            throw SupabaseInfrastructureError.accountChanged
        }
    }

    private func logAccountChangedAbort() {
        guard !didLogAccountChangedAbort else {
            return
        }
        didLogAccountChangedAbort = true
        syncPullLogger.debug("Sync pull run aborted because authenticated account changed")
    }
}
