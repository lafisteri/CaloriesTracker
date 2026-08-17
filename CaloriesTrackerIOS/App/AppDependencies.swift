import SwiftData

@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let productRepository: any ProductRepository
    let recipeRepository: any RecipeRepository
    let diaryRepository: any DiaryRepository
    let goalRepository: any GoalRepository
    let productService: ProductService

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema(versionedSchema: CaloriesTrackerSchemaV1.self)
        let configuration = ModelConfiguration(
            "CaloriesTracker",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
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
    }
}
