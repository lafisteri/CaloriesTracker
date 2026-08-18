import Foundation

struct Nutrition: Hashable, Codable, Sendable {
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double

    static let zero = Nutrition(calories: 0, protein: 0, fat: 0, carbs: 0)

    func scaled(by factor: Double) -> Nutrition {
        Nutrition(
            calories: calories * factor,
            protein: protein * factor,
            fat: fat * factor,
            carbs: carbs * factor,
        )
    }

    func adding(_ other: Nutrition) -> Nutrition {
        Nutrition(
            calories: calories + other.calories,
            protein: protein + other.protein,
            fat: fat + other.fat,
            carbs: carbs + other.carbs,
        )
    }
}
