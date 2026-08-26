import SwiftData

enum CaloriesTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CaloriesTrackerSchemaV1.self, CaloriesTrackerSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: CaloriesTrackerSchemaV1.self,
                toVersion: CaloriesTrackerSchemaV2.self,
            ),
        ]
    }
}
