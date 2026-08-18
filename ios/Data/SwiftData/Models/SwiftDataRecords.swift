import Foundation
import SwiftData

@Model
final class ProductRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var barcode: String?
    var currentVersionID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \ProductVersionRecord.product)
    var versions: [ProductVersionRecord] = []

    init(
        id: UUID,
        name: String,
        barcode: String? = nil,
        currentVersionID: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.currentVersionID = currentVersionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class ProductVersionRecord {
    @Attribute(.unique) var id: UUID
    var productID: UUID
    var basedOnVersionID: UUID?
    var versionNumber: Int
    var baseUnitRaw: String
    var baseAmount: Double
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var createdAt: Date

    var product: ProductRecord?

    init(
        id: UUID,
        productID: UUID,
        basedOnVersionID: UUID? = nil,
        versionNumber: Int,
        baseUnitRaw: String,
        baseAmount: Double,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        createdAt: Date,
    ) {
        self.id = id
        self.productID = productID
        self.basedOnVersionID = basedOnVersionID
        self.versionNumber = versionNumber
        self.baseUnitRaw = baseUnitRaw
        self.baseAmount = baseAmount
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.createdAt = createdAt
    }
}

@Model
final class RecipeRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var currentVersionID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \RecipeVersionRecord.recipe)
    var versions: [RecipeVersionRecord] = []

    init(
        id: UUID,
        name: String,
        currentVersionID: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.currentVersionID = currentVersionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class RecipeVersionRecord {
    @Attribute(.unique) var id: UUID
    var recipeID: UUID
    var basedOnVersionID: UUID?
    var versionNumber: Int
    var totalCalories: Double
    var totalProtein: Double
    var totalFat: Double
    var totalCarbs: Double
    var cookedWeight: Double?
    var servingsCount: Double?
    var createdAt: Date

    var recipe: RecipeRecord?

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredientRecord.recipeVersion)
    var ingredients: [RecipeIngredientRecord] = []

    init(
        id: UUID,
        recipeID: UUID,
        basedOnVersionID: UUID? = nil,
        versionNumber: Int,
        totalCalories: Double,
        totalProtein: Double,
        totalFat: Double,
        totalCarbs: Double,
        cookedWeight: Double? = nil,
        servingsCount: Double? = nil,
        createdAt: Date,
    ) {
        self.id = id
        self.recipeID = recipeID
        self.basedOnVersionID = basedOnVersionID
        self.versionNumber = versionNumber
        self.totalCalories = totalCalories
        self.totalProtein = totalProtein
        self.totalFat = totalFat
        self.totalCarbs = totalCarbs
        self.cookedWeight = cookedWeight
        self.servingsCount = servingsCount
        self.createdAt = createdAt
    }
}

@Model
final class RecipeIngredientRecord {
    @Attribute(.unique) var id: UUID
    var recipeVersionID: UUID
    var position: Int
    var productID: UUID
    var productVersionID: UUID
    var amount: Double
    var unitToken: String
    var normalizedAmount: Double

    var recipeVersion: RecipeVersionRecord?

    init(
        id: UUID,
        recipeVersionID: UUID,
        position: Int,
        productID: UUID,
        productVersionID: UUID,
        amount: Double,
        unitToken: String,
        normalizedAmount: Double,
    ) {
        self.id = id
        self.recipeVersionID = recipeVersionID
        self.position = position
        self.productID = productID
        self.productVersionID = productVersionID
        self.amount = amount
        self.unitToken = unitToken
        self.normalizedAmount = normalizedAmount
    }
}

@Model
final class DiaryEntryRecord {
    @Attribute(.unique) var id: UUID
    var dayKey: String
    var mealTypeRaw: String
    var sortOrder: Int
    var sourceTypeRaw: String
    var sourceID: UUID
    var sourceVersionID: UUID
    var sourceName: String
    var amount: Double
    var unitToken: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID,
        dayKey: String,
        mealTypeRaw: String,
        sortOrder: Int,
        sourceTypeRaw: String,
        sourceID: UUID,
        sourceVersionID: UUID,
        sourceName: String,
        amount: Double,
        unitToken: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
    ) {
        self.id = id
        self.dayKey = dayKey
        self.mealTypeRaw = mealTypeRaw
        self.sortOrder = sortOrder
        self.sourceTypeRaw = sourceTypeRaw
        self.sourceID = sourceID
        self.sourceVersionID = sourceVersionID
        self.sourceName = sourceName
        self.amount = amount
        self.unitToken = unitToken
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class WeeklyGoalRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var effectiveFromKey: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DailyMacroGoalRecord.weeklyGoal)
    var dailyGoals: [DailyMacroGoalRecord] = []

    init(id: UUID, effectiveFromKey: String, createdAt: Date) {
        self.id = id
        self.effectiveFromKey = effectiveFromKey
        self.createdAt = createdAt
    }
}

@Model
final class DailyMacroGoalRecord {
    @Attribute(.unique) var id: UUID
    var weeklyGoalID: UUID
    var weekdayRaw: String
    var position: Int
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double

    var weeklyGoal: WeeklyGoalRecord?

    init(
        id: UUID,
        weeklyGoalID: UUID,
        weekdayRaw: String,
        position: Int,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
    ) {
        self.id = id
        self.weeklyGoalID = weeklyGoalID
        self.weekdayRaw = weekdayRaw
        self.position = position
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }
}
