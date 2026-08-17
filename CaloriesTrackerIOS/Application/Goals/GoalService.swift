import Foundation

@MainActor
final class GoalService {
    private let repository: any GoalRepository

    init(repository: any GoalRepository) {
        self.repository = repository
    }

    func latestGoal() async throws -> WeeklyGoal? {
        try await repository.latestGoal()
    }

    func goal(for day: LocalDay) async throws -> WeeklyGoal? {
        try await repository.goal(effectiveOn: day)
    }

    func goals(for days: [LocalDay]) async throws -> [LocalDay: WeeklyGoal] {
        try await repository.goals(effectiveOn: days)
    }

    @discardableResult
    func create(draft: WeeklyGoalDraft) async throws -> UUID {
        try validate(draft)

        if let existingGoal = try await repository.goal(effectiveOn: draft.effectiveFrom),
           existingGoal.effectiveFrom == draft.effectiveFrom
        {
            throw GoalServiceError.duplicateEffectiveDate
        }

        let goal = WeeklyGoal(
            id: UUID(),
            effectiveFrom: draft.effectiveFrom,
            dailyGoals: draft.dailyGoals,
            createdAt: Date(),
        )

        do {
            try await repository.create(goal)
        } catch GoalRepositoryError.duplicateEffectiveDate {
            throw GoalServiceError.duplicateEffectiveDate
        }

        return goal.id
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
    case duplicateEffectiveDate

    var errorDescription: String? {
        switch self {
        case .incompleteWeek:
            "Заполните цели для всех дней недели."
        case .invalidValue:
            "Значения целей должны быть неотрицательными числами."
        case .duplicateEffectiveDate:
            "Цели с этой датой уже существуют. Выберите другую дату."
        }
    }
}
