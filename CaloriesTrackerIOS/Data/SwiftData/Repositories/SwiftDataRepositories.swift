import Foundation
import SwiftData

@MainActor
final class SwiftDataProductRepository: ProductRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func product(id: UUID) async throws -> Product? {
        let descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.toDomain()
    }
}

@MainActor
final class SwiftDataRecipeRepository: RecipeRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func recipe(id: UUID) async throws -> Recipe? {
        let descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.toDomain()
    }
}

@MainActor
final class SwiftDataDiaryRepository: DiaryRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func entry(id: UUID) async throws -> DiaryEntry? {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
    }
}

@MainActor
final class SwiftDataGoalRepository: GoalRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func weeklyGoal(id: UUID) async throws -> WeeklyGoal? {
        let descriptor = FetchDescriptor<WeeklyGoalRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
    }
}
