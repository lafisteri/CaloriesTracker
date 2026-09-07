import Foundation
import SwiftData

enum CaloriesTrackerSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            ProductRecord.self,
            ProductVersionRecord.self,
            RecipeRecord.self,
            RecipeVersionRecord.self,
            RecipeIngredientRecord.self,
            DiaryEntryRecord.self,
            MealConfigurationRecord.self,
            ChartSettingsRecord.self,
            WeeklyGoalRecord.self,
            DailyMacroGoalRecord.self,
            SyncOutboxRecord.self,
            SyncRemoteStateRecord.self,
            SyncPullStateRecord.self,
            SyncBootstrapStateRecord.self,
        ]
    }
}
