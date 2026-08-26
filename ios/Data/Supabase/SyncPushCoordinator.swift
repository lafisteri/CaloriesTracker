import Foundation
import OSLog
import SwiftData

enum SyncPushCoordinatorError: Error, LocalizedError {
    case alreadyRunning
    case pendingReadFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A sync push run is already in progress."
        case .pendingReadFailed:
            "Pending sync changes could not be read."
        }
    }
}

enum SyncPushFailure: Equatable, Sendable {
    case payloadExport
    case metadata
    case persistence
    case transport(SupabaseInfrastructureError)
}

enum SyncPushItemOutcome: Equatable, Sendable {
    case accepted(key: SyncEntityKey, serverRevision: Int64)
    case acceptedButStillPending(key: SyncEntityKey, serverRevision: Int64)
    case conflict(key: SyncEntityKey, remoteRecord: SupabaseRemoteSyncRecord)
    case missingRemote(key: SyncEntityKey)
    case failed(key: SyncEntityKey, reason: SyncPushFailure)
}

struct SyncPushReport: Equatable, Sendable {
    let outcomes: [SyncPushItemOutcome]

    var attempted: Int { outcomes.count }
    var accepted: Int { outcomes.count(where: { if case .accepted = $0 { true } else { false } }) }
    var acceptedButStillPending: Int {
        outcomes.count(where: { if case .acceptedButStillPending = $0 { true } else { false } })
    }
    var conflicts: Int { outcomes.count(where: { if case .conflict = $0 { true } else { false } }) }
    var missing: Int { outcomes.count(where: { if case .missingRemote = $0 { true } else { false } }) }
    var failed: Int { outcomes.count(where: { if case .failed = $0 { true } else { false } }) }
}

private let syncPushLogger = Logger(subsystem: "com.caloriestracker.ios", category: "SyncPush")

/// Explicit, push-only infrastructure. It is never scheduled automatically.
@MainActor
final class SyncPushCoordinator {
    private let modelContainer: ModelContainer
    private let localStore: SyncLocalStore
    private let authService: SupabaseAuthService
    private let transport: SupabaseSyncTransport
    private var isPushRunning = false

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

    /// Pushes at most `limit` existing outbox items in stable order.
    func pushPending(limit: Int = SyncOutboxStore.defaultPendingLimit) async throws -> SyncPushReport {
        guard !isPushRunning else {
            throw SyncPushCoordinatorError.alreadyRunning
        }
        isPushRunning = true
        defer { isPushRunning = false }

        guard let session = try await authService.currentSession() else {
            throw SupabaseInfrastructureError.notAuthenticated
        }
        let accountID = session.userID
        let pendingItems: [SyncOutboxItem]
        do {
            let modelContext = ModelContext(modelContainer)
            pendingItems = try SyncOutboxStore.pending(limit: limit, in: modelContext)
        } catch {
            syncPushLogger.error("Sync push could not read pending items")
            throw SyncPushCoordinatorError.pendingReadFailed
        }

        syncPushLogger.debug("Sync push run started with \(pendingItems.count, privacy: .public) items")
        var outcomes: [SyncPushItemOutcome] = []
        outcomes.reserveCapacity(pendingItems.count)

        for item in pendingItems {
            let outcome = try await push(item, accountID: accountID)
            outcomes.append(outcome)
        }

        let report = SyncPushReport(outcomes: outcomes)
        syncPushLogger.debug(
            "Sync push summary attempted=\(report.attempted, privacy: .public) accepted=\(report.accepted, privacy: .public) stillPending=\(report.acceptedButStillPending, privacy: .public) conflicts=\(report.conflicts, privacy: .public) missing=\(report.missing, privacy: .public) failed=\(report.failed, privacy: .public)",
        )
        return report
    }

    private func push(
        _ item: SyncOutboxItem,
        accountID: UUID,
    ) async throws -> SyncPushItemOutcome {
        let envelope: SyncPayloadEnvelope
        do {
            // All values are captured before the network await; no model objects cross it.
            envelope = try localStore.envelope(for: item.entityKey)
            guard envelope.payload.key == item.entityKey else {
                syncPushLogger.error("Sync push payload identity mismatch")
                return .failed(key: item.entityKey, reason: .payloadExport)
            }
        } catch {
            syncPushLogger.error("Sync push payload preparation failed")
            return .failed(key: item.entityKey, reason: .payloadExport)
        }

        let expectedServerRevision: Int64?
        do {
            let modelContext = ModelContext(modelContainer)
            expectedServerRevision = try SyncMetadataStore.remoteRevision(
                accountID: accountID,
                entityKey: item.entityKey,
                in: modelContext,
            )
        } catch {
            syncPushLogger.error("Sync push metadata preparation failed")
            return .failed(key: item.entityKey, reason: .metadata)
        }

        do {
            let result = try await transport.push(
                key: item.entityKey,
                envelope: envelope,
                expectedServerRevision: expectedServerRevision,
            )
            switch result {
            case let .accepted(remoteRecord):
                return commitAccepted(
                    remoteRecord,
                    item: item,
                    accountID: accountID,
                )
            case let .conflict(remoteRecord):
                syncPushLogger.debug("Sync push conflict")
                return .conflict(key: item.entityKey, remoteRecord: remoteRecord)
            case .missing:
                syncPushLogger.debug("Sync push missing remote record")
                return .missingRemote(key: item.entityKey)
            }
        } catch let error as SupabaseInfrastructureError {
            if error == .notAuthenticated || error == .unauthorized {
                syncPushLogger.error("Sync push stopped because authentication is unavailable")
                throw error
            }
            syncPushLogger.error("Sync push transport failure")
            return .failed(key: item.entityKey, reason: .transport(error))
        } catch {
            syncPushLogger.error("Sync push transport failure")
            return .failed(key: item.entityKey, reason: .transport(.server))
        }
    }

    private func commitAccepted(
        _ remoteRecord: SupabaseRemoteSyncRecord,
        item: SyncOutboxItem,
        accountID: UUID,
    ) -> SyncPushItemOutcome {
        guard remoteRecord.key == item.entityKey else {
            syncPushLogger.error("Sync push accepted an inconsistent entity key")
            return .failed(key: item.entityKey, reason: .metadata)
        }

        let modelContext = ModelContext(modelContainer)
        do {
            try SyncMetadataStore.setRemoteRevision(
                remoteRecord.serverRevision,
                accountID: accountID,
                entityKey: item.entityKey,
                in: modelContext,
            )
        } catch {
            syncPushLogger.error("Sync push could not persist remote revision metadata")
            return .failed(key: item.entityKey, reason: .metadata)
        }

        do {
            let acknowledged = try SyncOutboxStore.acknowledge(
                key: item.key,
                token: item.changeToken,
                in: modelContext,
            )
            try modelContext.save()
            if acknowledged {
                syncPushLogger.debug("Sync push item accepted")
                return .accepted(key: item.entityKey, serverRevision: remoteRecord.serverRevision)
            }

            syncPushLogger.debug("Sync push item accepted but remains pending after a concurrent edit")
            return .acceptedButStillPending(
                key: item.entityKey,
                serverRevision: remoteRecord.serverRevision,
            )
        } catch {
            // Do not claim either metadata or acknowledgement persisted when this save fails.
            syncPushLogger.error("Sync push accepted item could not be saved locally")
            return .failed(key: item.entityKey, reason: .persistence)
        }
    }
}
