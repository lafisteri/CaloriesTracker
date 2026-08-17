import Foundation

struct DailyMacroGoal: Hashable, Codable, Sendable {
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double

    var nutrition: Nutrition {
        Nutrition(calories: calories, protein: protein, fat: fat, carbs: carbs)
    }
}

struct WeeklyGoal: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let effectiveFrom: LocalDay
    let dailyGoals: [LocalDay.Weekday: DailyMacroGoal]
    let createdAt: Date
}
