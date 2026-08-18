import SwiftData

enum CaloriesTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CaloriesTrackerSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
