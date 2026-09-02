import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class TodayViewModel {
    private let diaryService: DiaryService
    private let goalService: GoalService

    private(set) var selectedDay: LocalDay
    private(set) var day: DiaryDayReadModel?
    private(set) var dailyGoal: DailyMacroGoal?
    private(set) var isLoading = false
    var errorMessage: String?
    private var currentLoadID: UUID?

    init(
        diaryService: DiaryService,
        goalService: GoalService,
        selectedDay: LocalDay = .current(),
    ) {
        self.diaryService = diaryService
        self.goalService = goalService
        self.selectedDay = selectedDay
    }

    func load() async {
        let loadID = UUID()
        let requestedDay = selectedDay
        currentLoadID = loadID
        isLoading = true
        errorMessage = nil
        day = nil
        dailyGoal = nil

        do {
            let loadedDay = try await diaryService.day(for: requestedDay)
            let loadedGoal = try await goalService.goal(for: requestedDay)

            guard currentLoadID == loadID else {
                return
            }

            day = loadedDay
            dailyGoal = loadedGoal?.dailyGoals[requestedDay.weekday()]
        } catch {
            guard currentLoadID == loadID else {
                return
            }

            day = nil
            dailyGoal = nil
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось загрузить дневник.")
        }

        if currentLoadID == loadID {
            isLoading = false
        }
    }

    func previousDay() async {
        selectedDay = selectedDay.previousDay()
        await load()
    }

    func nextDay() async {
        selectedDay = selectedDay.nextDay()
        await load()
    }

    func goToToday() async {
        selectedDay = .current()
        await load()
    }

    func quickAdd(
        context: DiaryContext,
        source: FoodSourceReference,
        defaultValue: FoodSelectionAmountDefault,
    ) async throws {
        try await diaryService.quickAdd(
            context: context,
            source: source,
            preferredAmount: defaultValue.amount,
            preferredUnitToken: defaultValue.unitToken,
        )
    }

    func delete(entryID: UUID) async {
        errorMessage = nil

        do {
            try await diaryService.softDelete(entryID: entryID)
            await load()
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось удалить запись.")
        }
    }

    func reorder(meal: MealType, orderedEntryIDs: [UUID]) async {
        errorMessage = nil

        do {
            try await diaryService.reorder(day: selectedDay, meal: meal, orderedEntryIDs: orderedEntryIDs)
            await load()
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось изменить порядок записей.")
        }
    }

    func move(
        entryID: UUID,
        to meal: MealType,
        displayedTargetIndex: Int,
    ) async {
        errorMessage = nil

        do {
            let targetIndex = targetIndex(
                for: entryID,
                movingTo: meal,
                displayedTargetIndex: displayedTargetIndex,
            )
            try await diaryService.move(
                MoveDiaryEntryCommand(entryID: entryID, targetMeal: meal, targetIndex: targetIndex),
            )
            await load()
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось переместить запись.")
        }
    }

    private func targetIndex(
        for entryID: UUID,
        movingTo targetMeal: MealType,
        displayedTargetIndex: Int,
    ) -> Int {
        guard displayedTargetIndex >= 0,
              let day,
              let sourceMeal = day.meals.first(where: { meal in
                  meal.entries.contains(where: { $0.id == entryID })
              }),
              sourceMeal.mealType == targetMeal,
              let sourceIndex = sourceMeal.entries.firstIndex(where: { $0.id == entryID })
        else {
            return displayedTargetIndex
        }

        return sourceIndex < displayedTargetIndex ? displayedTargetIndex - 1 : displayedTargetIndex
    }
}

enum DiaryAmountEditorMode: Hashable, Sendable {
    case create(context: DiaryContext, source: FoodSourceReference, selectionDefault: FoodSelectionAmountDefault?)
    case edit(entryID: UUID)
}

@MainActor
@Observable
final class AmountViewModel {
    private let diaryService: DiaryService
    let mode: DiaryAmountEditorMode

    private(set) var source: DiaryAmountSource?
    var amountText = ""
    var selectedUnitToken = ""
    private(set) var preview: Nutrition?
    private(set) var previewErrorMessage: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isProductEditRefreshBlocked = false
    var errorMessage: String?

    init(mode: DiaryAmountEditorMode, diaryService: DiaryService) {
        self.mode = mode
        self.diaryService = diaryService
    }

    var actionTitle: String {
        switch mode {
        case .create: "Добавить"
        case .edit: "Сохранить"
        }
    }

    var isSourceAvailable: Bool {
        source != nil && !isProductEditRefreshBlocked
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        isProductEditRefreshBlocked = false

        do {
            switch mode {
            case let .create(_, sourceReference, _):
                source = try await diaryService.amountSource(for: sourceReference)
            case let .edit(entryID):
                source = try await diaryService.amountSource(forEntryID: entryID)
            }

            guard let source else {
                return
            }
            switch mode {
            case let .create(_, _, selectionDefault):
                if let selectionDefault,
                   selectionDefault.amount.isFinite,
                   selectionDefault.amount > 0,
                   source.unitOptions.contains(where: { $0.token == selectionDefault.unitToken }) {
                    amountText = EditableDecimal.string(from: selectionDefault.amount)
                    selectedUnitToken = selectionDefault.unitToken
                } else {
                    selectedUnitToken = source.initialUnitToken
                    amountText = EditableDecimal.string(from: FoodAmountDefaults.fallbackAmount(for: selectedUnitToken))
                }
            case .edit:
                amountText = source.initialAmount.map { EditableDecimal.string(from: $0) } ?? ""
                selectedUnitToken = source.initialUnitToken
            }
            refreshPreview()
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось загрузить источник.")
        }
    }

    func beginProductEditRefresh() {
        isLoading = true
        isProductEditRefreshBlocked = true
        errorMessage = nil
        preview = nil
        previewErrorMessage = nil
    }

    @discardableResult
    func refreshAfterProductEdit() async -> Bool {
        if !isProductEditRefreshBlocked {
            beginProductEditRefresh()
        }

        defer { isLoading = false }

        do {
            switch mode {
            case let .create(_, sourceReference, _):
                let refreshedSource = try await diaryService.amountSource(for: sourceReference)
                source = refreshedSource
                if !refreshedSource.unitOptions.contains(where: { $0.token == selectedUnitToken }) {
                    selectedUnitToken = refreshedSource.initialUnitToken
                }
            case let .edit(entryID):
                try await diaryService.rebaseEntryToCurrentProduct(entryID: entryID)
                let refreshedSource = try await diaryService.amountSource(forEntryID: entryID)
                source = refreshedSource
                amountText = refreshedSource.initialAmount.map { EditableDecimal.string(from: $0) } ?? ""
                selectedUnitToken = refreshedSource.initialUnitToken
            }

            isProductEditRefreshBlocked = false
            refreshPreview()
            return true
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось обновить продукт в записи. Повторите попытку.")
            return false
        }
    }

    func refreshPreview() {
        guard let source else {
            return
        }
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAmount.isEmpty else {
            preview = nil
            previewErrorMessage = nil
            return
        }
        guard let amount = EditableDecimal.value(from: trimmedAmount), amount > 0 else {
            preview = nil
            previewErrorMessage = "Количество должно быть больше нуля."
            return
        }

        do {
            preview = try diaryService.preview(
                source: source,
                amount: amount,
                unitToken: selectedUnitToken,
            )
            previewErrorMessage = nil
        } catch {
            preview = nil
            previewErrorMessage = diaryErrorMessage(error, fallback: "Не удалось рассчитать КБЖУ.")
        }
    }

    @discardableResult
    func save() async -> Bool {
        guard !isSaving else {
            return false
        }
        errorMessage = nil

        guard !isProductEditRefreshBlocked else {
            errorMessage = "Не удалось обновить продукт в записи. Повторите попытку."
            return false
        }

        guard let amount = parsedPositiveAmount() else {
            return false
        }

        isSaving = true
        do {
            switch mode {
            case let .create(context, source, _):
                try await diaryService.create(
                    CreateDiaryEntryCommand(
                        context: context,
                        source: source,
                        amount: amount,
                        unitToken: selectedUnitToken,
                    ),
                )
            case let .edit(entryID):
                try await diaryService.updateAmount(
                    UpdateDiaryEntryAmountCommand(
                        entryID: entryID,
                        amount: amount,
                        unitToken: selectedUnitToken,
                    ),
                )
            }
            isSaving = false
            return true
        } catch {
            isSaving = false
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось сохранить запись.")
            return false
        }
    }

    private func parsedPositiveAmount() -> Double? {
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAmount.isEmpty else {
            errorMessage = "Введите количество."
            return nil
        }
        guard let amount = EditableDecimal.value(from: trimmedAmount), amount > 0 else {
            errorMessage = "Количество должно быть больше нуля."
            return nil
        }
        return amount
    }

}

private func diaryErrorMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case let error as DiaryServiceError:
        return error.errorDescription ?? fallback
    case let error as NutritionCalculatorError:
        return error.errorDescription ?? fallback
    case let error as RecipeCalculatorError:
        return error.errorDescription ?? fallback
    case let error as NutritionError:
        return error.errorDescription ?? fallback
    default:
        diaryErrorLogger.error(
            "unexpected_user_facing_error fallback=\(fallback, privacy: .public) technical_error=\(String(reflecting: error), privacy: .public)",
        )
        return fallback
    }
}

private let diaryErrorLogger = Logger(subsystem: "com.caloriestracker.ios", category: "Diary")
