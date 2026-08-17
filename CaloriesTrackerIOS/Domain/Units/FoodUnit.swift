import Foundation

enum FoodUnit: String, CaseIterable, Codable, Sendable {
    case g
    case ml
    case piece
    case serving

    init(_ baseUnit: ProductBaseUnit) {
        switch baseUnit {
        case .g: self = .g
        case .ml: self = .ml
        case .piece: self = .piece
        case .serving: self = .serving
        }
    }
}
