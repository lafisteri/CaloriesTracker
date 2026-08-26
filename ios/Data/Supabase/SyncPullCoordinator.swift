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
        defer { isPullRunning = false }

        // An absent session returns before reading or mutating local sync state.
        guard let session = try await authService.currentSession() else {
            throw SupabaseInfrastructureError.notAuthenticated
        }
        let accountID = session.userID
        let startingCursor: Int64
        do {
            let modelContext = ModelContext(modelContainer)
            startingCursor = try SyncMetadataStore.pullCursor(accountID: accountID, in: modelContext)
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

        syncPullLogger.debug("Sync pull run started at cursor \(startingCursor, privacy: .public)")

        while shouldContinue,
              pagesFetched < maximumPages,
              fetched < Self.maximumFetchedRecords
        {
            let requestLimit = min(pageSize, Self.maximumFetchedRecords - fetched)
            let page: [SupabaseRemoteSyncRecord]
            do {
                page = try await transport.fetchChanges(after: scanAfterRevision, limit: requestLimit)
                pagesFetched += 1
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
                accountID: accountID,
            )

            let safeCursor = safeCursor(
                startingAt: endingCursor,
                scannedThrough: scanAfterRevision,
                pendingRecords: pendingRecords,
                outcomes: outcomes,
            )
            if safeCursor > endingCursor {
                guard advanceCursor(safeCursor, accountID: accountID) else {
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

            let republishKeys = mergeResult.republishKeys
            for key in republishKeys {
                try SyncOutboxStore.ensurePending(key: key, in: modelContext)
            }

            let staleOutboxAcknowledged: Bool
            if case .remoteApplied = mergeResult,
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
                republishKeys: republishKeys,
                staleOutboxAcknowledged: staleOutboxAcknowledged,
            )
        } catch {
            modelContext.rollback()
            syncPullLogger.error("Sync pull could not apply a remote record")
            return .failed(
                key: record.key,
                serverRevision: record.serverRevision,
                reason: failureReason(for: error),
            )
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

    private func failureReason(for error: Error) -> SyncPullFailure {
        guard let error = error as? SyncLocalStoreError else {
            if error is SyncMetadataStoreError {
                return .metadata
            }
            return .persistence
        }

        switch error {
        case .immutableCollision:
            return .immutableCollision
        case .invalidPayload, .unsupportedPayloadSchema:
            return .invalidPayload
        case .inconsistentIdentity:
            return .invariantViolation
        case .missingEntity:
            return .persistence
        }
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
}
