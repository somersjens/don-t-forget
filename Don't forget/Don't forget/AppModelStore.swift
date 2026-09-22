import Foundation
import SwiftData

/// The single persistent store used by iPhone, iPad and Mac.
///
/// Keeping the same schema, bundle family and CloudKit container on every
/// platform is what makes changes appear on all of a user's devices.
@MainActor
enum AppModelStore {
    static let iCloudContainerIdentifier = "iCloud.Hakketjak.Don-t-forget"
    static let appGroupIdentifier = "group.Hakketjak.Don-t-forget"

    static var isICloudSyncEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKeys.iCloudSyncEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: SettingsKeys.iCloudSyncEnabled)
    }

    private static var cachedContainer: ModelContainer?
    private static var cachedError: Error?

    static func load() -> Result<ModelContainer, Error> {
        if let cachedContainer { return .success(cachedContainer) }
        if let cachedError { return .failure(cachedError) }

        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            // Do not let `.automatic` silently fall back to a different local
            // store when an entitlement is missing from a development build.
            // iPhone, iPad and Mac must all attach CloudKit to this exact store.
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: isICloudSyncEnabled
                ? .private(iCloudContainerIdentifier)
                : .none
        )

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppSchemaMigrationPlan.self,
                configurations: configuration
            )
            cachedContainer = container
            // Settle the zone before the first read, then keep watching while
            // CloudKit delivers calendar rows later in the launch.
            DayTimeZonePin.start(in: container)
            return .success(container)
        } catch {
            cachedError = error
            return .failure(error)
        }
    }

    static func requireContainer() throws -> ModelContainer {
        try load().get()
    }

    static func retryAfterFailure() -> Result<ModelContainer, Error> {
        cachedError = nil
        return load()
    }
}
