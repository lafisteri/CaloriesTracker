import Foundation

struct DailyMacroGoal: Hashable, Codable, Sendable {
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double

    var nutrition: Nutrition {
        Nutrition(calories: calories, protein: protein, fat: fat, carbs: carbs)
    }

    var isValid: Bool {
        [calories, protein, fat, carbs].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

struct WeeklyGoal: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let effectiveFrom: LocalDay
    let dailyGoals: [LocalDay.Weekday: DailyMacroGoal]
    let createdAt: Date
}

struct WeeklyGoalDraft: Hashable, Sendable {
    let effectiveFrom: LocalDay
    let dailyGoals: [LocalDay.Weekday: DailyMacroGoal]
}

extension LocalDay.Weekday {
    var russianShortLabel: String {
        switch self {
        case .monday: "Пн"
        case .tuesday: "Вт"
        case .wednesday: "Ср"
        case .thursday: "Чт"
        case .friday: "Пт"
        case .saturday: "Сб"
        case .sunday: "Вс"
        }
    }

    var russianLabel: String {
        switch self {
        case .monday: "Понедельник"
        case .tuesday: "Вторник"
        case .wednesday: "Среда"
        case .thursday: "Четверг"
        case .friday: "Пятница"
        case .saturday: "Суббота"
        case .sunday: "Воскресенье"
        }
    }
}
