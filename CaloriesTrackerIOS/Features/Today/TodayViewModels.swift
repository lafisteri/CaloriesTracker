import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private let diaryService: DiaryService

    private(set) var selectedDay: LocalDay
    private(set) var day: DiaryDayReadModel?
    private(set) var isLoading = false
    var errorMessage: String?

    init(diaryService: DiaryService, selectedDay: LocalDay = .current()) {
        self.diaryService = diaryService
        self.selectedDay = selectedDay
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            day = try await diaryService.day(for: selectedDay)
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось загрузить дневник.")
        }

        isLoading = false
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

    func move(entryID: UUID, to meal: MealType) async {
        errorMessage = nil

        do {
            try await diaryService.move(
                MoveDiaryEntryCommand(entryID: entryID, targetMeal: meal, targetIndex: Int.max),
            )
            await load()
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось переместить запись.")
        }
    }
}

@MainActor
@Observable
final class FoodSelectionViewModel {
    private let productService: ProductService

    private(set) var products: [ProductListItem] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(productService: ProductService) {
        self.productService = productService
    }

    func load(matching query: String) async {
        isLoading = true
        errorMessage = nil

        do {
            products = try await productService.products(matching: query)
        } catch {
            errorMessage = "Не удалось загрузить продукты."
        }

        isLoading = false
    }
}

enum DiaryAmountEditorMode: Hashable, Sendable {
    case create(context: DiaryContext, source: FoodSourceReference)
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

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            switch mode {
            case let .create(_, sourceReference):
                source = try await diaryService.amountSource(for: sourceReference)
            case let .edit(entryID):
                source = try await diaryService.amountSource(forEntryID: entryID)
            }

            guard let source else {
                return
            }
            amountText = source.initialAmount.map(numericString) ?? ""
            selectedUnitToken = source.initialUnitToken
            refreshPreview()
        } catch {
            errorMessage = diaryErrorMessage(error, fallback: "Не удалось загрузить источник.")
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
        guard let amount = numericValue(from: trimmedAmount), amount > 0 else {
            preview = nil
            previewErrorMessage = "Количество должно быть больше нуля."
            return
        }

        do {
            preview = try diaryService.preview(
                version: source.version,
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
        errorMessage = nil

        guard let amount = parsedPositiveAmount() else {
            return false
        }

        isSaving = true
        do {
            switch mode {
            case let .create(context, source):
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
        guard let amount = numericValue(from: trimmedAmount), amount > 0 else {
            errorMessage = "Количество должно быть больше нуля."
            return nil
        }
        return amount
    }

    private func numericValue(from text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func numericString(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 3)))
    }
}

private func diaryErrorMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case let error as DiaryServiceError:
        error.errorDescription ?? fallback
    case let error as UnitConverterError:
        error.errorDescription ?? fallback
    case let error as NutritionCalculatorError:
        error.errorDescription ?? fallback
    case let error as RecordMappingError:
        error.errorDescription ?? fallback
    default:
        fallback
    }
}
