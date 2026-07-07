import Foundation

/// Mirrors portable preferences to the user's private iCloud key-value store.
/// Device-specific state (Calendar permission, transient requests and sync
/// timestamps) deliberately remains local.
@MainActor
final class CloudSettingsSynchronizer {
    static let shared = CloudSettingsSynchronizer()

    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let localStore = UserDefaults.standard
    private var observerTokens: [NSObjectProtocol] = []
    private var hasStarted = false
    private var isApplyingCloudValues = false

    private let syncedKeys = [
        SettingsKeys.weekStart,
        SettingsKeys.weekNumberRule,
        SettingsKeys.dateFormat,
        SettingsKeys.language,
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

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloudStore,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CloudSettingsSynchronizer.shared.applyCloudValues()
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
                    CloudSettingsSynchronizer.shared.uploadLocalValues()
                }
            }
        )

        cloudStore.synchronize()
        mergeInitialValues()
    }

    func stop() {
        guard hasStarted else { return }

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
            localStore.removeObject(forKey: key)
        }

        cloudStore.synchronize()
    }

    /// Cloud wins when both sides contain a value. This makes a reinstall
    /// restore existing preferences instead of replacing them with defaults.
    private func mergeInitialValues() {
        isApplyingCloudValues = true

        for key in syncedKeys {
            if let cloudValue = cloudStore.object(forKey: key) {
                localStore.set(cloudValue, forKey: key)
            } else if let localValue = localStore.object(forKey: key) {
                cloudStore.set(localValue, forKey: key)
            }
        }

        isApplyingCloudValues = false
        cloudStore.synchronize()
    }

    private func applyCloudValues() {
        isApplyingCloudValues = true

        for key in syncedKeys {
            guard let cloudValue = cloudStore.object(forKey: key) else { continue }
            localStore.set(cloudValue, forKey: key)
        }

        isApplyingCloudValues = false
    }

    private func uploadLocalValues() {
        guard !isApplyingCloudValues else { return }

        for key in syncedKeys {
            guard let localValue = localStore.object(forKey: key) else { continue }
            cloudStore.set(localValue, forKey: key)
        }

        cloudStore.synchronize()
    }
}
