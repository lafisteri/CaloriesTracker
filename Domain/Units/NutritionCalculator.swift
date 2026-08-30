import Foundation

enum NutritionCalculatorError: Error, LocalizedError {
    case invalidBaseAmount
    case invalidNormalizedAmount

    var errorDescription: String? {
        switch self {
        case .invalidBaseAmount:
            "Базовое количество должно быть положительным конечным числом."
        case .invalidNormalizedAmount:
            "Количество должно быть конечным неотрицательным числом."
        }
    }
}

enum NutritionCalculator {
    static func calculate(
        nutrition: Nutrition,
        baseAmount: Double,
        normalizedAmount: Double,
    ) throws -> Nutrition {
        guard baseAmount.isFinite, baseAmount > 0 else {
            throw NutritionCalculatorError.invalidBaseAmount
        }

        guard normalizedAmount.isFinite, normalizedAmount >= 0 else {
            throw NutritionCalculatorError.invalidNormalizedAmount
        }

        return try nutrition.scaled(by: normalizedAmount / baseAmount)
    }
}
