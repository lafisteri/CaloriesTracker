import Foundation

@MainActor
protocol ProductRepository: Sendable {
    func activeProducts(matching query: String) async throws -> [Product]
    func product(id: UUID, includingDeleted: Bool) async throws -> Product?
    func product(withBarcode barcode: String) async throws -> Product?
    func version(id: UUID) async throws -> ProductVersion?
    func versions(for productID: UUID) async throws -> [ProductVersion]
    func create(_ product: Product, initialVersion: ProductVersion) async throws
    func saveLogicalMetadata(_ product: Product) async throws
    func append(_ version: ProductVersion, settingCurrentVersionOf product: Product) async throws
    func softDeleteProduct(id: UUID, at: Date) async throws
}

@MainActor
protocol RecipeRepository: Sendable {
    func recipe(id: UUID) async throws -> Recipe?
}

@MainActor
protocol DiaryRepository: Sendable {
    func entry(id: UUID, includingDeleted: Bool) async throws -> DiaryEntry?
    func entries(on day: LocalDay) async throws -> [DiaryEntry]
    func create(_ entry: DiaryEntry) async throws
    func save(_ entry: DiaryEntry) async throws
    func save(_ entries: [DiaryEntry]) async throws
    func softDeleteEntry(id: UUID, at: Date) async throws
}

@MainActor
protocol GoalRepository: Sendable {
    func weeklyGoal(id: UUID) async throws -> WeeklyGoal?
}
