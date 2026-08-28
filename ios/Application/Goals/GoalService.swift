import Foundation

@MainActor
final class GoalService {
    private let repository: any GoalRepository

    init(repository: any GoalRepository) {
        self.repository = repository
    }

    func goal(for day: LocalDay) async throws -> WeeklyGoal? {
        try await repository.goal(effectiveOn: day)
    }

    func goals(for days: [LocalDay]) async throws -> [LocalDay: WeeklyGoal] {
        try await repository.goals(effectiveOn: days)
    }

    @discardableResult
    func save(draft: WeeklyGoalDraft) async throws -> UUID {
        try validate(draft)
        return try await repository.save(draft: draft, at: Date()).id
    }

    private func validate(_ draft: WeeklyGoalDraft) throws {
        let expectedWeekdays = Set(LocalDay.Weekday.allCases)
        guard Set(draft.dailyGoals.keys) == expectedWeekdays else {
            throw GoalServiceError.incompleteWeek
        }
        guard draft.dailyGoals.values.allSatisfy(\.isValid) else {
            throw GoalServiceError.invalidValue
        }
    }
}

enum GoalServiceError: LocalizedError {
    case incompleteWeek
    case invalidValue

    var errorDescription: String? {
        switch self {
        case .incompleteWeek:
            "Заполните цели для всех дней недели."
        case .invalidValue:
            "Значения целей должны быть неотрицательными числами."
        }
    }
}
