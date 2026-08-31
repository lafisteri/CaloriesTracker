import Foundation

struct WeekStatistics: Hashable, Sendable {
    let selectedDay: LocalDay
    let weekStart: LocalDay
    let days: [DayStatistics]
    let weeklyCalorieBalance: Double?
    let macroDistribution: MacroDistribution
}

struct DayStatistics: Identifiable, Hashable, Sendable {
    let day: LocalDay
    let weekday: LocalDay.Weekday
    let consumedNutrition: Nutrition
    let macroGoal: DailyMacroGoal?
    let calorieGoal: Double?
    let calorieBalance: Double?
    let isFuture: Bool

    var id: LocalDay {
        day
    }
}

enum MacroNutrient: CaseIterable, Hashable, Sendable {
    case protein
    case fat
    case carbs
}

struct MacroDistributionComponent: Identifiable, Hashable, Sendable {
    let nutrient: MacroNutrient
    let energy: Double
    let percentage: Double

    var id: MacroNutrient {
        nutrient
    }
}

struct MacroDistribution: Hashable, Sendable {
    let totalEnergy: Double
    let components: [MacroDistributionComponent]

    var hasEnergy: Bool {
        totalEnergy > 0
    }
}
