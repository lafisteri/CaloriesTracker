import Foundation
import SwiftData

enum CaloriesTrackerSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
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
        ]
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
}
