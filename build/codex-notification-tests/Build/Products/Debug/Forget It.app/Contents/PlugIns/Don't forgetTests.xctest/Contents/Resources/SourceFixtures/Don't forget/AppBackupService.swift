import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct AppBackupArchive: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let createdAt: Date
    let appVersion: String
    let entries: [DayEntryBackup]
    let todos: [TodoItemBackup]
    let recurringItems: [RecurringItemBackup]
    let settingsPropertyList: Data

    var itemCount: Int {
        entries.count + todos.count + recurringItems.count
    }
}

nonisolated struct DayEntryBackup: Codable {
    let id: UUID
    let date: Date
    let rawText: String
    let startMinutes: Int?
    let endMinutes: Int?
    let isUncertain: Bool
    let isDone: Bool
    let isRemoved: Bool
    let showOnWidget: Bool
    let sourceRawValue: String
    let manualOrder: Double
    let createdAt: Date
    let completedAt: Date?
    let calendarEventIdentifier: String?
    let recurringItemIdentifier: UUID?
    let recurringOccurrenceKey: String?
    let recurringDateOverride: Date?
    let accentRawValue: String

    @MainActor init(_ entry: DayEntry) {
        id = entry.id
        date = entry.date
        rawText = entry.rawText
        startMinutes = entry.startMinutes
        endMinutes = entry.endMinutes
        isUncertain = entry.isUncertain
        isDone = entry.isDone
        isRemoved = entry.isRemoved
        showOnWidget = entry.showOnWidget
        sourceRawValue = entry.sourceRawValue
        manualOrder = entry.manualOrder
        createdAt = entry.createdAt
        completedAt = entry.completedAt
        calendarEventIdentifier = entry.calendarEventIdentifier
        recurringItemIdentifier = entry.recurringItemIdentifier
        recurringOccurrenceKey = entry.recurringOccurrenceKey
        recurringDateOverride = entry.recurringDateOverride
        accentRawValue = entry.accentRawValue
    }

    @MainActor func makeModel() -> DayEntry {
        let model = DayEntry(date: date, rawText: rawText)
        model.id = id
        model.startMinutes = startMinutes
        model.endMinutes = endMinutes
        model.isUncertain = isUncertain
        model.isDone = isDone
        model.isRemoved = isRemoved
        model.showOnWidget = showOnWidget
        model.sourceRawValue = sourceRawValue
        model.manualOrder = manualOrder
        model.createdAt = createdAt
        model.completedAt = completedAt
        // Calendar identifiers are device-local. A restore must not mutate an
        // unrelated calendar event that happens to reuse an old identifier.
        model.calendarEventIdentifier = nil
        model.recurringItemIdentifier = recurringItemIdentifier
        model.recurringOccurrenceKey = recurringOccurrenceKey
        model.recurringDateOverride = recurringDateOverride
        model.accentRawValue = accentRawValue
        return model
    }
}

nonisolated struct TodoItemBackup: Codable {
    let id: UUID
    let text: String
    let bucketRawValue: String
    let isDone: Bool
    let isRemoved: Bool
    let showOnWidget: Bool
    let createdAt: Date
    let completedAt: Date?

    @MainActor init(_ todo: TodoItem) {
        id = todo.id
        text = todo.text
        bucketRawValue = todo.bucketRawValue
        isDone = todo.isDone
        isRemoved = todo.isRemoved
        showOnWidget = todo.showOnWidget
        createdAt = todo.createdAt
        completedAt = todo.completedAt
    }

    @MainActor func makeModel() -> TodoItem {
        let model = TodoItem(text: text, showOnWidget: showOnWidget)
        model.id = id
        model.bucketRawValue = bucketRawValue
        model.isDone = isDone
        model.isRemoved = isRemoved
        model.createdAt = createdAt
        model.completedAt = completedAt
        return model
    }
}

nonisolated struct RecurringItemBackup: Codable {
    let id: UUID
    let title: String
    let frequencyText: String
    let nextDate: Date
    let reminderMinutesBefore: Int?
    let showOnWidget: Bool
    let themeRawValue: String
    let recurrenceKindRawValue: String
    let intervalValue: Int
    let intervalUnitRawValue: String
    let monthlyDay: Int
    let monthlyOrdinal: Int
    let monthlyWeekday: Int
    let annualMonth: Int
    let reminderDaysBefore: Int?
    let birthDate: Date?
    let birthdayYearUncertain: Bool
    let notes: String
    let linksData: String
    let scheduleShiftsData: String
    let recurrenceConfigurationVersion: Int
    let createdAt: Date
    let isRemoved: Bool
    let completedAt: Date?

    @MainActor init(_ item: RecurringItem) {
        id = item.id
        title = item.title
        frequencyText = item.frequencyText
        nextDate = item.nextDate
        reminderMinutesBefore = item.reminderMinutesBefore
        showOnWidget = item.showOnWidget
        themeRawValue = item.themeRawValue
        recurrenceKindRawValue = item.recurrenceKindRawValue
        intervalValue = item.intervalValue
        intervalUnitRawValue = item.intervalUnitRawValue
        monthlyDay = item.monthlyDay
        monthlyOrdinal = item.monthlyOrdinal
        monthlyWeekday = item.monthlyWeekday
        annualMonth = item.annualMonth
        reminderDaysBefore = item.reminderDaysBefore
        birthDate = item.birthDate
        birthdayYearUncertain = item.birthdayYearUncertain
        notes = item.notes
        linksData = item.linksData
        scheduleShiftsData = item.scheduleShiftsData
        recurrenceConfigurationVersion = item.recurrenceConfigurationVersion
        createdAt = item.createdAt
        isRemoved = item.isRemoved
        completedAt = item.completedAt
    }

    @MainActor func makeModel() -> RecurringItem {
        let model = RecurringItem(title: title, frequencyText: frequencyText, nextDate: nextDate)
        model.id = id
        model.reminderMinutesBefore = reminderMinutesBefore
        model.showOnWidget = showOnWidget
        model.themeRawValue = themeRawValue
        model.recurrenceKindRawValue = recurrenceKindRawValue
        model.intervalValue = intervalValue
        model.intervalUnitRawValue = intervalUnitRawValue
        model.monthlyDay = monthlyDay
        model.monthlyOrdinal = monthlyOrdinal
        model.monthlyWeekday = monthlyWeekday
        model.annualMonth = annualMonth
        model.reminderDaysBefore = reminderDaysBefore
        model.birthDate = birthDate
        model.birthdayYearUncertain = birthdayYearUncertain
        model.notes = notes
        model.linksData = linksData
        model.scheduleShiftsData = scheduleShiftsData
        model.recurrenceConfigurationVersion = recurrenceConfigurationVersion
        model.createdAt = createdAt
        model.isRemoved = isRemoved
        model.completedAt = completedAt
        return model
    }
}

struct AppBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let archive: AppBackupArchive

    init(archive: AppBackupArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw AppBackupError.emptyFile
        }
        archive = try AppBackupService.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try AppBackupService.encode(archive))
    }
}

enum AppBackupError: LocalizedError {
    case emptyFile
    case unsupportedVersion(Int)
    case invalidSettings

    var errorDescription: String? {
        switch self {
        case .emptyFile: "Het backupbestand is leeg."
        case .unsupportedVersion(let version): "Backupversie \(version) wordt niet ondersteund."
        case .invalidSettings: "De instellingen in de backup zijn beschadigd."
        }
    }
}

@MainActor
enum AppBackupService {
    static func makeArchive(
        from modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> AppBackupArchive {
        let entries = try modelContext.fetch(FetchDescriptor<DayEntry>())
        let todos = try modelContext.fetch(FetchDescriptor<TodoItem>())
        let recurringItems = try modelContext.fetch(FetchDescriptor<RecurringItem>())
        let domain = defaults.dictionaryRepresentation().filter { key, _ in
            key.hasPrefix("settings.")
                || key.hasPrefix("onboarding.")
                || key.hasPrefix("quickTodo.")
        }
        let settingsData = try PropertyListSerialization.data(
            fromPropertyList: domain,
            format: .binary,
            options: 0
        )

        return AppBackupArchive(
            formatVersion: AppBackupArchive.currentFormatVersion,
            createdAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            entries: entries.map(DayEntryBackup.init),
            todos: todos.map(TodoItemBackup.init),
            recurringItems: recurringItems.map(RecurringItemBackup.init),
            settingsPropertyList: settingsData
        )
    }

    static func restore(
        _ archive: AppBackupArchive,
        into modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) throws {
        try validate(archive)
        try createAutomaticSnapshot(
            from: modelContext,
            reason: "before-restore",
            defaults: defaults
        )

        let currentICloudSetting = defaults.object(forKey: SettingsKeys.iCloudSyncEnabled)
        let currentLanguage = defaults.object(forKey: SettingsKeys.language)

        for entry in try modelContext.fetch(FetchDescriptor<DayEntry>()) { modelContext.delete(entry) }
        for todo in try modelContext.fetch(FetchDescriptor<TodoItem>()) { modelContext.delete(todo) }
        for item in try modelContext.fetch(FetchDescriptor<RecurringItem>()) { modelContext.delete(item) }
        archive.entries.map { $0.makeModel() }.forEach(modelContext.insert)
        archive.todos.map { $0.makeModel() }.forEach(modelContext.insert)
        archive.recurringItems.map { $0.makeModel() }.forEach(modelContext.insert)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        guard let restoredSettings = try PropertyListSerialization.propertyList(
            from: archive.settingsPropertyList,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw AppBackupError.invalidSettings
        }

        restoredSettings.forEach { defaults.set($0.value, forKey: $0.key) }
        // Storage mode is device-specific and only changes through its explicit
        // restart flow. A data restore may not silently switch stores.
        if let currentICloudSetting {
            defaults.set(currentICloudSetting, forKey: SettingsKeys.iCloudSyncEnabled)
        }
        if let currentLanguage {
            defaults.set(currentLanguage, forKey: SettingsKeys.language)
        }
        defaults.set(true, forKey: SettingsKeys.hasCompletedWelcome)
#if !os(macOS)
        CalendarWidgetSnapshotPublisher.clear()
#endif
    }

    nonisolated static func validate(_ archive: AppBackupArchive) throws {
        guard archive.formatVersion == AppBackupArchive.currentFormatVersion else {
            throw AppBackupError.unsupportedVersion(archive.formatVersion)
        }
        guard (try? PropertyListSerialization.propertyList(
            from: archive.settingsPropertyList,
            options: [],
            format: nil
        )) is [String: Any] else {
            throw AppBackupError.invalidSettings
        }
    }

    nonisolated static func encode(_ archive: AppBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    nonisolated static func decode(_ data: Data) throws -> AppBackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(AppBackupArchive.self, from: data)
        try validate(archive)
        return archive
    }

    static func createAutomaticSnapshot(
        from modelContext: ModelContext,
        reason: String,
        defaults: UserDefaults = .standard
    ) throws {
        let archive = try makeArchive(from: modelContext, defaults: defaults)
        let directory = try backupDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let safeReason = reason.replacingOccurrences(of: "[^A-Za-z0-9-]", with: "-", options: .regularExpression)
        let url = directory.appendingPathComponent(
            "backup-\(formatter.string(from: archive.createdAt))-\(safeReason).json"
        )
        try encode(archive).write(to: url, options: .atomic)
        try pruneAutomaticSnapshots(in: directory, keeping: 5)
    }

    static func latestAutomaticSnapshot() throws -> AppBackupArchive? {
        let directory = try backupDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let latest = try urls.max {
            let left = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let right = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return left < right
        }
        guard let latest else { return nil }
        return try decode(Data(contentsOf: latest))
    }

    private static func backupDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("SafetyBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func pruneAutomaticSnapshots(in directory: URL, keeping count: Int) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let sorted = try urls.sorted {
            let left = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let right = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return left > right
        }
        for url in sorted.dropFirst(count) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
