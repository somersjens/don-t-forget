import SwiftData

/// The first production schema. Future model changes must add a new
/// VersionedSchema and a migration stage instead of silently changing V1.
enum AppSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            DayEntry.self,
            TodoItem.self,
            RecurringItem.self,
        ]
    }
}

enum AppSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
