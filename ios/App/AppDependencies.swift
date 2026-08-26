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

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema(versionedSchema: CaloriesTrackerSchemaV2.self)
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
        productRepository = SwiftDataProductRepository(modelContainer: modelContainer)
        recipeRepository = SwiftDataRecipeRepository(modelContainer: modelContainer)
        diaryRepository = SwiftDataDiaryRepository(modelContainer: modelContainer)
        goalRepository = SwiftDataGoalRepository(modelContainer: modelContainer)
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

        let supabaseClientProvider = SupabaseClientProvider.makeFromMainBundle()
        self.supabaseClientProvider = supabaseClientProvider
        supabaseAuth = supabaseClientProvider.map { SupabaseAuthService(client: $0.client) }
        supabaseSyncTransport = supabaseClientProvider.map { SupabaseSyncTransport(client: $0.client) }
    }
}
