import SwiftData

enum CaloriesTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            CaloriesTrackerSchemaV1.self,
            CaloriesTrackerSchemaV2.self,
            CaloriesTrackerSchemaV3.self,
            CaloriesTrackerSchemaV4.self,
            CaloriesTrackerSchemaV5.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: CaloriesTrackerSchemaV1.self,
                toVersion: CaloriesTrackerSchemaV2.self,
            ),
            .lightweight(
                fromVersion: CaloriesTrackerSchemaV2.self,
                toVersion: CaloriesTrackerSchemaV3.self,
            ),
            .lightweight(
                fromVersion: CaloriesTrackerSchemaV3.self,
                toVersion: CaloriesTrackerSchemaV4.self,
            ),
            .lightweight(
                fromVersion: CaloriesTrackerSchemaV4.self,
                toVersion: CaloriesTrackerSchemaV5.self,
            ),
        ]
    }
}
