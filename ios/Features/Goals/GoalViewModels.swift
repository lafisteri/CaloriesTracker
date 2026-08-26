import Foundation
import Observation
import OSLog

struct GoalDayForm: Identifiable, Hashable {
    let weekday: LocalDay.Weekday
    var caloriesText = ""
    var proteinText = ""
    var fatText = ""
    var carbsText = ""

    var id: LocalDay.Weekday {
        weekday
    }
}

@MainActor
@Observable
final class GoalEditorViewModel {
    private let goalService: GoalService

    var effectiveFrom: LocalDay = .current()
    var days = LocalDay.Weekday.allCases.map { GoalDayForm(weekday: $0) }
    var applySourceWeekday: LocalDay.Weekday = .monday
    private(set) var isSaving = false
    var errorMessage: String?

    init(goalService: GoalService) {
        self.goalService = goalService
    }

    func setEffectiveFrom(_ date: Date) {
        effectiveFrom = .from(date)
    }

    func applyToAllDays() {
        guard let source = days.first(where: { $0.weekday == applySourceWeekday }) else {
            return
        }

        for index in days.indices {
            days[index].caloriesText = source.caloriesText
            days[index].proteinText = source.proteinText
            days[index].fatText = source.fatText
            days[index].carbsText = source.carbsText
        }
    }

    @discardableResult
    func save() async -> Bool {
        errorMessage = nil

        do {
            let draft = try makeDraft()
            isSaving = true
            try await goalService.create(draft: draft)
            isSaving = false
            return true
        } catch {
            isSaving = false
            errorMessage = goalErrorMessage(error, fallback: "Не удалось сохранить цели.")
            return false
        }
    }

    private func makeDraft() throws -> WeeklyGoalDraft {
        var dailyGoals: [LocalDay.Weekday: DailyMacroGoal] = [:]

        for day in days {
            dailyGoals[day.weekday] = DailyMacroGoal(
                calories: try numericValue(day.caloriesText, field: "Калории", weekday: day.weekday),
                protein: try numericValue(day.proteinText, field: "Белки", weekday: day.weekday),
                fat: try numericValue(day.fatText, field: "Жиры", weekday: day.weekday),
                carbs: try numericValue(day.carbsText, field: "Углеводы", weekday: day.weekday),
            )
        }

        return WeeklyGoalDraft(effectiveFrom: effectiveFrom, dailyGoals: dailyGoals)
    }

    private func numericValue(
        _ text: String,
        field: String,
        weekday: LocalDay.Weekday,
    ) throws -> Double {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw GoalEditorError.fieldRequired(field: field, weekday: weekday)
        }

        guard let number = EditableDecimal.value(from: value), number >= 0 else {
            throw GoalEditorError.invalidValue(field: field, weekday: weekday)
        }

        return number
    }
}

private enum GoalEditorError: LocalizedError {
    case fieldRequired(field: String, weekday: LocalDay.Weekday)
    case invalidValue(field: String, weekday: LocalDay.Weekday)

    var errorDescription: String? {
        switch self {
        case let .fieldRequired(field, weekday):
            "Заполните поле «\(field)» для \(weekday.russianShortLabel)."
        case let .invalidValue(field, weekday):
            "Введите неотрицательное число в поле «\(field)» для \(weekday.russianShortLabel)."
        }
    }
}

func goalErrorMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case let error as GoalServiceError:
        return error.errorDescription ?? fallback
    case let error as GoalEditorError:
        return error.errorDescription ?? fallback
    default:
        goalErrorLogger.error(
            "unexpected_user_facing_error fallback=\(fallback, privacy: .public) technical_error=\(String(reflecting: error), privacy: .public)",
        )
        return fallback
    }
}

private let goalErrorLogger = Logger(subsystem: "com.caloriestracker.ios", category: "Goals")
