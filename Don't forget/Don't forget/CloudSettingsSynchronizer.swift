import Foundation

/// Mirrors portable preferences to the user's private iCloud key-value store.
///
/// Values are synchronized independently. This prevents an unrelated local
/// preference change from writing an old copy of every other preference back
/// to iCloud. If iOS and macOS edit the same setting almost simultaneously,
/// the iOS edit wins; outside that short conflict window the newest edit wins.
@MainActor
final class CloudSettingsSynchronizer {
    static let shared = CloudSettingsSynchronizer()

    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let localStore = UserDefaults.standard
    private var observerTokens: [NSObjectProtocol] = []
    private var hasStarted = false
    private var localSnapshot: [String: NSObject] = [:]
    private var uploadTask: Task<Void, Never>?

    private static let metadataPrefix = "settings.syncMetadata.v2."
    private static let conflictWindow: TimeInterval = 10

    private let syncedKeys = [
        SettingsKeys.weekStart,
        SettingsKeys.weekdayLabelLength,
        SettingsKeys.weekNumberRule,
        SettingsKeys.dateFormat,
        SettingsKeys.language,
        SettingsKeys.defaultColorCombinationEnabled,
        SettingsKeys.recurringBirthdayColor,
        SettingsKeys.recurringGeneralColor,
        SettingsKeys.recurringPersonalColor,
        SettingsKeys.recurringCategories,
        SettingsKeys.recurringShowNextDate,
        SettingsKeys.recurringCompactRows,
        SettingsKeys.recurringCompactCategoryIDs,
        SettingsKeys.recurringSoonestFirst,
        SettingsKeys.recurringShowHolidays,
        SettingsKeys.recurringHolidayCountry,
        SettingsKeys.recurringOnlyLocalHolidays,
        SettingsKeys.recurringBirthdayCategoryDeleted,
        SettingsKeys.recurringHorizon,
        SettingsKeys.todoGroups,
        SettingsKeys.historyShowsDeletedItems,
        SettingsKeys.historyRetention,
        SettingsKeys.actionButtonContent,
        SettingsKeys.actionButtonDatePrefix,
        SettingsKeys.actionButtonItemCount,
        SettingsKeys.lockScreenWordTruncation,
        SettingsKeys.homeWidgetContent,
        SettingsKeys.homeWidgetCalendarRange,
        SettingsKeys.homeWidgetDatePrefix,
        SettingsKeys.homeWidgetTextFlow,
        SettingsKeys.homeWidgetShowsTitle,
        SettingsKeys.homeWidgetBackground,
        SettingsKeys.homeWidgetShowsOtherWhenEmpty,
        SettingsKeys.homeWidgetTodoCategoryID,
        SettingsKeys.actionButtonDefaultDestination,
        SettingsKeys.actionButtonTaskCategoryID,
        SettingsKeys.actionButtonStartsVoiceRecording,
        SettingsKeys.actionButtonLaunchMode,
    ]

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        localSnapshot = snapshotLocalValues()

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloudStore,
                queue: .main
            ) { notification in
                let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                Task { @MainActor in
                    CloudSettingsSynchronizer.shared.applyCloudValues(changedKeys: changedKeys)
                }
            }
        )

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: localStore,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CloudSettingsSynchronizer.shared.scheduleLocalUpload()
                }
            }
        )

        cloudStore.synchronize()
        mergeInitialValues()
    }

    func stop() {
        guard hasStarted else { return }
        uploadTask?.cancel()
        uploadTask = nil
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
        hasStarted = false
    }

    /// Removes preferences mirrored through iCloud so a full app reset cannot
    /// immediately restore the previous settings.
    func removeSyncedSettings() {
        stop()
        for key in syncedKeys {
            cloudStore.removeObject(forKey: key)
            cloudStore.removeObject(forKey: metadataKey(for: key))
            localStore.removeObject(forKey: key)
            localStore.removeObject(forKey: metadataKey(for: key))
        }
        cloudStore.synchronize()
    }

    /// Existing cloud values win only during the legacy/first-install merge.
    /// Once metadata exists, normal conflict resolution is used.
    private func mergeInitialValues() {
        for key in syncedKeys {
            if let cloudValue = cloudStore.object(forKey: key) as? NSObject {
                let cloudMetadata = metadata(in: cloudStore, for: key)
                let localMetadata = metadata(in: localStore, for: key)
                if cloudMetadata == nil || shouldAccept(cloudMetadata, over: localMetadata) {
                    setLocal(cloudValue, metadata: cloudMetadata, for: key)
                }
            } else if let localValue = localStore.object(forKey: key) as? NSObject {
                upload(localValue, for: key, metadata: newMetadata())
            }
        }
        localSnapshot = snapshotLocalValues()
        cloudStore.synchronize()
    }

    private func applyCloudValues(changedKeys: [String]?) {
        let keys: [String]
        if let changedKeys {
            let changed = Set(changedKeys)
            keys = syncedKeys.filter {
                changed.contains($0) || changed.contains(metadataKey(for: $0))
            }
        } else {
            keys = syncedKeys
        }

        for key in keys {
            guard let cloudValue = cloudStore.object(forKey: key) as? NSObject else { continue }
            let cloudMetadata = metadata(in: cloudStore, for: key)
            let localMetadata = metadata(in: localStore, for: key)
            guard cloudMetadata == nil || shouldAccept(cloudMetadata, over: localMetadata) else { continue }
            setLocal(cloudValue, metadata: cloudMetadata, for: key)
        }
        localSnapshot = snapshotLocalValues()
    }

    /// UserDefaults notifications do not identify their changed key. Comparing
    /// with a snapshot lets us upload only the portable settings that changed.
    private func scheduleLocalUpload() {
        uploadTask?.cancel()
        uploadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, hasStarted else { return }
            uploadChangedLocalValues()
        }
    }

    private func uploadChangedLocalValues() {
        let current = snapshotLocalValues()
        for key in syncedKeys where !Self.valuesEqual(current[key], localSnapshot[key]) {
            guard let value = current[key] else { continue }
            upload(value, for: key, metadata: newMetadata())
        }
        localSnapshot = current
        cloudStore.synchronize()
    }

    private func upload(_ value: NSObject, for key: String, metadata: SyncMetadata) {
        localStore.set(metadata.dictionary, forKey: metadataKey(for: key))
        cloudStore.set(value, forKey: key)
        cloudStore.set(metadata.dictionary, forKey: metadataKey(for: key))
    }

    private func setLocal(_ value: NSObject, metadata: SyncMetadata?, for key: String) {
        localStore.set(value, forKey: key)
        if let metadata {
            localStore.set(metadata.dictionary, forKey: metadataKey(for: key))
        }
    }

    private func snapshotLocalValues() -> [String: NSObject] {
        Dictionary(uniqueKeysWithValues: syncedKeys.compactMap { key in
            (localStore.object(forKey: key) as? NSObject).map { (key, $0) }
        })
    }

    private func metadataKey(for key: String) -> String {
        Self.metadataPrefix + key
    }

    private func metadata(in store: UserDefaults, for key: String) -> SyncMetadata? {
        SyncMetadata(dictionary: store.dictionary(forKey: metadataKey(for: key)))
    }

    private func metadata(in store: NSUbiquitousKeyValueStore, for key: String) -> SyncMetadata? {
        SyncMetadata(dictionary: store.dictionary(forKey: metadataKey(for: key)))
    }

    private func newMetadata() -> SyncMetadata {
        SyncMetadata(modifiedAt: Date().timeIntervalSince1970, platform: Self.platform)
    }

    private func shouldAccept(_ incoming: SyncMetadata?, over local: SyncMetadata?) -> Bool {
        guard let incoming else { return true }
        guard let local else { return true }
        let distance = abs(incoming.modifiedAt - local.modifiedAt)
        if distance <= Self.conflictWindow, incoming.platform != local.platform {
            return incoming.platform == .iOS
        }
        return incoming.modifiedAt > local.modifiedAt
    }

    private static func valuesEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.isEqual(rhs)
        default: false
        }
    }

    private static var platform: SyncPlatform {
#if os(macOS)
        .macOS
#else
        .iOS
#endif
    }
}

private enum SyncPlatform: String {
    case iOS
    case macOS
}

private struct SyncMetadata: Equatable {
    let modifiedAt: TimeInterval
    let platform: SyncPlatform

    init(modifiedAt: TimeInterval, platform: SyncPlatform) {
        self.modifiedAt = modifiedAt
        self.platform = platform
    }

    init?(dictionary: [String: Any]?) {
        guard
            let dictionary,
            let modifiedAt = dictionary["modifiedAt"] as? NSNumber,
            let platformValue = dictionary["platform"] as? String,
            let platform = SyncPlatform(rawValue: platformValue)
        else { return nil }
        self.modifiedAt = modifiedAt.doubleValue
        self.platform = platform
    }

    var dictionary: [String: Any] {
        ["modifiedAt": modifiedAt, "platform": platform.rawValue]
    }
}
