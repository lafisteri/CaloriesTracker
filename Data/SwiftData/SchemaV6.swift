import Foundation
import SwiftData

enum CaloriesTrackerSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
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
            WeeklyGoalRecord.self,
            DailyMacroGoalRecord.self,
            SyncOutboxRecord.self,
            SyncRemoteStateRecord.self,
            SyncPullStateRecord.self,
            SyncBootstrapStateRecord.self,
        ]
    }
}
