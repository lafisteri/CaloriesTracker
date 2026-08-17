import Foundation

struct Product: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let barcode: String?
    let currentVersionID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

/// Immutable nutrition and unit data for one logical product version.
struct ProductVersion: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let productID: UUID
    let basedOnVersionID: UUID?
    let versionNumber: Int
    let baseUnit: ProductBaseUnit
    let baseAmount: Double
    let nutrition: Nutrition
    let servingUnits: [ServingUnit]
    let createdAt: Date
}

/// Immutable child data belonging to one ProductVersion.
struct ServingUnit: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let productVersionID: UUID
    let position: Int
    let name: String
    let conversionAmount: Double
    let conversionUnit: ServingConversionUnit
}

/// Editable values used to create a product or append a new immutable version.
struct ProductDraft: Hashable, Sendable {
    let name: String
    let barcode: String?
    let baseUnit: ProductBaseUnit
    let baseAmount: Double
    let nutrition: Nutrition
}
