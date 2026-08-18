import Foundation
import Observation

struct RecipeIngredientEditorItem: Identifiable, Hashable, Sendable {
    let draft: RecipeIngredientDraft
    let productName: String

    var id: UUID {
        draft.id
    }
}

@MainActor
@Observable
final class RecipeListViewModel {
    private let recipeService: RecipeService
    private let diaryService: DiaryService?
    private var currentQuery = ""

    private(set) var recipes: [RecipeListItem] = []
    private(set) var isLoading = false
    private(set) var quickAddingRecipeID: UUID?
    private var usageDefaults: [FoodSourceReference: DiaryUsageDefault] = [:]
    var errorMessage: String?

    init(recipeService: RecipeService, diaryService: DiaryService? = nil) {
        self.recipeService = recipeService
        self.diaryService = diaryService
    }

    func load(matching query: String) async {
        currentQuery = query
        isLoading = true
        errorMessage = nil

        do {
            let items = try await recipeService.recipes(matching: query)
            recipes = items
            if let diaryService {
                usageDefaults = try await diaryService.latestUsageDefaults(
                    for: items.map { item in
                        FoodSourceReference(sourceType: .recipe, sourceID: item.recipe.id)
                    },
                )
            } else {
                usageDefaults = [:]
            }
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось загрузить рецепты.")
        }

        isLoading = false
    }

    func softDelete(recipeID: UUID) async {
        errorMessage = nil

        do {
            try await recipeService.softDelete(recipeID: recipeID)
            await load(matching: currentQuery)
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось удалить рецепт.")
        }
    }

    func selectionDefault(for item: RecipeListItem) -> DiarySelectionAmountDefault? {
        let availableUnits = recipeUnits(for: item.currentVersion)
        guard let fallbackUnit = availableUnits.first else {
            return nil
        }
        let fallback = DiarySelectionAmountDefault(
            amount: 100,
            unitToken: fallbackUnit.token,
            unitLabel: fallbackUnit.label,
        )
        let source = FoodSourceReference(sourceType: .recipe, sourceID: item.recipe.id)
        guard let usageDefault = usageDefaults[source],
              usageDefault.amount.isFinite,
              usageDefault.amount > 0,
              let recipeUnit = RecipeDiaryUnit.resolve(usageDefault.unitToken),
              let compatibleUnit = availableUnits.first(where: { $0.token == recipeUnit.rawValue })
        else {
            return fallback
        }

        return DiarySelectionAmountDefault(
            amount: usageDefault.amount,
            unitToken: compatibleUnit.token,
            unitLabel: compatibleUnit.label,
        )
    }

    func quickAdd(
        recipeID: UUID,
        context: DiaryContext,
        defaultValue: DiarySelectionAmountDefault,
    ) async -> Bool {
        guard let diaryService else {
            return false
        }

        quickAddingRecipeID = recipeID
        errorMessage = nil
        defer { quickAddingRecipeID = nil }

        do {
            try await diaryService.quickAdd(
                context: context,
                source: FoodSourceReference(sourceType: .recipe, sourceID: recipeID),
                preferredAmount: defaultValue.amount,
                preferredUnitToken: defaultValue.unitToken,
            )
            return true
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось добавить рецепт.")
            return false
        }
    }

    private func recipeUnits(for version: RecipeVersion) -> [(token: String, label: String)] {
        var units: [(token: String, label: String)] = []
        if version.cookedWeight != nil {
            units.append((RecipeDiaryUnit.grams.rawValue, "г"))
        }
        if version.servingsCount != nil {
            units.append((RecipeDiaryUnit.serving.rawValue, "порция"))
        }
        return units
    }
}

@MainActor
@Observable
final class RecipeDetailViewModel {
    private let recipeService: RecipeService
    private let recipeID: UUID

    private(set) var details: RecipeDetails?
    private(set) var isLoading = false
    private(set) var isUpdatingIngredients = false
    var errorMessage: String?

    init(recipeID: UUID, recipeService: RecipeService) {
        self.recipeID = recipeID
        self.recipeService = recipeService
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            details = try await recipeService.details(id: recipeID)
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось загрузить рецепт.")
        }

        isLoading = false
    }

    @discardableResult
    func softDelete() async -> Bool {
        errorMessage = nil

        do {
            try await recipeService.softDelete(recipeID: recipeID)
            return true
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось удалить рецепт.")
            return false
        }
    }

    func updateIngredients() async {
        isUpdatingIngredients = true
        errorMessage = nil

        do {
            try await recipeService.updateOutdatedIngredients(recipeID: recipeID)
            await load()
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось обновить ингредиенты.")
        }

        isUpdatingIngredients = false
    }
}

@MainActor
@Observable
final class RecipeEditorViewModel {
    private let recipeService: RecipeService
    let recipeID: UUID?

    var name = ""
    var cookedWeightText = ""
    var servingsCountText = ""
    private(set) var ingredients: [RecipeIngredientEditorItem] = []
    private(set) var preview: Nutrition?
    private(set) var previewErrorMessage: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    init(recipeID: UUID?, recipeService: RecipeService) {
        self.recipeID = recipeID
        self.recipeService = recipeService
    }

    func loadForEditing() async {
        guard let recipeID else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            guard let draft = try await recipeService.draft(for: recipeID) else {
                throw RecipeServiceError.recipeNotFound
            }
            name = draft.name
            cookedWeightText = draft.cookedWeight.map(recipeNumericString) ?? ""
            servingsCountText = draft.servingsCount.map(recipeNumericString) ?? ""
            try await setIngredients(from: draft.ingredients)
            await refreshPreview()
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось загрузить рецепт.")
        }

        isLoading = false
    }

    func addIngredient(_ draft: RecipeIngredientDraft, productName: String) {
        ingredients.append(RecipeIngredientEditorItem(draft: draft, productName: productName))
    }

    func replaceIngredient(_ draft: RecipeIngredientDraft, productName: String) {
        guard let index = ingredients.firstIndex(where: { $0.draft.id == draft.id }) else {
            return
        }
        ingredients[index] = RecipeIngredientEditorItem(draft: draft, productName: productName)
    }

    func removeIngredients(at offsets: IndexSet) {
        ingredients.remove(atOffsets: offsets)
    }

    func draft(for item: RecipeIngredientEditorItem) -> RecipeIngredientDraft {
        item.draft
    }

    func refreshPreview() async {
        do {
            preview = try await recipeService.preview(makeDraft()).totalNutrition
            previewErrorMessage = nil
        } catch {
            preview = nil
            previewErrorMessage = recipeErrorMessage(error, fallback: "Не удалось рассчитать КБЖУ.")
        }
    }

    @discardableResult
    func save() async -> Bool {
        errorMessage = nil

        do {
            let draft = try makeDraft()
            isSaving = true
            if let recipeID {
                try await recipeService.update(recipeID: recipeID, draft: draft)
            } else {
                try await recipeService.create(draft: draft)
            }
            isSaving = false
            return true
        } catch {
            isSaving = false
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось сохранить рецепт.")
            return false
        }
    }

    private func setIngredients(from drafts: [RecipeIngredientDraft]) async throws {
        var loaded: [RecipeIngredientEditorItem] = []
        for draft in drafts {
            let source = try await recipeService.ingredientSource(for: draft)
            loaded.append(RecipeIngredientEditorItem(draft: draft, productName: source.productName))
        }
        ingredients = loaded
    }

    private func makeDraft() throws -> RecipeDraft {
        RecipeDraft(
            name: name,
            ingredients: ingredients.map(\.draft),
            cookedWeight: try recipeOptionalNumber(cookedWeightText, field: "Готовый вес"),
            servingsCount: try recipeOptionalNumber(servingsCountText, field: "Количество порций"),
        )
    }
}

@MainActor
@Observable
final class RecipeVersionHistoryViewModel {
    private let recipeService: RecipeService
    private let recipeID: UUID

    private(set) var versions: [RecipeVersion] = []
    private(set) var currentVersionID: UUID?
    private(set) var isLoading = false
    var errorMessage: String?

    init(recipeID: UUID, recipeService: RecipeService) {
        self.recipeID = recipeID
        self.recipeService = recipeService
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let details = try await recipeService.details(id: recipeID) else {
                throw RecipeServiceError.recipeNotFound
            }
            currentVersionID = details.recipe.currentVersionID
            versions = try await recipeService.versions(for: recipeID)
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось загрузить версии рецепта.")
        }

        isLoading = false
    }
}

@MainActor
@Observable
final class RecipeIngredientSelectionViewModel {
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

@MainActor
@Observable
final class RecipeIngredientAmountViewModel {
    private let recipeService: RecipeService
    let source: RecipeIngredientSource
    let replacing: RecipeIngredientDraft?

    var amountText = ""
    var selectedUnitToken = ""
    private(set) var preview: Nutrition?
    private(set) var previewErrorMessage: String?
    var errorMessage: String?

    init(
        source: RecipeIngredientSource,
        replacing: RecipeIngredientDraft?,
        recipeService: RecipeService,
    ) {
        self.source = source
        self.replacing = replacing
        self.recipeService = recipeService
        amountText = source.initialAmount.map(recipeNumericString) ?? ""
        selectedUnitToken = source.initialUnitToken
    }

    func refreshPreview() {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = nil
            previewErrorMessage = nil
            return
        }
        guard let amount = recipeNumericValue(trimmed), amount > 0 else {
            preview = nil
            previewErrorMessage = "Количество должно быть больше нуля."
            return
        }

        do {
            preview = try recipeService.previewIngredient(
                source: source,
                amount: amount,
                unitToken: selectedUnitToken,
            )
            previewErrorMessage = nil
        } catch {
            preview = nil
            previewErrorMessage = recipeErrorMessage(error, fallback: "Не удалось рассчитать КБЖУ.")
        }
    }

    func makeDraft() -> RecipeIngredientDraft? {
        errorMessage = nil
        guard let amount = recipeNumericValue(amountText), amount > 0 else {
            errorMessage = "Количество должно быть больше нуля."
            return nil
        }

        do {
            return try recipeService.makeIngredientDraft(
                source: source,
                amount: amount,
                unitToken: selectedUnitToken,
                replacing: replacing,
            )
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось добавить ингредиент.")
            return nil
        }
    }
}

func recipeNumericString(_ value: Double) -> String {
    String(value)
}

func recipeNumericValue(_ text: String) -> Double? {
    let normalized = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
    return Double(normalized)?.isFinite == true ? Double(normalized) : nil
}

private func recipeOptionalNumber(_ text: String, field: String) throws -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    guard let value = recipeNumericValue(trimmed) else {
        throw RecipeEditorError.invalidNumber(field: field)
    }
    return value
}

private enum RecipeEditorError: LocalizedError {
    case invalidNumber(field: String)

    var errorDescription: String? {
        switch self {
        case let .invalidNumber(field):
            "Введите корректное значение для поля «\(field)»."
        }
    }
}

func recipeErrorMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case let error as RecipeServiceError:
        error.errorDescription ?? fallback
    case let error as RecipeCalculatorError:
        error.errorDescription ?? fallback
    case let error as UnitConverterError:
        error.errorDescription ?? fallback
    case let error as NutritionCalculatorError:
        error.errorDescription ?? fallback
    case let error as RecipeEditorError:
        error.errorDescription ?? fallback
    case let error as RecordMappingError:
        error.errorDescription ?? fallback
    default:
        fallback
    }
}
