import Foundation

struct Recipe: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let currentVersionID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

/// Immutable composition and calculated totals for one logical recipe version.
struct RecipeVersion: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let recipeID: UUID
    let basedOnVersionID: UUID?
    let versionNumber: Int
    let totalNutrition: Nutrition
    let cookedWeight: Double?
    let servingsCount: Double?
    let ingredients: [RecipeIngredient]
    let createdAt: Date
}

/// An immutable recipe-version child that pins one exact ProductVersion.
struct RecipeIngredient: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let recipeVersionID: UUID
    let position: Int
    let productID: UUID
    let productVersionID: UUID
    let amount: Double
    let unitToken: String
    let normalizedAmount: Double
}
