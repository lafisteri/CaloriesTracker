import Foundation
import Observation
import OSLog
import SwiftData

enum SyncStatus: Equatable, Sendable {
    case disabled
    case signedOut
    case idle
    case syncing
    case waitingForRetry
    case blocked
}

enum SyncErrorCategory: Equatable, Sendable {
    case network
    case server
    case authentication
    case configuration
    case conflict
    case missingRemote
    case dependency
    case invariant
    case persistence
}

@MainActor
@Observable
final class SyncStatusStore {
    private(set) var status: SyncStatus = .idle
    private(set) var lastSuccessfulSyncAt: Date?
    private(set) var lastErrorCategory: SyncErrorCategory?

    func set(
        _ status: SyncStatus,
        errorCategory: SyncErrorCategory? = nil,
        succeededAt: Date? = nil,
    ) {
        self.status = status
        if let errorCategory {
            lastErrorCategory = errorCategory
        }
        if let succeededAt {
            lastSuccessfulSyncAt = succeededAt
            lastErrorCategory = nil
        }
    }
}

/// Typed, post-commit signal emitted by local SwiftData repositories only.
@MainActor
final class SyncChangeNotifier {
    private var handler: (() -> Void)?

    func setHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func localSyncableMutationCommitted() {
        handler?()
    }
}

private enum SyncWakeReason: Sendable {
    case active
    case sessionAvailable
    case localChange
    case periodic
    case retry
    case continuation
    case userRequested
}

private enum SyncRunOutcome: Sendable {
    case inactive
    case succeeded
    case signedOut
    case accountChanged
    case moreWork
    case retry(SyncErrorCategory)
    case blocked(SyncErrorCategory)
}

private let syncOrchestratorLogger = Logger(subsystem: "com.caloriestracker.ios", category: "SyncOrchestrator")

/// Actor-isolated, foreground-only orchestration around the existing sync coordinators.
actor SyncOrchestrator {
    static let localChangeDebounceNanoseconds: UInt64 = 1_800_000_000
    static let foregroundRefreshNanoseconds: UInt64 = 60_000_000_000
    static let retryDelaysNanoseconds: [UInt64] = [
        2_000_000_000,
        5_000_000_000,
        15_000_000_000,
        30_000_000_000,
        60_000_000_000,
    ]
    static let continuationDelayNanoseconds: UInt64 = 1_000_000_000
    static let maximumConvergenceCycles = 3

    private let modelContainer: ModelContainer
    private let authService: SupabaseAuthService
    private let bootstrapCoordinator: SyncBootstrapCoordinator
    private let pullCoordinator: SyncPullCoordinator
    private let pushCoordinator: SyncPushCoordinator
    private let statusStore: SyncStatusStore

    private var isForeground = false
    private var isRunning = false
    private var needsAnotherRun = false
    private var retryAttempt = 0
    private var debounceTask: Task<Void, Never>?
    private var continuationTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var observedAccountID: UUID?
    private var accountGeneration: UInt64 = 0

    init(
        modelContainer: ModelContainer,
        authService: SupabaseAuthService,
        bootstrapCoordinator: SyncBootstrapCoordinator,
        pullCoordinator: SyncPullCoordinator,
        pushCoordinator: SyncPushCoordinator,
        statusStore: SyncStatusStore,
    ) {
        self.modelContainer = modelContainer
        self.authService = authService
        self.bootstrapCoordinator = bootstrapCoordinator
        self.pullCoordinator = pullCoordinator
        self.pushCoordinator = pushCoordinator
        self.statusStore = statusStore
    }

    func applicationDidBecomeActive() {
        isForeground = true
        startPeriodicRefresh()
        requestRun(reason: .active)
    }

    func applicationDidLeaveActive() async {
        isForeground = false
        needsAnotherRun = false
        debounceTask?.cancel()
        debounceTask = nil
        continuationTask?.cancel()
        continuationTask = nil
        retryTask?.cancel()
        retryTask = nil
        periodicTask?.cancel()
        periodicTask = nil
        await setStatus(.idle)
    }

    /// Called after OTP verification; restored sessions are also picked up on activation.
    func authenticatedSessionDidBecomeAvailable() async {
        observeAccountIdentity(await currentAccountID())
        guard isForeground else {
            return
        }
        startPeriodicRefresh()
        requestRun(reason: .sessionAvailable)
    }

    /// Cancels scheduled work after the auth boundary has completed sign-out.
    func authenticatedSessionDidEnd() async {
        observeAccountIdentity(nil)
        needsAnotherRun = false
        debounceTask?.cancel()
        debounceTask = nil
        continuationTask?.cancel()
        continuationTask = nil
        retryTask?.cancel()
        retryTask = nil
        periodicTask?.cancel()
        periodicTask = nil
        await setStatus(.signedOut, errorCategory: .authentication)
    }

    /// Coalesces an explicit Settings-triggered sync into the existing single-flight run.
    func userRequestedSync() {
        retryTask?.cancel()
        retryTask = nil
        requestRun(reason: .userRequested)
    }

    func localSyncableMutationCommitted() {
        guard isForeground else {
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.localChangeDebounceNanoseconds)
            } catch {
                return
            }
            await self?.debounceElapsed()
        }
    }

    private func debounceElapsed() {
        debounceTask = nil
        requestRun(reason: .localChange)
    }

    private func startPeriodicRefresh() {
        guard periodicTask == nil else {
            return
        }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.foregroundRefreshNanoseconds)
                } catch {
                    return
                }
                await self?.periodicElapsed()
            }
        }
    }

    private func periodicElapsed() {
        guard isForeground else {
            return
        }
        requestRun(reason: .periodic)
    }

    private func requestRun(reason: SyncWakeReason) {
        guard isForeground else {
            return
        }
        if case .continuation = reason {
            // The task clears itself before waking this run.
        } else {
            continuationTask?.cancel()
            continuationTask = nil
        }
        guard !isRunning else {
            needsAnotherRun = true
            return
        }

        isRunning = true
        Task { [weak self] in
            await self?.performScheduledRuns()
        }
    }

    private func performScheduledRuns() async {
        defer {
            isRunning = false
            if isForeground, needsAnotherRun {
                needsAnotherRun = false
                requestRun(reason: .localChange)
            }
        }

        var runs = 0
        repeat {
            needsAnotherRun = false
            let outcome = await performOneRun()
            runs += 1

            switch outcome {
            case .inactive:
                return
            case .succeeded:
                retryAttempt = 0
                await setStatus(.idle, succeededAt: Date())
            case .signedOut:
                retryAttempt = 0
                await setStatus(.signedOut, errorCategory: .authentication)
                return
            case .accountChanged:
                retryAttempt = 0
                if await currentAccountID() == nil {
                    await setStatus(.signedOut, errorCategory: .authentication)
                } else {
                    await setStatus(.idle)
                }
                return
            case .moreWork:
                retryAttempt = 0
                scheduleContinuation()
                return
            case let .retry(category):
                scheduleRetry(for: category)
                return
            case let .blocked(category):
                await setStatus(.blocked, errorCategory: category)
                return
            }
        } while isForeground && needsAnotherRun && runs < 2
    }

    private func performOneRun() async -> SyncRunOutcome {
        guard isForeground else {
            return .inactive
        }
        let accountID: UUID
        do {
            guard let session = try await authService.currentSession() else {
                return .signedOut
            }
            accountID = session.userID
        } catch let error as SupabaseInfrastructureError {
            return outcome(for: error)
        } catch {
            return .retry(.server)
        }
        observeAccountIdentity(accountID)
        let expectedAccountGeneration = accountGeneration

        await setStatus(.syncing)

        let bootstrapReport: SyncBootstrapReport
        do {
            bootstrapReport = try await bootstrapCoordinator.bootstrapIfNeeded(expectedAccountID: accountID)
        } catch let error as SupabaseInfrastructureError {
            return outcome(for: error)
        } catch {
            return .blocked(.persistence)
        }
        guard isForeground else {
            return .inactive
        }
        guard await runIsStillCurrent(accountID, generation: expectedAccountGeneration) else {
            return .accountChanged
        }

        switch bootstrapReport.status {
        case .completed, .alreadyCompleted:
            break
        case .notAuthenticated:
            return .signedOut
        case .incompleteNeedsRetry:
            return bootstrapOutcome(for: bootstrapReport.blockingReason)
        case .blocked:
            return .blocked(category(for: bootstrapReport.blockingReason))
        }

        for _ in 0 ..< Self.maximumConvergenceCycles {
            let firstPull: SyncPullReport
            do {
                firstPull = try await pullCoordinator.pullIncrementally(expectedAccountID: accountID)
            } catch let error as SupabaseInfrastructureError {
                return outcome(for: error)
            } catch {
                return .blocked(.persistence)
            }
            guard isForeground else {
                return .inactive
            }
            guard await runIsStillCurrent(accountID, generation: expectedAccountGeneration) else {
                return .accountChanged
            }
            if let runFailure = firstPull.runFailure {
                return pullOutcome(for: runFailure)
            }
            if firstPull.failed > 0 {
                return .blocked(.invariant)
            }

            let push: SyncPushReport
            do {
                push = try await pushCoordinator.pushPending(expectedAccountID: accountID)
            } catch let error as SupabaseInfrastructureError {
                return outcome(for: error)
            } catch {
                return .blocked(.persistence)
            }
            guard isForeground else {
                return .inactive
            }
            guard await runIsStillCurrent(accountID, generation: expectedAccountGeneration) else {
                return .accountChanged
            }
            if let failure = pushFailureOutcome(push) {
                return failure
            }

            let finalPull: SyncPullReport
            do {
                finalPull = try await pullCoordinator.pullIncrementally(expectedAccountID: accountID)
            } catch let error as SupabaseInfrastructureError {
                return outcome(for: error)
            } catch {
                return .blocked(.persistence)
            }
            guard isForeground else {
                return .inactive
            }
            guard await runIsStillCurrent(accountID, generation: expectedAccountGeneration) else {
                return .accountChanged
            }
            if let runFailure = finalPull.runFailure {
                return pullOutcome(for: runFailure)
            }
            if finalPull.failed > 0 {
                return .blocked(.invariant)
            }

            // Deferred records mean their dependency has still not arrived
            // after Pull → Push → Pull. Advancing normal work would not resolve
            // this safely, so preserve the established blocker behavior.
            if finalPull.deferred > 0 {
                return .blocked(.dependency)
            }

            let pendingCount: Int
            do {
                pendingCount = try await pendingOutboxCount()
            } catch {
                return .blocked(.persistence)
            }
            guard await runIsStillCurrent(accountID, generation: expectedAccountGeneration) else {
                return .accountChanged
            }
            guard pendingCount == 0,
                  firstPull.caughtUpToRemoteState,
                  firstPull.deferred == 0,
                  finalPull.caughtUpToRemoteState,
                  finalPull.deferred == 0
            else {
                if push.missing > 0 {
                    return .blocked(.missingRemote)
                }
                continue
            }
            return .succeeded
        }

        // The bounded convergence budget was consumed while all work remained
        // otherwise healthy. Continue later; this is not an unresolved
        // dependency and must not surface as an attention-required state.
        return .moreWork
    }

    private func currentAccountID() async -> UUID? {
        do {
            return try await authService.currentSession()?.userID
        } catch {
            return nil
        }
    }

    private func observeAccountIdentity(_ accountID: UUID?) {
        guard observedAccountID != accountID else {
            return
        }
        observedAccountID = accountID
        accountGeneration &+= 1
        syncOrchestratorLogger.debug("Sync authenticated account identity changed; active runs are invalidated")
    }

    private func runIsStillCurrent(_ expectedAccountID: UUID, generation: UInt64) async -> Bool {
        guard accountGeneration == generation else {
            return false
        }
        let currentAccountID = await currentAccountID()
        observeAccountIdentity(currentAccountID)
        return accountGeneration == generation && currentAccountID == expectedAccountID
    }

    private func pendingOutboxCount() async throws -> Int {
        try await MainActor.run {
            let modelContext = ModelContext(modelContainer)
            return try SyncOutboxStore.pendingCount(in: modelContext)
        }
    }

    private func pushFailureOutcome(_ report: SyncPushReport) -> SyncRunOutcome? {
        for itemOutcome in report.outcomes {
            guard case let .failed(_, reason) = itemOutcome else {
                continue
            }
            if case let .transport(error) = reason {
                return outcome(for: error)
            }
            return .blocked(.persistence)
        }
        return nil
    }

    private func pullOutcome(for failure: SyncPullRunFailure) -> SyncRunOutcome {
        switch failure {
        case let .transport(error):
            outcome(for: error)
        case .cursorPersistence:
            .blocked(.persistence)
        }
    }

    private func bootstrapOutcome(for reason: SyncBootstrapBlockingReason?) -> SyncRunOutcome {
        switch reason {
        case let .transport(error), let .pullRunFailure(.transport(error)):
            return outcome(for: error)
        case .pullBoundReached, .pendingOutbox:
            return .moreWork
        case .pushConflict, .pushMissing, .remoteStateMissing, .pullDeferred:
            return .blocked(.dependency)
        case .none, .pullBlocked, .seedPersistence, .pushFailed, .pushPersistence, .metadata, .convergenceLimit,
             .pullRunFailure(.cursorPersistence):
            return .blocked(.invariant)
        }
    }

    private func outcome(for error: SupabaseInfrastructureError) -> SyncRunOutcome {
        switch error {
        case .accountChanged:
            .accountChanged
        case .notAuthenticated, .unauthorized:
            .signedOut
        case .network:
            .retry(.network)
        case .server:
            .retry(.server)
        case .notConfigured:
            .blocked(.configuration)
        case .decode, .invalidResponse:
            .blocked(.invariant)
        }
    }

    private func category(for reason: SyncBootstrapBlockingReason?) -> SyncErrorCategory {
        switch reason {
        case .pushConflict:
            .conflict
        case .pushMissing:
            .missingRemote
        case .pullDeferred, .pullBoundReached, .remoteStateMissing, .pendingOutbox:
            .dependency
        case .seedPersistence, .pushPersistence, .metadata:
            .persistence
        case let .transport(error), let .pullRunFailure(.transport(error)):
            switch outcome(for: error) {
            case let .retry(category), let .blocked(category):
                category
            case .inactive, .succeeded, .signedOut, .accountChanged, .moreWork:
                .authentication
            }
        case .none, .pullBlocked, .pushFailed, .convergenceLimit, .pullRunFailure(.cursorPersistence):
            .invariant
        }
    }

    private func scheduleRetry(for category: SyncErrorCategory) {
        guard isForeground else {
            return
        }
        guard retryAttempt < Self.retryDelaysNanoseconds.count else {
            Task { [statusStore] in
                await MainActor.run {
                    statusStore.set(.idle, errorCategory: category)
                }
            }
            return
        }

        let delay = Self.retryDelaysNanoseconds[retryAttempt]
        retryAttempt += 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            await self?.retryElapsed()
        }
        Task { [statusStore] in
            await MainActor.run {
                statusStore.set(.waitingForRetry, errorCategory: category)
            }
        }
    }

    private func retryElapsed() {
        retryTask = nil
        requestRun(reason: .retry)
    }

    private func scheduleContinuation() {
        guard isForeground, continuationTask == nil else {
            return
        }
        continuationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.continuationDelayNanoseconds)
            } catch {
                return
            }
            await self?.continuationElapsed()
        }
    }

    private func continuationElapsed() {
        continuationTask = nil
        requestRun(reason: .continuation)
    }

    private func setStatus(
        _ status: SyncStatus,
        errorCategory: SyncErrorCategory? = nil,
        succeededAt: Date? = nil,
    ) async {
        await MainActor.run {
            statusStore.set(status, errorCategory: errorCategory, succeededAt: succeededAt)
        }
    }
}
