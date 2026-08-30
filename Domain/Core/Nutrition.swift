import Foundation

enum NutritionError: Error, LocalizedError {
    case nonFiniteResult

    var errorDescription: String? {
        switch self {
        case .nonFiniteResult:
            "Результат расчёта КБЖУ должен быть конечным числом."
        }
    }
}

struct Nutrition: Hashable, Codable, Sendable {
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double

    static let zero = Nutrition(calories: 0, protein: 0, fat: 0, carbs: 0)

    var isFinite: Bool {
        [calories, protein, fat, carbs].allSatisfy(\.isFinite)
    }

    func scaled(by factor: Double) throws -> Nutrition {
        guard factor.isFinite, isFinite else {
            throw NutritionError.nonFiniteResult
        }

        let result = Nutrition(
            calories: calories * factor,
            protein: protein * factor,
            fat: fat * factor,
            carbs: carbs * factor,
        )
        guard result.isFinite else {
            throw NutritionError.nonFiniteResult
        }
        return result
    }

    func adding(_ other: Nutrition) throws -> Nutrition {
        guard isFinite, other.isFinite else {
            throw NutritionError.nonFiniteResult
        }

        let result = Nutrition(
            calories: calories + other.calories,
            protein: protein + other.protein,
            fat: fat + other.fat,
            carbs: carbs + other.carbs,
        )
        guard result.isFinite else {
            throw NutritionError.nonFiniteResult
        }
        return result
    }
}
