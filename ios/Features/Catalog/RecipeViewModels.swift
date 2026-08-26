import Foundation
import Observation
import OSLog

struct RecipeIngredientEditorItem: Identifiable, Hashable, Sendable {
    let draft: RecipeIngredientDraft
    let productName: String
    let nutrition: Nutrition?

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
    private var usageDefaults: [FoodSourceReference: DiaryUsageDefault] = [:]
    private var selectionDisplays: [UUID: FoodSelectionDisplay] = [:]
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
            refreshSelectionDisplays(for: items)
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

    func selectionDefault(for item: RecipeListItem) -> FoodSelectionAmountDefault? {
        let availableUnits = recipeUnits(for: item.currentVersion)
        guard let fallbackUnit = availableUnits.first else {
            return nil
        }
        let fallback = FoodSelectionAmountDefault(
            amount: FoodAmountDefaults.fallbackAmount(for: fallbackUnit.token),
            unitToken: fallbackUnit.token,
            unitLabel: fallbackUnit.label,
        )
        let source = FoodSourceReference(sourceType: .recipe, sourceID: item.recipe.id)
        guard let usageDefault = usageDefaults[source],
              usageDefault.amount.isFinite,
              usageDefault.amount > 0,
              let recipeUnit = RecipeDiaryUnit(rawValue: usageDefault.unitToken),
              let compatibleUnit = availableUnits.first(where: { $0.token == recipeUnit.rawValue })
        else {
            return fallback
        }

        return FoodSelectionAmountDefault(
            amount: usageDefault.amount,
            unitToken: compatibleUnit.token,
            unitLabel: compatibleUnit.label,
        )
    }

    func selectionDisplay(for item: RecipeListItem) -> FoodSelectionDisplay? {
        guard let defaultValue = selectionDefault(for: item) else {
            return nil
        }

        return selectionDisplays[item.id] ?? FoodSelectionDisplay(
            defaultValue: defaultValue,
            nutrition: nil,
        )
    }

    private func refreshSelectionDisplays(for items: [RecipeListItem]) {
        guard let diaryService else {
            selectionDisplays = [:]
            return
        }

        var displays: [UUID: FoodSelectionDisplay] = [:]
        var calculationErrorMessage: String?

        for item in items {
            guard let defaultValue = selectionDefault(for: item) else {
                continue
            }

            let nutrition: Nutrition?

            do {
                nutrition = try diaryService.preview(
                    calculationSource: .recipe(item.currentVersion),
                    amount: defaultValue.amount,
                    unitToken: defaultValue.unitToken,
                )
            } catch {
                nutrition = nil
                if calculationErrorMessage == nil {
                    calculationErrorMessage = recipeErrorMessage(
                        error,
                        fallback: "Не удалось рассчитать КБЖУ.",
                    )
                }
            }

            displays[item.id] = FoodSelectionDisplay(
                defaultValue: defaultValue,
                nutrition: nutrition,
            )
        }

        selectionDisplays = displays
        if let calculationErrorMessage {
            errorMessage = calculationErrorMessage
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
    private struct OutputValues {
        let cookedWeight: Double?
        let servingsCount: Double?
    }

    private let recipeService: RecipeService
    let recipeID: UUID?

    var name = ""
    var cookedWeightText = ""
    var servingsCountText = ""
    var outputUnit: RecipeDiaryUnit = .grams
    var outputAmountText: String {
        get {
            switch outputUnit {
            case .grams:
                cookedWeightText
            case .serving:
                servingsCountText
            }
        }
        set {
            switch outputUnit {
            case .grams:
                cookedWeightText = newValue
            case .serving:
                servingsCountText = newValue
            }
        }
    }
    private(set) var ingredients: [RecipeIngredientEditorItem] = []
    private(set) var preview: RecipeOutputPreview?
    private(set) var previewErrorMessage: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    private var composition: RecipeCalculation?
    private var compositionErrorMessage: String?
    private var compositionRevision = 0
    private var compositionRequestID = 0
    private var isRefreshingComposition = false
    private var hasLoadedInitialDraft = false
    private var loadedOutputValues: OutputValues?

    init(recipeID: UUID?, recipeService: RecipeService) {
        self.recipeID = recipeID
        self.recipeService = recipeService
    }

    func loadForEditing() async {
        guard let recipeID, !hasLoadedInitialDraft, !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            guard let editorData = try await recipeService.editorData(for: recipeID) else {
                throw RecipeServiceError.recipeNotFound
            }
            compositionRevision &+= 1
            composition = editorData.composition
            compositionErrorMessage = nil
            isRefreshingComposition = false

            let draft = editorData.draft
            name = draft.name
            cookedWeightText = draft.cookedWeight.map { EditableDecimal.string(from: $0) } ?? ""
            servingsCountText = draft.servingsCount.map { EditableDecimal.string(from: $0) } ?? ""
            outputUnit = draft.cookedWeight == nil && draft.servingsCount != nil ? .serving : .grams
            loadedOutputValues = OutputValues(
                cookedWeight: draft.cookedWeight,
                servingsCount: draft.servingsCount,
            )
            let nutritionByDraftID = Dictionary(
                uniqueKeysWithValues: editorData.composition.ingredientCalculations.map { ($0.draftID, $0.nutrition) },
            )
            ingredients = editorData.ingredients.map { item in
                RecipeIngredientEditorItem(
                    draft: RecipeIngredientDraft(
                        id: item.ingredient.id,
                        productID: item.ingredient.productID,
                        productVersionID: item.ingredient.productVersionID,
                        amount: item.ingredient.amount,
                        unitToken: item.ingredient.unitToken,
                    ),
                    productName: item.productName,
                    nutrition: nutritionByDraftID[item.ingredient.id],
                )
            }
            refreshOutputPreview()
            hasLoadedInitialDraft = true
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось загрузить рецепт.")
        }

        isLoading = false
    }

    func addIngredient(_ draft: RecipeIngredientDraft, productName: String) {
        ingredients.append(RecipeIngredientEditorItem(draft: draft, productName: productName, nutrition: nil))
        invalidateComposition()
    }

    func appendIngredient(_ draft: RecipeIngredientDraft, productName: String) async {
        addIngredient(draft, productName: productName)
        await refreshCompositionPreview()
    }

    func quickAddIngredient(
        productID: UUID,
        defaultValue: FoodSelectionAmountDefault,
    ) async throws {
        let source = try await recipeService.ingredientSource(forProductID: productID)
        let draft = try recipeService.makeIngredientDraft(
            source: source,
            amount: defaultValue.amount,
            unitToken: defaultValue.unitToken,
        )
        await appendIngredient(draft, productName: source.productName)
    }

    func quickAddRecipeComposition(
        recipeID: UUID,
        defaultValue: FoodSelectionAmountDefault,
    ) async throws {
        let source = try await recipeService.compositionSource(forRecipeID: recipeID)
        let drafts = try recipeService.makeIngredientDrafts(
            from: source,
            amount: defaultValue.amount,
            unitToken: defaultValue.unitToken,
        )
        try await appendIngredients(drafts)
    }

    @discardableResult
    func addIngredients(_ drafts: [RecipeIngredientDraft]) async -> Bool {
        do {
            try await appendIngredients(drafts)
            return true
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось добавить состав рецепта.")
            return false
        }
    }

    func appendIngredients(_ drafts: [RecipeIngredientDraft]) async throws {
        let sources = try await recipeService.ingredientSources(for: drafts)
        let newItems = zip(drafts, sources).map { draft, source in
            RecipeIngredientEditorItem(draft: draft, productName: source.productName, nutrition: nil)
        }
        ingredients.append(contentsOf: newItems)
        invalidateComposition()
        await refreshCompositionPreview()
    }

    func replaceIngredient(_ draft: RecipeIngredientDraft, productName: String) {
        guard let index = ingredients.firstIndex(where: { $0.draft.id == draft.id }) else {
            return
        }
        ingredients[index] = RecipeIngredientEditorItem(draft: draft, productName: productName, nutrition: nil)
        invalidateComposition()
    }

    func removeIngredients(at offsets: IndexSet) {
        ingredients.remove(atOffsets: offsets)
        invalidateComposition()
    }

    func removeIngredient(id: UUID) {
        ingredients.removeAll { $0.id == id }
        invalidateComposition()
    }

    func draft(for item: RecipeIngredientEditorItem) -> RecipeIngredientDraft {
        item.draft
    }

    func refreshCompositionPreview() async {
        let revision = compositionRevision
        compositionRequestID &+= 1
        let requestID = compositionRequestID
        isRefreshingComposition = true
        let drafts = ingredients.map(\.draft)

        do {
            let calculation = try await recipeService.previewComposition(for: drafts)
            guard compositionRevision == revision, compositionRequestID == requestID else {
                return
            }
            composition = calculation
            compositionErrorMessage = nil
            isRefreshingComposition = false
            refreshOutputPreview()
        } catch {
            guard compositionRevision == revision, compositionRequestID == requestID else {
                return
            }
            composition = nil
            compositionErrorMessage = recipeErrorMessage(error, fallback: "Не удалось рассчитать КБЖУ.")
            isRefreshingComposition = false
            preview = nil
            previewErrorMessage = compositionErrorMessage
        }
    }

    func refreshOutputPreview() {
        do {
            let draft = try makeDraft()
            guard let composition else {
                if let compositionErrorMessage {
                    preview = nil
                    previewErrorMessage = compositionErrorMessage
                } else if !isRefreshingComposition {
                    preview = nil
                    previewErrorMessage = recipeErrorMessage(
                        RecipeServiceError.noIngredients,
                        fallback: "Не удалось рассчитать КБЖУ.",
                    )
                }
                return
            }

            preview = try recipeService.outputPreview(
                totalNutrition: composition.totalNutrition,
                cookedWeight: draft.cookedWeight,
                servingsCount: draft.servingsCount,
            )
            applyIngredientNutrition(from: composition)
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

    private func invalidateComposition() {
        compositionRevision &+= 1
        composition = nil
        compositionErrorMessage = nil
        isRefreshingComposition = false
    }

    private func applyIngredientNutrition(from calculation: RecipeCalculation) {
        let nutritionByDraftID = Dictionary(
            uniqueKeysWithValues: calculation.ingredientCalculations.map { ($0.draftID, $0.nutrition) },
        )
        ingredients = ingredients.map { item in
            RecipeIngredientEditorItem(
                draft: item.draft,
                productName: item.productName,
                nutrition: nutritionByDraftID[item.draft.id],
            )
        }
    }

    private func makeDraft() throws -> RecipeDraft {
        let outputValues: OutputValues
        if let loadedOutputValues, outputInputsMatch(loadedOutputValues) {
            // Preserve unedited stored values rather than round-tripping through
            // the editor's two-decimal display representation.
            outputValues = loadedOutputValues
        } else {
            outputValues = OutputValues(
                cookedWeight: try recipeOptionalNumber(cookedWeightText, field: "Количество"),
                servingsCount: try recipeOptionalNumber(servingsCountText, field: "Количество"),
            )
        }

        return RecipeDraft(
            name: name,
            ingredients: ingredients.map(\.draft),
            cookedWeight: outputValues.cookedWeight,
            servingsCount: outputValues.servingsCount,
        )
    }

    private func outputInputsMatch(_ values: OutputValues) -> Bool {
        cookedWeightText == (values.cookedWeight.map { EditableDecimal.string(from: $0) } ?? "")
            && servingsCountText == (values.servingsCount.map { EditableDecimal.string(from: $0) } ?? "")
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
        selectionDefault: FoodSelectionAmountDefault?,
        recipeService: RecipeService,
    ) {
        self.source = source
        self.replacing = replacing
        self.recipeService = recipeService
        if let selectionDefault,
           selectionDefault.amount.isFinite,
           selectionDefault.amount > 0,
           source.unitOptions.contains(where: { $0.token == selectionDefault.unitToken }) {
            amountText = EditableDecimal.string(from: selectionDefault.amount)
            selectedUnitToken = selectionDefault.unitToken
        } else {
            selectedUnitToken = source.initialUnitToken
            amountText = source.initialAmount.map { EditableDecimal.string(from: $0) }
                ?? EditableDecimal.string(from: FoodAmountDefaults.fallbackAmount(for: selectedUnitToken))
        }
    }

    func refreshPreview() {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = nil
            previewErrorMessage = nil
            return
        }
        guard let amount = EditableDecimal.value(from: trimmed), amount > 0 else {
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
        guard let amount = EditableDecimal.value(from: amountText), amount > 0 else {
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

@MainActor
@Observable
final class RecipeCompositionAmountViewModel {
    private let recipeService: RecipeService
    let source: RecipeCompositionSource

    var amountText = ""
    var selectedUnitToken = ""
    private(set) var preview: Nutrition?
    private(set) var previewErrorMessage: String?
    var errorMessage: String?

    init(
        source: RecipeCompositionSource,
        selectionDefault: FoodSelectionAmountDefault?,
        recipeService: RecipeService,
    ) {
        self.source = source
        self.recipeService = recipeService
        if let selectionDefault,
           selectionDefault.amount.isFinite,
           selectionDefault.amount > 0,
           source.outputUnits.contains(where: { $0.token == selectionDefault.unitToken }) {
            amountText = EditableDecimal.string(from: selectionDefault.amount)
            selectedUnitToken = selectionDefault.unitToken
        } else {
            selectedUnitToken = source.outputUnits.first?.token ?? ""
            amountText = EditableDecimal.string(from: FoodAmountDefaults.fallbackAmount(for: selectedUnitToken))
        }
    }

    func refreshPreview() {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = nil
            previewErrorMessage = nil
            return
        }
        guard let amount = EditableDecimal.value(from: trimmed), amount > 0 else {
            preview = nil
            previewErrorMessage = "Количество должно быть больше нуля."
            return
        }

        do {
            preview = try recipeService.previewComposition(
                source: source,
                amount: amount,
                unitToken: selectedUnitToken,
            )
            previewErrorMessage = nil
        } catch {
            preview = nil
            previewErrorMessage = recipeErrorMessage(error, fallback: "Не удалось рассчитать КБЖУ рецепта.")
        }
    }

    func makeDrafts() -> [RecipeIngredientDraft]? {
        errorMessage = nil
        guard let amount = EditableDecimal.value(from: amountText), amount > 0 else {
            errorMessage = "Количество должно быть больше нуля."
            return nil
        }

        do {
            return try recipeService.makeIngredientDrafts(
                from: source,
                amount: amount,
                unitToken: selectedUnitToken,
            )
        } catch {
            errorMessage = recipeErrorMessage(error, fallback: "Не удалось добавить состав рецепта.")
            return nil
        }
    }
}

private func recipeOptionalNumber(_ text: String, field: String) throws -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    guard let value = EditableDecimal.value(from: trimmed) else {
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
        return error.errorDescription ?? fallback
    case let error as RecipeCalculatorError:
        return error.errorDescription ?? fallback
    case let error as NutritionCalculatorError:
        return error.errorDescription ?? fallback
    case let error as NutritionError:
        return error.errorDescription ?? fallback
    case let error as RecipeEditorError:
        return error.errorDescription ?? fallback
    default:
        recipeErrorLogger.error(
            "unexpected_user_facing_error fallback=\(fallback, privacy: .public) technical_error=\(String(reflecting: error), privacy: .public)",
        )
        return fallback
    }
}

private let recipeErrorLogger = Logger(subsystem: "com.caloriestracker.ios", category: "Recipe")
