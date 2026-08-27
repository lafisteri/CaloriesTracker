import SwiftData

@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let productRepository: any ProductRepository
    let recipeRepository: any RecipeRepository
    let diaryRepository: any DiaryRepository
    let goalRepository: any GoalRepository
    let productService: ProductService
    let recipeService: RecipeService
    let diaryService: DiaryService
    let goalService: GoalService
    let statisticsService: StatisticsService
    let supabaseClientProvider: SupabaseClientProvider?
    let supabaseAuth: SupabaseAuthService?
    let supabaseSyncTransport: SupabaseSyncTransport?
    let syncLocalStore: SyncLocalStore
    let syncPushCoordinator: SyncPushCoordinator?
    let syncPullCoordinator: SyncPullCoordinator?
    let syncBootstrapCoordinator: SyncBootstrapCoordinator?
    let syncChangeNotifier: SyncChangeNotifier?
    let syncStatus: SyncStatusStore?
    let syncOrchestrator: SyncOrchestrator?

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema(versionedSchema: CaloriesTrackerSchemaV5.self)
        let configuration = ModelConfiguration(
            "CaloriesTracker",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none,
        )
        let modelContainer = try ModelContainer(
            for: schema,
            migrationPlan: CaloriesTrackerMigrationPlan.self,
            configurations: configuration,
        )

        self.modelContainer = modelContainer
        let syncLocalStore = SyncLocalStore(modelContainer: modelContainer)
        self.syncLocalStore = syncLocalStore
        let supabaseClientProvider = SupabaseClientProvider.makeFromMainBundle()
        let syncChangeNotifier = supabaseClientProvider.map { _ in SyncChangeNotifier() }
        self.syncChangeNotifier = syncChangeNotifier
        productRepository = SwiftDataProductRepository(
            modelContainer: modelContainer,
            syncChangeNotifier: syncChangeNotifier,
        )
        recipeRepository = SwiftDataRecipeRepository(
            modelContainer: modelContainer,
            syncChangeNotifier: syncChangeNotifier,
        )
        diaryRepository = SwiftDataDiaryRepository(
            modelContainer: modelContainer,
            syncChangeNotifier: syncChangeNotifier,
        )
        goalRepository = SwiftDataGoalRepository(
            modelContainer: modelContainer,
            syncChangeNotifier: syncChangeNotifier,
        )
        productService = ProductService(repository: productRepository)
        recipeService = RecipeService(
            recipeRepository: recipeRepository,
            productRepository: productRepository,
        )
        diaryService = DiaryService(
            diaryRepository: diaryRepository,
            productRepository: productRepository,
            recipeRepository: recipeRepository,
        )
        let goalService = GoalService(repository: goalRepository)
        self.goalService = goalService
        statisticsService = StatisticsService(
            diaryRepository: diaryRepository,
            goalService: goalService,
        )

        let supabaseAuth = supabaseClientProvider.map { SupabaseAuthService(client: $0.client) }
        let supabaseSyncTransport = supabaseClientProvider.map { SupabaseSyncTransport(client: $0.client) }
        self.supabaseClientProvider = supabaseClientProvider
        self.supabaseAuth = supabaseAuth
        self.supabaseSyncTransport = supabaseSyncTransport
        if let supabaseAuth, let supabaseSyncTransport {
            let syncPushCoordinator = SyncPushCoordinator(
                modelContainer: modelContainer,
                localStore: syncLocalStore,
                authService: supabaseAuth,
                transport: supabaseSyncTransport,
            )
            let syncPullCoordinator = SyncPullCoordinator(
                modelContainer: modelContainer,
                localStore: syncLocalStore,
                authService: supabaseAuth,
                transport: supabaseSyncTransport,
            )
            self.syncPushCoordinator = syncPushCoordinator
            self.syncPullCoordinator = syncPullCoordinator
            let syncBootstrapCoordinator = SyncBootstrapCoordinator(
                modelContainer: modelContainer,
                localStore: syncLocalStore,
                authService: supabaseAuth,
                pullCoordinator: syncPullCoordinator,
                pushCoordinator: syncPushCoordinator,
            )
            self.syncBootstrapCoordinator = syncBootstrapCoordinator
            let syncStatus = SyncStatusStore()
            let syncOrchestrator = SyncOrchestrator(
                modelContainer: modelContainer,
                authService: supabaseAuth,
                bootstrapCoordinator: syncBootstrapCoordinator,
                pullCoordinator: syncPullCoordinator,
                pushCoordinator: syncPushCoordinator,
                statusStore: syncStatus,
            )
            self.syncStatus = syncStatus
            self.syncOrchestrator = syncOrchestrator
            syncChangeNotifier?.setHandler {
                Task {
                    await syncOrchestrator.localSyncableMutationCommitted()
                }
            }
            Task {
                await supabaseAuth.setSessionLifecycleHandlers(
                    onSessionAvailable: {
                        await syncOrchestrator.authenticatedSessionDidBecomeAvailable()
                    },
                    onSessionEnded: {
                        await syncOrchestrator.authenticatedSessionDidEnd()
                    },
                )
            }
        } else {
            syncPushCoordinator = nil
            syncPullCoordinator = nil
            syncBootstrapCoordinator = nil
            syncStatus = nil
            syncOrchestrator = nil
        }
    }
}
