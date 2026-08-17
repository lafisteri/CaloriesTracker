import Foundation

enum MealType: String, CaseIterable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var russianLabel: String {
        switch self {
        case .breakfast: "Завтрак"
        case .lunch: "Обед"
        case .dinner: "Ужин"
        case .snack: "Перекусы"
        }
    }
}

enum SourceType: String, Codable, Sendable {
    case product
    case recipe
}

enum ProductBaseUnit: String, CaseIterable, Codable, Sendable {
    case g
    case ml
    case piece
    case serving
}

enum ServingConversionUnit: String, CaseIterable, Codable, Sendable {
    case g
    case ml
    case piece
}
