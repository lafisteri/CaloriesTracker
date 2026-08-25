import Foundation

struct RecipeListItem: Identifiable, Hashable, Sendable {
    let recipe: Recipe
    let currentVersion: RecipeVersion

    var id: UUID {
        recipe.id
    }
}

struct RecipeIngredientUnitOption: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case base(ProductBaseUnit)
    }

    let token: String
    let kind: Kind

    var id: String {
        token
    }
}

struct RecipeIngredientSource: Identifiable, Hashable, Sendable {
    let productID: UUID
    let productName: String
    let version: ProductVersion
    let unitOptions: [RecipeIngredientUnitOption]
    let initialAmount: Double?
    let initialUnitToken: String

    var id: UUID {
        productID
    }
}

/// A saved recipe selected for composition. It is flattened into its pinned
/// product ingredients rather than being stored as a nested recipe reference.
struct RecipeCompositionSource: Identifiable, Hashable, Sendable {
    let recipeID: UUID
    let recipeName: String
    let version: RecipeVersion
    let outputUnits: [RecipeCompositionOutputUnit]

    var id: UUID {
        recipeID
    }
}

struct RecipeCompositionOutputUnit: Identifiable, Hashable, Sendable {
    let token: String
    let label: String

    var id: String {
        token
    }
}

struct RecipeIngredientReadModel: Identifiable, Hashable, Sendable {
    let ingredient: RecipeIngredient
    let productName: String
    let productVersion: ProductVersion

    var id: UUID {
        ingredient.id
    }
}

struct RecipeDetails: Hashable, Sendable {
    let recipe: Recipe
    let currentVersion: RecipeVersion
    let ingredients: [RecipeIngredientReadModel]
    let nutritionPer100Grams: Nutrition?
    let nutritionPerServing: Nutrition?
    let outdatedIngredientCount: Int
}

@MainActor
final class RecipeService {
    private let recipeRepository: any RecipeRepository
    private let productRepository: any ProductRepository

    init(
        recipeRepository: any RecipeRepository,
        productRepository: any ProductRepository,
    ) {
        self.recipeRepository = recipeRepository
        self.productRepository = productRepository
    }

    func recipes(matching query: String) async throws -> [RecipeListItem] {
        let recipes = try await recipeRepository.activeRecipes(matching: query)
        guard !recipes.isEmpty else {
            return []
        }
        let versionIDs = Set(recipes.map(\.currentVersionID))
        let versions = try await recipeRepository.versions(ids: versionIDs)
        let versionsByID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })

        return try recipes.map { recipe in
            guard let version = versionsByID[recipe.currentVersionID],
                  version.recipeID == recipe.id
            else {
                throw RecipeServiceError.currentRecipeVersionNotFound
            }
            return RecipeListItem(recipe: recipe, currentVersion: version)
        }
    }

    func details(id: UUID) async throws -> RecipeDetails? {
        guard let recipe = try await recipeRepository.recipe(id: id, includingDeleted: false) else {
            return nil
        }
        let version = try await currentVersion(for: recipe)
        let ingredients = try await ingredientReadModels(for: version)
        let outdatedIngredientCount = try await outdatedIngredientCount(for: version)
        let nutritionPer100Grams = try RecipeCalculator.nutritionPer100Grams(for: version)
        let nutritionPerServing = try RecipeCalculator.nutritionPerServing(for: version)

        return RecipeDetails(
            recipe: recipe,
            currentVersion: version,
            ingredients: ingredients,
            nutritionPer100Grams: nutritionPer100Grams,
            nutritionPerServing: nutritionPerServing,
            outdatedIngredientCount: outdatedIngredientCount,
        )
    }

    func draft(for recipeID: UUID) async throws -> RecipeDraft? {
        guard let details = try await details(id: recipeID) else {
            return nil
        }

        return RecipeDraft(
            name: details.recipe.name,
            ingredients: details.currentVersion.ingredients.map { ingredient in
                RecipeIngredientDraft(
                    id: ingredient.id,
                    productID: ingredient.productID,
                    productVersionID: ingredient.productVersionID,
                    amount: ingredient.amount,
                    unitToken: ingredient.unitToken,
                )
            },
            cookedWeight: details.currentVersion.cookedWeight,
            servingsCount: details.currentVersion.servingsCount,
        )
    }

    func versions(for recipeID: UUID) async throws -> [RecipeVersion] {
        let versions = try await recipeRepository.versions(for: recipeID)
        return versions.sorted {
            if $0.versionNumber == $1.versionNumber {
                return $0.createdAt > $1.createdAt
            }
            return $0.versionNumber > $1.versionNumber
        }
    }

    func ingredientSource(forProductID productID: UUID) async throws -> RecipeIngredientSource {
        guard let product = try await productRepository.product(id: productID, includingDeleted: false) else {
            throw RecipeServiceError.productNotFound
        }
        guard let version = try await productRepository.version(id: product.currentVersionID),
              version.productID == product.id
        else {
            throw RecipeServiceError.currentProductVersionNotFound
        }

        return RecipeIngredientSource(
            productID: product.id,
            productName: product.name,
            version: version,
            unitOptions: unitOptions(for: version),
            initialAmount: nil,
            initialUnitToken: version.baseUnit.rawValue,
        )
    }

    func compositionSource(forRecipeID recipeID: UUID) async throws -> RecipeCompositionSource {
        guard let recipe = try await recipeRepository.recipe(id: recipeID, includingDeleted: false) else {
            throw RecipeServiceError.recipeNotFound
        }
        let version = try await currentVersion(for: recipe)
        let outputUnits = compositionOutputUnits(for: version)
        guard !outputUnits.isEmpty else {
            throw RecipeServiceError.outputRequired
        }

        return RecipeCompositionSource(
            recipeID: recipe.id,
            recipeName: recipe.name,
            version: version,
            outputUnits: outputUnits,
        )
    }

    func previewComposition(
        source: RecipeCompositionSource,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        source.version.totalNutrition.scaled(by: try compositionFactor(for: source, amount: amount, unitToken: unitToken))
    }

    func makeIngredientDrafts(
        from source: RecipeCompositionSource,
        amount: Double,
        unitToken: String,
    ) throws -> [RecipeIngredientDraft] {
        let factor = try compositionFactor(for: source, amount: amount, unitToken: unitToken)

        return try source.version.ingredients.map { ingredient in
            let scaledAmount = ingredient.amount * factor
            guard scaledAmount.isFinite, scaledAmount > 0 else {
                throw RecipeServiceError.invalidCompositionAmount
            }
            return RecipeIngredientDraft(
                id: UUID(),
                productID: ingredient.productID,
                productVersionID: ingredient.productVersionID,
                amount: scaledAmount,
                unitToken: ingredient.unitToken,
            )
        }
    }

    func ingredientSource(for draft: RecipeIngredientDraft) async throws -> RecipeIngredientSource {
        guard let version = try await productRepository.version(id: draft.productVersionID),
              version.productID == draft.productID
        else {
            throw RecipeServiceError.pinnedProductVersionNotFound
        }
        let productName = try await productRepository.product(id: draft.productID, includingDeleted: true)?.name
            ?? "Удалённый продукт"

        return RecipeIngredientSource(
            productID: draft.productID,
            productName: productName,
            version: version,
            unitOptions: unitOptions(for: version),
            initialAmount: draft.amount,
            initialUnitToken: draft.unitToken,
        )
    }

    func makeIngredientDraft(
        source: RecipeIngredientSource,
        amount: Double,
        unitToken: String,
        replacing existing: RecipeIngredientDraft? = nil,
    ) throws -> RecipeIngredientDraft {
        let draftID = existing?.id ?? UUID()
        _ = try RecipeCalculator.calculate(
            ingredients: [
                RecipeIngredientCalculationInput(
                    draftID: draftID,
                    productVersion: source.version,
                    amount: amount,
                    unitToken: unitToken,
                ),
            ],
        )

        return RecipeIngredientDraft(
            id: draftID,
            productID: source.productID,
            productVersionID: source.version.id,
            amount: amount,
            unitToken: unitToken,
        )
    }

    func previewIngredient(
        source: RecipeIngredientSource,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        try RecipeCalculator.calculate(
            ingredients: [
                RecipeIngredientCalculationInput(
                    draftID: UUID(),
                    productVersion: source.version,
                    amount: amount,
                    unitToken: unitToken,
                ),
            ],
        ).totalNutrition
    }

    func preview(_ draft: RecipeDraft) async throws -> RecipeCalculation {
        try validate(draft)
        return try await calculation(for: draft.ingredients)
    }

    @discardableResult
    func create(draft: RecipeDraft) async throws -> UUID {
        let name = try validatedName(draft.name)
        try validate(draft)
        let calculation = try await calculation(for: draft.ingredients)
        let now = Date()
        let recipeID = UUID()
        let versionID = UUID()
        let version = try makeVersion(
            id: versionID,
            recipeID: recipeID,
            basedOnVersionID: nil,
            versionNumber: 1,
            draft: draft,
            calculation: calculation,
            createdAt: now,
        )
        let recipe = Recipe(
            id: recipeID,
            name: name,
            currentVersionID: versionID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
        )

        try await recipeRepository.create(recipe, initialVersion: version)
        return recipeID
    }

    func update(recipeID: UUID, draft: RecipeDraft) async throws {
        guard let recipe = try await recipeRepository.recipe(id: recipeID, includingDeleted: false) else {
            throw RecipeServiceError.recipeNotFound
        }
        let currentVersion = try await currentVersion(for: recipe)
        let name = try validatedName(draft.name)
        try validate(draft)
        let calculation = try await calculation(for: draft.ingredients)
        let versionedChange = versionedContentChanged(
            currentVersion: currentVersion,
            draft: draft,
            calculation: calculation,
        )
        let metadataChanged = recipe.name != name

        guard versionedChange || metadataChanged else {
            return
        }

        let now = Date()
        if versionedChange {
            let nextVersionID = UUID()
            let nextVersion = try makeVersion(
                id: nextVersionID,
                recipeID: recipe.id,
                basedOnVersionID: currentVersion.id,
                versionNumber: currentVersion.versionNumber + 1,
                draft: draft,
                calculation: calculation,
                createdAt: now,
            )
            let updatedRecipe = Recipe(
                id: recipe.id,
                name: name,
                currentVersionID: nextVersionID,
                createdAt: recipe.createdAt,
                updatedAt: now,
                deletedAt: recipe.deletedAt,
            )
            try await recipeRepository.append(nextVersion, settingCurrentVersionOf: updatedRecipe)
        } else {
            let updatedRecipe = Recipe(
                id: recipe.id,
                name: name,
                currentVersionID: recipe.currentVersionID,
                createdAt: recipe.createdAt,
                updatedAt: now,
                deletedAt: recipe.deletedAt,
            )
            try await recipeRepository.saveLogicalMetadata(updatedRecipe)
        }
    }

    func updateOutdatedIngredients(recipeID: UUID) async throws {
        guard let recipe = try await recipeRepository.recipe(id: recipeID, includingDeleted: false) else {
            throw RecipeServiceError.recipeNotFound
        }
        let currentVersion = try await currentVersion(for: recipe)
        var ingredients = currentVersion.ingredients.map {
                RecipeIngredientDraft(
                    id: $0.id,
                    productID: $0.productID,
                    productVersionID: $0.productVersionID,
                    amount: $0.amount,
                    unitToken: $0.unitToken,
                )
            }
        var changed = false

        for index in ingredients.indices {
            let ingredient = ingredients[index]
            guard let product = try await productRepository.product(id: ingredient.productID, includingDeleted: false),
                  product.currentVersionID != ingredient.productVersionID,
                  let nextVersion = try await productRepository.version(id: product.currentVersionID),
                  nextVersion.productID == product.id,
                  unitToken(ingredient.unitToken, isCompatibleWith: nextVersion)
            else {
                continue
            }

            ingredients[index] = RecipeIngredientDraft(
                id: ingredient.id,
                productID: ingredient.productID,
                productVersionID: nextVersion.id,
                amount: ingredient.amount,
                unitToken: ingredient.unitToken,
            )
            changed = true
        }

        guard changed else {
            throw RecipeServiceError.noCompatibleIngredientUpdates
        }
        try await update(
            recipeID: recipeID,
            draft: RecipeDraft(
                name: recipe.name,
                ingredients: ingredients,
                cookedWeight: currentVersion.cookedWeight,
                servingsCount: currentVersion.servingsCount,
            ),
        )
    }

    func softDelete(recipeID: UUID) async throws {
        guard try await recipeRepository.recipe(id: recipeID, includingDeleted: false) != nil else {
            throw RecipeServiceError.recipeNotFound
        }
        try await recipeRepository.softDeleteRecipe(id: recipeID, at: Date())
    }

    private func currentVersion(for recipe: Recipe) async throws -> RecipeVersion {
        guard let version = try await recipeRepository.version(id: recipe.currentVersionID),
              version.recipeID == recipe.id
        else {
            throw RecipeServiceError.currentRecipeVersionNotFound
        }
        return version
    }

    private func compositionOutputUnits(for version: RecipeVersion) -> [RecipeCompositionOutputUnit] {
        var units: [RecipeCompositionOutputUnit] = []
        if version.cookedWeight != nil {
            units.append(RecipeCompositionOutputUnit(token: RecipeDiaryUnit.grams.rawValue, label: "г"))
        }
        if version.servingsCount != nil {
            units.append(RecipeCompositionOutputUnit(token: RecipeDiaryUnit.serving.rawValue, label: "порция"))
        }
        return units
    }

    private func compositionFactor(
        for source: RecipeCompositionSource,
        amount: Double,
        unitToken: String,
    ) throws -> Double {
        guard amount.isFinite, amount > 0 else {
            throw RecipeServiceError.invalidCompositionAmount
        }

        let outputAmount: Double
        switch RecipeDiaryUnit(rawValue: unitToken) {
        case .grams:
            guard let cookedWeight = source.version.cookedWeight, cookedWeight.isFinite, cookedWeight > 0 else {
                throw RecipeServiceError.unavailableCompositionUnit
            }
            outputAmount = cookedWeight
        case .serving:
            guard let servingsCount = source.version.servingsCount, servingsCount.isFinite, servingsCount > 0 else {
                throw RecipeServiceError.unavailableCompositionUnit
            }
            outputAmount = servingsCount
        case nil:
            throw RecipeServiceError.unavailableCompositionUnit
        }

        let factor = amount / outputAmount
        guard factor.isFinite, factor > 0 else {
            throw RecipeServiceError.invalidCompositionAmount
        }
        return factor
    }

    private func ingredientReadModels(for version: RecipeVersion) async throws -> [RecipeIngredientReadModel] {
        var result: [RecipeIngredientReadModel] = []
        for ingredient in version.ingredients.sorted(by: { $0.position < $1.position }) {
            guard let productVersion = try await productRepository.version(id: ingredient.productVersionID),
                  productVersion.productID == ingredient.productID
            else {
                throw RecipeServiceError.pinnedProductVersionNotFound
            }
            let productName = try await productRepository.product(id: ingredient.productID, includingDeleted: true)?.name
                ?? "Удалённый продукт"
            result.append(
                RecipeIngredientReadModel(
                    ingredient: ingredient,
                    productName: productName,
                    productVersion: productVersion,
                ),
            )
        }
        return result
    }

    private func outdatedIngredientCount(for version: RecipeVersion) async throws -> Int {
        var count = 0
        for ingredient in version.ingredients {
            guard let product = try await productRepository.product(id: ingredient.productID, includingDeleted: false) else {
                continue
            }
            if product.currentVersionID != ingredient.productVersionID {
                count += 1
            }
        }
        return count
    }

    private func calculation(for drafts: [RecipeIngredientDraft]) async throws -> RecipeCalculation {
        guard Set(drafts.map(\.id)).count == drafts.count else {
            throw RecipeServiceError.duplicateIngredient
        }

        var inputs: [RecipeIngredientCalculationInput] = []
        for draft in drafts {
            guard let version = try await productRepository.version(id: draft.productVersionID),
                  version.productID == draft.productID
            else {
                throw RecipeServiceError.pinnedProductVersionNotFound
            }
            inputs.append(
                RecipeIngredientCalculationInput(
                    draftID: draft.id,
                    productVersion: version,
                    amount: draft.amount,
                    unitToken: draft.unitToken,
                ),
            )
        }
        return try RecipeCalculator.calculate(ingredients: inputs)
    }

    private func makeVersion(
        id: UUID,
        recipeID: UUID,
        basedOnVersionID: UUID?,
        versionNumber: Int,
        draft: RecipeDraft,
        calculation: RecipeCalculation,
        createdAt: Date,
    ) throws -> RecipeVersion {
        let calculationsByDraftID = Dictionary(
            uniqueKeysWithValues: calculation.ingredientCalculations.map { ($0.draftID, $0) },
        )
        guard calculationsByDraftID.count == draft.ingredients.count else {
            throw RecipeServiceError.calculationMismatch
        }
        let ingredients = try draft.ingredients.enumerated().map { position, draftIngredient -> RecipeIngredient in
            guard let ingredientCalculation = calculationsByDraftID[draftIngredient.id] else {
                throw RecipeServiceError.calculationMismatch
            }
            return RecipeIngredient(
                id: UUID(),
                recipeVersionID: id,
                position: position,
                productID: draftIngredient.productID,
                productVersionID: draftIngredient.productVersionID,
                amount: draftIngredient.amount,
                unitToken: draftIngredient.unitToken,
                normalizedAmount: ingredientCalculation.normalizedAmount,
            )
        }

        return RecipeVersion(
            id: id,
            recipeID: recipeID,
            basedOnVersionID: basedOnVersionID,
            versionNumber: versionNumber,
            totalNutrition: calculation.totalNutrition,
            cookedWeight: draft.cookedWeight,
            servingsCount: draft.servingsCount,
            ingredients: ingredients,
            createdAt: createdAt,
        )
    }

    private func versionedContentChanged(
        currentVersion: RecipeVersion,
        draft: RecipeDraft,
        calculation: RecipeCalculation,
    ) -> Bool {
        guard currentVersion.cookedWeight == draft.cookedWeight,
              currentVersion.servingsCount == draft.servingsCount,
              currentVersion.ingredients.count == draft.ingredients.count
        else {
            return true
        }

        for (ingredient, draftIngredient) in zip(currentVersion.ingredients.sorted(by: { $0.position < $1.position }), draft.ingredients) {
            guard ingredient.productID == draftIngredient.productID,
                  ingredient.productVersionID == draftIngredient.productVersionID,
                  ingredient.amount == draftIngredient.amount,
                  ingredient.unitToken == draftIngredient.unitToken
            else {
                return true
            }
        }

        return currentVersion.totalNutrition != calculation.totalNutrition
    }

    private func validate(_ draft: RecipeDraft) throws {
        guard !draft.ingredients.isEmpty else {
            throw RecipeServiceError.noIngredients
        }
        if let cookedWeight = draft.cookedWeight {
            guard cookedWeight.isFinite, cookedWeight > 0 else {
                throw RecipeServiceError.invalidCookedWeight
            }
        }
        if let servingsCount = draft.servingsCount {
            guard servingsCount.isFinite, servingsCount > 0 else {
                throw RecipeServiceError.invalidServingsCount
            }
        }
        guard draft.cookedWeight != nil || draft.servingsCount != nil else {
            throw RecipeServiceError.outputRequired
        }
    }

    private func validatedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw RecipeServiceError.nameRequired
        }
        return name
    }

    private func unitOptions(for version: ProductVersion) -> [RecipeIngredientUnitOption] {
        [RecipeIngredientUnitOption(token: version.baseUnit.rawValue, kind: .base(version.baseUnit))]
    }

    private func unitToken(_ token: String, isCompatibleWith version: ProductVersion) -> Bool {
        token == version.baseUnit.rawValue
    }
}

enum RecipeServiceError: LocalizedError {
    case recipeNotFound
    case productNotFound
    case currentProductVersionNotFound
    case currentRecipeVersionNotFound
    case pinnedProductVersionNotFound
    case nameRequired
    case noIngredients
    case outputRequired
    case invalidCookedWeight
    case invalidServingsCount
    case duplicateIngredient
    case calculationMismatch
    case noCompatibleIngredientUpdates
    case unavailableCompositionUnit
    case invalidCompositionAmount

    var errorDescription: String? {
        switch self {
        case .recipeNotFound:
            "Рецепт не найден."
        case .productNotFound:
            "Продукт не найден или удалён."
        case .currentProductVersionNotFound:
            "Не удалось найти текущую версию продукта."
        case .currentRecipeVersionNotFound:
            "Не удалось найти текущую версию рецепта."
        case .pinnedProductVersionNotFound:
            "Не удалось найти закреплённую версию продукта."
        case .nameRequired:
            "Введите название рецепта."
        case .noIngredients:
            "Добавьте хотя бы один ингредиент."
        case .outputRequired:
            "Укажите готовый вес или количество порций."
        case .invalidCookedWeight:
            "Готовый вес должен быть больше нуля."
        case .invalidServingsCount:
            "Количество порций должно быть больше нуля."
        case .duplicateIngredient:
            "Ингредиенты рецепта повторяются некорректно."
        case .calculationMismatch:
            "Не удалось рассчитать ингредиенты рецепта."
        case .noCompatibleIngredientUpdates:
            "Нет совместимых обновлений ингредиентов."
        case .unavailableCompositionUnit:
            "Для этого рецепта недоступна выбранная единица выхода."
        case .invalidCompositionAmount:
            "Количество рецепта должно быть больше нуля."
        }
    }
}
