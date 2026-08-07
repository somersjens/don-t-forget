import Foundation
import SwiftData

@MainActor
enum AppResetService {
    static func reset(modelContext: ModelContext) throws {
        let defaults = UserDefaults.standard
        let preservedLanguage = defaults.object(forKey: SettingsKeys.language)

        let entries = try modelContext.fetch(FetchDescriptor<DayEntry>())
        let todos = try modelContext.fetch(FetchDescriptor<TodoItem>())
        let recurringItems = try modelContext.fetch(FetchDescriptor<RecurringItem>())

        try AppBackupService.createAutomaticSnapshot(
            from: modelContext,
            reason: "before-full-reset"
        )

        // Calendar is outside the app's own storage. Clean up linked events
        // when possible, but never let a revoked permission block the reset.
        try? CalendarSyncService.removeSyncedEvents(for: entries)

        for entry in entries {
            modelContext.delete(entry)
        }
        for todo in todos {
            modelContext.delete(todo)
        }
        for recurringItem in recurringItems {
            modelContext.delete(recurringItem)
        }
        try modelContext.save()

#if !os(macOS)
        CalendarWidgetSnapshotPublisher.clear()
#endif
        EndOfDayReminderService.cancelPendingReminders()
        CloudSettingsSynchronizer.shared.removeSyncedSettings()

        clearDefaultsPreservingLanguage(
            defaults: defaults,
            domainName: Bundle.main.bundleIdentifier,
            preservedLanguage: preservedLanguage
        )

        // Explicitly notify the root view to return to onboarding. On a fresh
        // install iCloud settings sync is active by default, so restore that
        // behavior after clearing its old values.
        defaults.set(false, forKey: SettingsKeys.hasCompletedWelcome)
        CloudSettingsSynchronizer.shared.start()
    }

    static func clearDefaultsPreservingLanguage(
        defaults: UserDefaults,
        domainName: String?,
        preservedLanguage: Any?
    ) {
        if let domainName {
            defaults.removePersistentDomain(forName: domainName)
        } else {
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
        }

        if let preservedLanguage {
            defaults.set(preservedLanguage, forKey: SettingsKeys.language)
        }
    }
}
