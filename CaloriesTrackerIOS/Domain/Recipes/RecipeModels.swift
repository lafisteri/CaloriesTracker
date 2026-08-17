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

/// Editable input. IDs are transient and are replaced by immutable child IDs when a RecipeVersion is saved.
struct RecipeIngredientDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    let productID: UUID
    let productVersionID: UUID
    let amount: Double
    let unitToken: String
}

struct RecipeDraft: Hashable, Sendable {
    let name: String
    let ingredients: [RecipeIngredientDraft]
    let cookedWeight: Double?
    let servingsCount: Double?
}

enum RecipeDiaryUnit: String, CaseIterable, Hashable, Codable, Sendable {
    case grams = "g"
    case serving = "piece"

    /// Accepts the short-lived Phase 4 tokens so an already saved local entry
    /// remains editable after the canonical token format is restored.
    static func resolve(_ token: String) -> Self? {
        switch token {
        case grams.rawValue, "recipe:g":
            .grams
        case serving.rawValue, "recipe:serving":
            .serving
        default:
            nil
        }
    }
}
