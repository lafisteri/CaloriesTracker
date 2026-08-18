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
        guard !ingredients.isEmpty else {
            throw RecipeCalculatorError.noIngredients
        }

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
            total = total.adding(nutrition)
        }

        return RecipeCalculation(totalNutrition: total, ingredientCalculations: calculations)
    }

    static func nutritionPer100Grams(for version: RecipeVersion) throws -> Nutrition? {
        guard let cookedWeight = version.cookedWeight else {
            return nil
        }
        guard cookedWeight.isFinite, cookedWeight > 0 else {
            throw RecipeCalculatorError.invalidCookedWeight
        }
        return version.totalNutrition.scaled(by: 100 / cookedWeight)
    }

    static func nutritionPerServing(for version: RecipeVersion) throws -> Nutrition? {
        guard let servingsCount = version.servingsCount else {
            return nil
        }
        guard servingsCount.isFinite, servingsCount > 0 else {
            throw RecipeCalculatorError.invalidServingsCount
        }
        return version.totalNutrition.scaled(by: 1 / servingsCount)
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
            return version.totalNutrition.scaled(by: amount / cookedWeight)
        case .serving:
            guard let servingsCount = version.servingsCount,
                  servingsCount.isFinite,
                  servingsCount > 0
            else {
                throw RecipeCalculatorError.unavailableDiaryUnit
            }
            return version.totalNutrition.scaled(by: amount / servingsCount)
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
