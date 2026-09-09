import Foundation

struct DiaryContext: Hashable, Codable, Sendable {
    let day: LocalDay
    let mealID: UUID
}

struct FoodSourceReference: Hashable, Codable, Sendable {
    let sourceType: SourceType
    let sourceID: UUID
}

struct LatestDiaryUsage: Hashable, Sendable {
    let source: FoodSourceReference
    let amount: Double
    let unitToken: String
}

/// Nutrition and source fields are snapshots. They must not be automatically recalculated.
struct DiaryEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let day: LocalDay
    let mealID: UUID
    let sortOrder: Int
    let sourceType: SourceType
    let sourceID: UUID
    let sourceVersionID: UUID
    let sourceName: String
    let amount: Double
    let unitToken: String
    let nutrition: Nutrition
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

extension Sequence where Element == DiaryEntry {
    func nutritionTotal() throws -> Nutrition {
        try reduce(.zero) { total, entry in
            try total.adding(entry.nutrition)
        }
    }
}
