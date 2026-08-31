import Foundation

struct RecipeIngredientCalculationInput: Hashable, Sendable {
    let draftID: UUID
    let productVersion: ProductVersion
    let amount: Double
    let unitToken: String
}

struct RecipeIngredientCalculation: Hashable, Sendable {
    let draftID: UUID
    let normalizedAmount: Double
    let nutrition: Nutrition
}

struct RecipeCalculation: Hashable, Sendable {
    let totalNutrition: Nutrition
    let ingredientCalculations: [RecipeIngredientCalculation]
}

struct RecipeOutputPreview: Hashable, Sendable {
    let totalNutrition: Nutrition
    let nutritionPer100Grams: Nutrition?
    let nutritionPerServing: Nutrition?
}

enum RecipeCalculatorError: LocalizedError {
    case noIngredients
    case invalidAmount
    case invalidUnit
    case invalidCookedWeight
    case invalidServingsCount
    case unavailableDiaryUnit

    var errorDescription: String? {
        switch self {
        case .noIngredients:
            "Добавьте хотя бы один ингредиент."
        case .invalidAmount:
            "Количество должно быть больше нуля."
        case .invalidUnit:
            "Выберите доступную единицу продукта."
        case .invalidCookedWeight:
            "Готовый вес должен быть больше нуля."
        case .invalidServingsCount:
            "Количество порций должно быть больше нуля."
        case .unavailableDiaryUnit:
            "Выберите доступную единицу рецепта."
        }
    }
}

enum RecipeCalculator {
    static func calculate(
        ingredients: [RecipeIngredientCalculationInput],
    ) throws -> RecipeCalculation {
        var calculations: [RecipeIngredientCalculation] = []
        var total = Nutrition.zero

        for ingredient in ingredients {
            let normalizedAmount = try normalizedAmount(
                amount: ingredient.amount,
                unitToken: ingredient.unitToken,
                version: ingredient.productVersion,
            )
            let nutrition = try NutritionCalculator.calculate(
                nutrition: ingredient.productVersion.nutrition,
                baseAmount: ingredient.productVersion.baseAmount,
                normalizedAmount: normalizedAmount,
            )
            calculations.append(
                RecipeIngredientCalculation(
                    draftID: ingredient.draftID,
                    normalizedAmount: normalizedAmount,
                    nutrition: nutrition,
                ),
            )
            total = try total.adding(nutrition)
        }

        return RecipeCalculation(totalNutrition: total, ingredientCalculations: calculations)
    }

    static func nutritionPer100Grams(for version: RecipeVersion) throws -> Nutrition? {
        try outputPreview(
            totalNutrition: version.totalNutrition,
            cookedWeight: version.cookedWeight,
            servingsCount: nil,
        ).nutritionPer100Grams
    }

    static func nutritionPerServing(for version: RecipeVersion) throws -> Nutrition? {
        try outputPreview(
            totalNutrition: version.totalNutrition,
            cookedWeight: nil,
            servingsCount: version.servingsCount,
        ).nutritionPerServing
    }

    static func outputPreview(
        totalNutrition: Nutrition,
        cookedWeight: Double?,
        servingsCount: Double?,
    ) throws -> RecipeOutputPreview {
        let nutritionPer100Grams: Nutrition?
        if let cookedWeight {
            guard cookedWeight.isFinite, cookedWeight > 0 else {
                throw RecipeCalculatorError.invalidCookedWeight
            }
            nutritionPer100Grams = try totalNutrition.scaled(by: 100 / cookedWeight)
        } else {
            nutritionPer100Grams = nil
        }

        let nutritionPerServing: Nutrition?
        if let servingsCount {
            guard servingsCount.isFinite, servingsCount > 0 else {
                throw RecipeCalculatorError.invalidServingsCount
            }
            nutritionPerServing = try totalNutrition.scaled(by: 1 / servingsCount)
        } else {
            nutritionPerServing = nil
        }

        return RecipeOutputPreview(
            totalNutrition: totalNutrition,
            nutritionPer100Grams: nutritionPer100Grams,
            nutritionPerServing: nutritionPerServing,
        )
    }

    static func diaryNutrition(
        for version: RecipeVersion,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        guard amount.isFinite, amount > 0 else {
            throw RecipeCalculatorError.invalidAmount
        }

        guard let unit = RecipeDiaryUnit(rawValue: unitToken) else {
            throw RecipeCalculatorError.unavailableDiaryUnit
        }

        switch unit {
        case .grams:
            guard let cookedWeight = version.cookedWeight,
                  cookedWeight.isFinite,
                  cookedWeight > 0
            else {
                throw RecipeCalculatorError.unavailableDiaryUnit
            }
            return try version.totalNutrition.scaled(by: amount / cookedWeight)
        case .serving:
            guard let servingsCount = version.servingsCount,
                  servingsCount.isFinite,
                  servingsCount > 0
            else {
                throw RecipeCalculatorError.unavailableDiaryUnit
            }
            return try version.totalNutrition.scaled(by: amount / servingsCount)
        }
    }

    private static func normalizedAmount(
        amount: Double,
        unitToken: String,
        version: ProductVersion,
    ) throws -> Double {
        guard amount.isFinite, amount > 0 else {
            throw RecipeCalculatorError.invalidAmount
        }

        guard unitToken == version.baseUnit.rawValue else {
            throw RecipeCalculatorError.invalidUnit
        }
        return amount
    }
}
