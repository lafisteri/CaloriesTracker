import Foundation

@MainActor
protocol ProductRepository: Sendable {
    func product(id: UUID) async throws -> Product?
}

@MainActor
protocol RecipeRepository: Sendable {
    func recipe(id: UUID) async throws -> Recipe?
}

@MainActor
protocol DiaryRepository: Sendable {
    func entry(id: UUID) async throws -> DiaryEntry?
}

@MainActor
protocol GoalRepository: Sendable {
    func weeklyGoal(id: UUID) async throws -> WeeklyGoal?
}
