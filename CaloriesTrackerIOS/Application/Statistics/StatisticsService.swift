import Foundation

@MainActor
final class StatisticsService {
    private let diaryRepository: any DiaryRepository
    private let goalService: GoalService

    init(
        diaryRepository: any DiaryRepository,
        goalService: GoalService,
    ) {
        self.diaryRepository = diaryRepository
        self.goalService = goalService
    }

    func week(containing selectedDay: LocalDay) async throws -> WeekStatistics {
        let weekStart = selectedDay.mondayOfWeek()
        let days = weekStart.weekDaysMondayFirst()
        let entries = try await diaryRepository.entries(in: days)
        let goals = try await goalService.goals(for: days)
        let entriesByDay = Dictionary(grouping: entries, by: \.day)
        let today = LocalDay.current()

        let dayStatistics = days.map { day in
            let consumedNutrition = nutritionTotal(for: entriesByDay[day] ?? [])
            let calorieGoal = goals[day]?.dailyGoals[day.weekday()]?.calories
            let isFuture = day > today
            let calorieBalance = isFuture ? nil : calorieGoal.map { consumedNutrition.calories - $0 }

            return DayStatistics(
                day: day,
                weekday: day.weekday(),
                consumedNutrition: consumedNutrition,
                calorieGoal: calorieGoal,
                calorieBalance: calorieBalance,
                isFuture: isFuture,
            )
        }

        let weeklyCalorieBalance = dayStatistics
            .compactMap(\.calorieBalance)
            .reduce(nil as Double?) { partial, balance in
                (partial ?? 0) + balance
            }
        let weeklyNutrition = nutritionTotal(for: entries)

        return WeekStatistics(
            selectedDay: selectedDay,
            weekStart: weekStart,
            days: dayStatistics,
            weeklyCalorieBalance: weeklyCalorieBalance,
            macroDistribution: macroDistribution(for: weeklyNutrition),
        )
    }

    private func nutritionTotal(for entries: [DiaryEntry]) -> Nutrition {
        entries.reduce(.zero) { total, entry in
            total.adding(entry.nutrition)
        }
    }

    private func macroDistribution(for nutrition: Nutrition) -> MacroDistribution {
        let energyByNutrient: [(MacroNutrient, Double)] = [
            (.protein, nutrition.protein * 4),
            (.fat, nutrition.fat * 9),
            (.carbs, nutrition.carbs * 4),
        ]
        let totalEnergy = energyByNutrient.reduce(0) { $0 + $1.1 }
        let safeTotalEnergy = totalEnergy.isFinite && totalEnergy > 0 ? totalEnergy : 0

        return MacroDistribution(
            totalEnergy: safeTotalEnergy,
            components: energyByNutrient.map { nutrient, energy in
                let safeEnergy = energy.isFinite && energy >= 0 ? energy : 0
                return MacroDistributionComponent(
                    nutrient: nutrient,
                    energy: safeEnergy,
                    percentage: safeTotalEnergy > 0 ? safeEnergy / safeTotalEnergy * 100 : 0,
                )
            },
        )
    }
}
