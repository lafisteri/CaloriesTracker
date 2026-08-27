import Foundation

@MainActor
protocol ProductRepository: Sendable {
    func activeProducts(matching query: String) async throws -> [Product]
    func product(id: UUID, includingDeleted: Bool) async throws -> Product?
    func products(ids: Set<UUID>, includingDeleted: Bool) async throws -> [Product]
    func product(withBarcode barcode: String) async throws -> Product?
    func version(id: UUID) async throws -> ProductVersion?
    func versions(ids: Set<UUID>) async throws -> [ProductVersion]
    func versions(for productID: UUID) async throws -> [ProductVersion]
    func create(_ product: Product, initialVersion: ProductVersion) async throws
    func saveLogicalMetadata(_ product: Product) async throws
    func append(_ version: ProductVersion, settingCurrentVersionOf product: Product) async throws
    func softDeleteProduct(id: UUID, at: Date) async throws
}

@MainActor
protocol RecipeRepository: Sendable {
    func activeRecipes(matching query: String) async throws -> [Recipe]
    func recipe(id: UUID, includingDeleted: Bool) async throws -> Recipe?
    func version(id: UUID) async throws -> RecipeVersion?
    func versions(ids: Set<UUID>) async throws -> [RecipeVersion]
    func versions(for recipeID: UUID) async throws -> [RecipeVersion]
    func create(_ recipe: Recipe, initialVersion: RecipeVersion) async throws
    func saveLogicalMetadata(_ recipe: Recipe) async throws
    func append(_ version: RecipeVersion, settingCurrentVersionOf recipe: Recipe) async throws
    func softDeleteRecipe(id: UUID, at: Date) async throws
}

@MainActor
protocol DiaryRepository: Sendable {
    func entry(id: UUID, includingDeleted: Bool) async throws -> DiaryEntry?
    func entries(on day: LocalDay) async throws -> [DiaryEntry]
    func entries(in days: [LocalDay]) async throws -> [DiaryEntry]
    func activeEntries(for sources: [FoodSourceReference]) async throws -> [DiaryEntry]
    func latestActiveUsages(for sources: [FoodSourceReference]) async throws -> [LatestDiaryUsage]
    func create(_ entry: DiaryEntry) async throws
    func save(_ entry: DiaryEntry) async throws
    func rebaseSourceSnapshot(_ entry: DiaryEntry) async throws
    func save(_ entries: [DiaryEntry]) async throws
    func softDeleteEntry(id: UUID, at: Date) async throws
}

@MainActor
protocol GoalRepository: Sendable {
    func weeklyGoal(id: UUID) async throws -> WeeklyGoal?
    func latestGoal() async throws -> WeeklyGoal?
    func goal(effectiveOn day: LocalDay) async throws -> WeeklyGoal?
    func goals(effectiveOn days: [LocalDay]) async throws -> [LocalDay: WeeklyGoal]
    func save(draft: WeeklyGoalDraft, at timestamp: Date) async throws -> WeeklyGoal
}
