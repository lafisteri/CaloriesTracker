import Foundation
import SwiftData

enum CaloriesTrackerSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            ProductRecord.self,
            ProductVersionRecord.self,
            RecipeRecord.self,
            RecipeVersionRecord.self,
            RecipeIngredientRecord.self,
            DiaryEntryRecord.self,
            WeeklyGoalRecord.self,
            DailyMacroGoalRecord.self,
            SyncOutboxRecord.self,
            SyncRemoteStateRecord.self,
            SyncPullStateRecord.self,
            SyncBootstrapStateRecord.self,
        ]
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

}
