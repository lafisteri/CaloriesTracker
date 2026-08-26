import Foundation
import OSLog
import SwiftData

enum SyncBootstrapCoordinatorError: Error, LocalizedError {
    case alreadyRunning
    case invalidMaximumRounds

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A sync bootstrap run is already in progress."
        case .invalidMaximumRounds:
            "The sync bootstrap round limit must be positive."
        }
    }
}

enum SyncBootstrapStatus: Equatable, Sendable {
    case alreadyCompleted
    case completed
    case incompleteNeedsRetry
    case blocked
    case notAuthenticated
}

enum SyncBootstrapBlockingReason: Equatable, Sendable {
    case transport(SupabaseInfrastructureError)
    case pullRunFailure(SyncPullRunFailure)
    case pullBlocked
    case pullDeferred
    case pullBoundReached
    case seedPersistence
    case pushConflict
    case pushMissing
    case pushFailed
    case pushPersistence
    case remoteStateMissing
    case pendingOutbox
    case metadata
    case convergenceLimit
}

struct SyncBootstrapReport: Equatable, Sendable {
    let status: SyncBootstrapStatus
    let rounds: Int
    let pulled: Int
    let pushed: Int
    let seeded: Int
    /// Nil means the coordinator intentionally made no local outbox scan (already-completed/no-session).
    let remainingOutbox: Int?
    let startingCursor: Int64?
    let endingCursor: Int64?
    let blockingReason: SyncBootstrapBlockingReason?
}

private struct SyncBootstrapReadiness {
    let cursor: Int64
    let missingRemoteStates: Int
    let pendingOutbox: Int

    var isComplete: Bool {
        missingRemoteStates == 0 && pendingOutbox == 0
    }
}

private let syncBootstrapLogger = Logger(subsystem: "com.caloriestracker.ios", category: "SyncBootstrap")

/// Explicit remote-first initial synchronization for one Supabase account.
@MainActor
final class SyncBootstrapCoordinator {
    static let defaultMaximumRounds = 10
    static let pushBatchSize = 200
    static let maximumPushBatchesPerRound = 5

    private let modelContainer: ModelContainer
    private let localStore: SyncLocalStore
    private let authService: SupabaseAuthService
    private let pullCoordinator: SyncPullCoordinator
    private let pushCoordinator: SyncPushCoordinator
    private var isBootstrapRunning = false

    init(
        modelContainer: ModelContainer,
        localStore: SyncLocalStore,
        authService: SupabaseAuthService,
        pullCoordinator: SyncPullCoordinator,
        pushCoordinator: SyncPushCoordinator,
    ) {
        self.modelContainer = modelContainer
        self.localStore = localStore
        self.authService = authService
        self.pullCoordinator = pullCoordinator
        self.pushCoordinator = pushCoordinator
    }

    /// Bootstraps only accounts that have not already reached convergence.
    func bootstrapIfNeeded(
        maximumRounds: Int = defaultMaximumRounds,
    ) async throws -> SyncBootstrapReport {
        guard maximumRounds > 0 else {
            throw SyncBootstrapCoordinatorError.invalidMaximumRounds
        }
        guard !isBootstrapRunning else {
            throw SyncBootstrapCoordinatorError.alreadyRunning
        }
        isBootstrapRunning = true
        defer { isBootstrapRunning = false }

        let accountID: UUID
        do {
            guard let session = try await authService.currentSession() else {
                return SyncBootstrapReport(
                    status: .notAuthenticated,
                    rounds: 0,
                    pulled: 0,
                    pushed: 0,
                    seeded: 0,
                    remainingOutbox: nil,
                    startingCursor: nil,
                    endingCursor: nil,
                    blockingReason: nil,
                )
            }
            accountID = session.userID
        } catch let error as SupabaseInfrastructureError {
            return SyncBootstrapReport(
                status: .incompleteNeedsRetry,
                rounds: 0,
                pulled: 0,
                pushed: 0,
                seeded: 0,
                remainingOutbox: nil,
                startingCursor: nil,
                endingCursor: nil,
                blockingReason: .transport(error),
            )
        } catch {
            return SyncBootstrapReport(
                status: .incompleteNeedsRetry,
                rounds: 0,
                pulled: 0,
                pushed: 0,
                seeded: 0,
                remainingOutbox: nil,
                startingCursor: nil,
                endingCursor: nil,
                blockingReason: .transport(.server),
            )
        }

        let startingCursor: Int64
        do {
            let modelContext = ModelContext(modelContainer)
            startingCursor = try SyncMetadataStore.pullCursor(accountID: accountID, in: modelContext)
            if try SyncMetadataStore.bootstrapCompleted(accountID: accountID, in: modelContext) {
                return SyncBootstrapReport(
                    status: .alreadyCompleted,
                    rounds: 0,
                    pulled: 0,
                    pushed: 0,
                    seeded: 0,
                    remainingOutbox: nil,
                    startingCursor: startingCursor,
                    endingCursor: startingCursor,
                    blockingReason: nil,
                )
            }
        } catch {
            syncBootstrapLogger.error("Sync bootstrap could not read account metadata")
            return SyncBootstrapReport(
                status: .blocked,
                rounds: 0,
                pulled: 0,
                pushed: 0,
                seeded: 0,
                remainingOutbox: nil,
                startingCursor: nil,
                endingCursor: nil,
                blockingReason: .metadata,
            )
        }

        var endingCursor = startingCursor
        var pulled = 0
        var pushed = 0
        var seeded = 0
        var remainingOutbox: Int?
        var lastReason: SyncBootstrapBlockingReason?

        syncBootstrapLogger.debug("Sync bootstrap started at cursor \(startingCursor, privacy: .public)")

        for round in 1 ... maximumRounds {
            let initialPull: SyncPullReport
            do {
                initialPull = try await pullCoordinator.pullIncrementally()
            } catch let error as SupabaseInfrastructureError {
                return report(
                    status: error == .notAuthenticated || error == .unauthorized ? .notAuthenticated : .incompleteNeedsRetry,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: error == .notAuthenticated || error == .unauthorized ? nil : .transport(error),
                )
            } catch {
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pullBlocked,
                )
            }
            pulled += initialPull.processed
            endingCursor = initialPull.endingCursor

            if let runFailure = initialPull.runFailure {
                return report(
                    status: .incompleteNeedsRetry,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pullRunFailure(runFailure),
                )
            }
            if initialPull.failed > 0 {
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pullBlocked,
                )
            }
            // Remote-first means a bounded pull continues in a later round before
            // inspecting local pre-sync data for upload.
            guard initialPull.caughtUpToRemoteState else {
                lastReason = .pullBoundReached
                continue
            }

            let newlySeeded: Int
            do {
                newlySeeded = try seedUnknownLocalEntities(accountID: accountID)
            } catch {
                syncBootstrapLogger.error("Sync bootstrap could not seed the outbox")
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .seedPersistence,
                )
            }
            seeded += newlySeeded

            let pushBatchResult: (pushed: Int, reason: SyncBootstrapBlockingReason?)
            do {
                pushBatchResult = try await pushPendingBatches()
                pushed += pushBatchResult.pushed
            } catch let error as SupabaseInfrastructureError {
                return report(
                    status: error == .notAuthenticated || error == .unauthorized ? .notAuthenticated : .incompleteNeedsRetry,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: error == .notAuthenticated || error == .unauthorized ? nil : .transport(error),
                )
            } catch {
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pushPersistence,
                )
            }

            let finalPull: SyncPullReport
            do {
                finalPull = try await pullCoordinator.pullIncrementally()
            } catch let error as SupabaseInfrastructureError {
                return report(
                    status: error == .notAuthenticated || error == .unauthorized ? .notAuthenticated : .incompleteNeedsRetry,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: error == .notAuthenticated || error == .unauthorized ? nil : .transport(error),
                )
            } catch {
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pullBlocked,
                )
            }
            pulled += finalPull.processed
            endingCursor = finalPull.endingCursor

            if let runFailure = finalPull.runFailure {
                return report(
                    status: .incompleteNeedsRetry,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pullRunFailure(runFailure),
                )
            }
            if finalPull.failed > 0 {
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .pullBlocked,
                )
            }
            if !finalPull.caughtUpToRemoteState {
                lastReason = .pullBoundReached
                continue
            }
            if finalPull.deferred > 0 {
                lastReason = .pullDeferred
                continue
            }

            let readiness: SyncBootstrapReadiness
            do {
                readiness = try completeIfReady(accountID: accountID)
            } catch {
                syncBootstrapLogger.error("Sync bootstrap could not persist completion state")
                return report(
                    status: .blocked,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: .metadata,
                )
            }
            endingCursor = readiness.cursor
            remainingOutbox = readiness.pendingOutbox
            if readiness.isComplete {
                return report(
                    status: .completed,
                    rounds: round,
                    pulled: pulled,
                    pushed: pushed,
                    seeded: seeded,
                    remainingOutbox: remainingOutbox,
                    startingCursor: startingCursor,
                    endingCursor: endingCursor,
                    reason: nil,
                )
            }

            if readiness.pendingOutbox > 0 {
                lastReason = pushBatchResult.reason ?? .pendingOutbox
            } else if readiness.missingRemoteStates > 0 {
                lastReason = .remoteStateMissing
            }
        }

        let finalReadiness = try? readiness(accountID: accountID)
        return report(
            status: .incompleteNeedsRetry,
            rounds: maximumRounds,
            pulled: pulled,
            pushed: pushed,
            seeded: seeded,
            remainingOutbox: finalReadiness?.pendingOutbox ?? remainingOutbox,
            startingCursor: startingCursor,
            endingCursor: finalReadiness?.cursor ?? endingCursor,
            reason: lastReason ?? .convergenceLimit,
        )
    }

    /// One local scan and one account-scoped remote-state scan seed all pre-sync entities.
    private func seedUnknownLocalEntities(accountID: UUID) throws -> Int {
        let modelContext = ModelContext(modelContainer)
        do {
            let localKeys = try localStore.syncEntityKeys(in: modelContext)
            let knownRemoteKeys = try SyncMetadataStore.remoteEntityKeys(accountID: accountID, in: modelContext)
            let unknownKeys = localKeys.filter { !knownRemoteKeys.contains($0) }
            var created = 0
            for key in unknownKeys where try SyncOutboxStore.ensurePending(key: key, in: modelContext) {
                created += 1
            }
            if created > 0 {
                try modelContext.save()
            }
            return created
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Stops after a non-accepted push outcome so conflicts are never blindly retried in the same pass.
    private func pushPendingBatches() async throws -> (pushed: Int, reason: SyncBootstrapBlockingReason?) {
        var pushed = 0
        for _ in 0 ..< Self.maximumPushBatchesPerRound {
            let report = try await pushCoordinator.pushPending(limit: Self.pushBatchSize)
            pushed += report.accepted + report.acceptedButStillPending
            if report.conflicts > 0 {
                return (pushed, .pushConflict)
            }
            if report.missing > 0 {
                return (pushed, .pushMissing)
            }
            if report.failed > 0 || report.acceptedButStillPending > 0 {
                return (pushed, .pushFailed)
            }
            if report.attempted < Self.pushBatchSize {
                return (pushed, nil)
            }
        }
        return (pushed, .pendingOutbox)
    }

    /// Rechecks completion predicates and writes the account completion marker in one local save.
    private func completeIfReady(accountID: UUID) throws -> SyncBootstrapReadiness {
        let modelContext = ModelContext(modelContainer)
        do {
            let localKeys = try localStore.syncEntityKeys(in: modelContext)
            let knownRemoteKeys = try SyncMetadataStore.remoteEntityKeys(accountID: accountID, in: modelContext)
            let pendingOutbox = try SyncOutboxStore.pendingCount(in: modelContext)
            let cursor = try SyncMetadataStore.pullCursor(accountID: accountID, in: modelContext)
            let readiness = SyncBootstrapReadiness(
                cursor: cursor,
                missingRemoteStates: localKeys.count(where: { !knownRemoteKeys.contains($0) }),
                pendingOutbox: pendingOutbox,
            )
            guard readiness.isComplete else {
                return readiness
            }

            try SyncMetadataStore.markBootstrapCompleted(accountID: accountID, in: modelContext)
            try modelContext.save()
            return readiness
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func readiness(accountID: UUID) throws -> SyncBootstrapReadiness {
        let modelContext = ModelContext(modelContainer)
        let localKeys = try localStore.syncEntityKeys(in: modelContext)
        let knownRemoteKeys = try SyncMetadataStore.remoteEntityKeys(accountID: accountID, in: modelContext)
        return SyncBootstrapReadiness(
            cursor: try SyncMetadataStore.pullCursor(accountID: accountID, in: modelContext),
            missingRemoteStates: localKeys.count(where: { !knownRemoteKeys.contains($0) }),
            pendingOutbox: try SyncOutboxStore.pendingCount(in: modelContext),
        )
    }

    private func report(
        status: SyncBootstrapStatus,
        rounds: Int,
        pulled: Int,
        pushed: Int,
        seeded: Int,
        remainingOutbox: Int?,
        startingCursor: Int64?,
        endingCursor: Int64?,
        reason: SyncBootstrapBlockingReason?,
    ) -> SyncBootstrapReport {
        SyncBootstrapReport(
            status: status,
            rounds: rounds,
            pulled: pulled,
            pushed: pushed,
            seeded: seeded,
            remainingOutbox: remainingOutbox,
            startingCursor: startingCursor,
            endingCursor: endingCursor,
            blockingReason: reason,
        )
    }
}
