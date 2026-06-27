import Foundation
import SwiftData

enum EntrySource: String, Codable, CaseIterable {
    case manual
    case recurring
    case todo
}

enum TodoBucket: String, Codable, CaseIterable {
    case today
    case shortTerm
    case longTerm
}

enum RecurringTheme: String, Codable, CaseIterable, Identifiable {
    case birthday
    case general
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .birthday: "Verjaardagen"
        case .general: "Algemeen"
        case .personal: "Persoonlijk"
        }
    }
}

enum RecurrenceKind: String, Codable, CaseIterable, Identifiable {
    case interval
    case quarterly
    case monthlyDay
    case monthlyOrdinalWeekday
    case approximateInterval
    case birthday

    var id: String { rawValue }
}

enum RecurrenceUnit: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
}

@Model
final class DayEntry {
    @Attribute(.unique) var id: UUID

    var date: Date
    var rawText: String

    var startMinutes: Int?
    var endMinutes: Int?

    var isUncertain: Bool
    var isDone: Bool
    var showOnWidget: Bool

    var sourceRawValue: String
    var manualOrder: Double

    var createdAt: Date
    var completedAt: Date?
    var calendarEventIdentifier: String?
    var recurringItemIdentifier: UUID?
    var recurringOccurrenceKey: String?
    var recurringDateOverride: Date?
    var accentRawValue: String = "none"

    init(
        date: Date,
        rawText: String = "",
        source: EntrySource = .manual,
        manualOrder: Double = 0
    ) {
        self.id = UUID()
        self.date = AppCalendar.startOfDay(date)
        self.rawText = rawText
        self.startMinutes = nil
        self.endMinutes = nil
        self.isUncertain = false
        self.isDone = false
        self.showOnWidget = true
        self.sourceRawValue = source.rawValue
        self.manualOrder = manualOrder
        self.createdAt = .now
        self.completedAt = nil
        self.calendarEventIdentifier = nil
        self.recurringItemIdentifier = nil
        self.recurringOccurrenceKey = nil
        self.recurringDateOverride = nil
        self.accentRawValue = "none"

        refreshParsedFields()
    }

    var source: EntrySource {
        get {
            EntrySource(rawValue: sourceRawValue) ?? .manual
        }
        set {
            sourceRawValue = newValue.rawValue
        }
    }

    var hasTime: Bool {
        startMinutes != nil
    }

    func refreshParsedFields() {
        let parsed = TimeParser.parse(rawText)
        startMinutes = parsed.startMinutes
        endMinutes = parsed.endMinutes
        isUncertain = parsed.isUncertain
    }

    func toggleDone() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }
}

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID

    var text: String
    var bucketRawValue: String

    var isDone: Bool
    var showOnWidget: Bool

    var createdAt: Date
    var completedAt: Date?

    init(
        text: String = "",
        bucket: TodoBucket = .today,
        showOnWidget: Bool = true
    ) {
        self.id = UUID()
        self.text = text
        self.bucketRawValue = bucket.rawValue
        self.isDone = false
        self.showOnWidget = showOnWidget
        self.createdAt = .now
        self.completedAt = nil
    }

    var bucket: TodoBucket {
        get {
            TodoBucket(rawValue: bucketRawValue) ?? .today
        }
        set {
            bucketRawValue = newValue.rawValue
        }
    }

    func toggleDone() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }
}

@Model
final class RecurringItem {
    @Attribute(.unique) var id: UUID

    var title: String
    var frequencyText: String
    var nextDate: Date

    var reminderMinutesBefore: Int?
    var showOnWidget: Bool

    var themeRawValue: String = "general"
    var recurrenceKindRawValue: String = "interval"
    var intervalValue: Int = 1
    var intervalUnitRawValue: String = "week"
    var monthlyDay: Int = 1
    var monthlyOrdinal: Int = 1
    var monthlyWeekday: Int = 2
    var reminderDaysBefore: Int?
    var birthDate: Date?
    var birthdayYearUncertain: Bool = false
    var notes: String = ""
    var recurrenceConfigurationVersion: Int = 0

    var createdAt: Date

    init(
        title: String = "",
        frequencyText: String = "",
        nextDate: Date = .now,
        reminderMinutesBefore: Int? = nil,
        showOnWidget: Bool = true,
        theme: RecurringTheme = .general,
        recurrenceKind: RecurrenceKind = .interval,
        intervalValue: Int = 1,
        intervalUnit: RecurrenceUnit = .week,
        monthlyDay: Int = 1,
        monthlyOrdinal: Int = 1,
        monthlyWeekday: Int = 2,
        reminderDaysBefore: Int? = nil,
        birthDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.frequencyText = frequencyText
        self.nextDate = AppCalendar.startOfDay(nextDate)
        self.reminderMinutesBefore = reminderMinutesBefore
        self.showOnWidget = showOnWidget
        self.themeRawValue = theme.rawValue
        self.recurrenceKindRawValue = recurrenceKind.rawValue
        self.intervalValue = max(1, intervalValue)
        self.intervalUnitRawValue = intervalUnit.rawValue
        self.monthlyDay = min(max(1, monthlyDay), 31)
        self.monthlyOrdinal = min(max(1, monthlyOrdinal), 5)
        self.monthlyWeekday = min(max(1, monthlyWeekday), 7)
        self.reminderDaysBefore = reminderDaysBefore
        self.birthDate = birthDate.map { AppCalendar.startOfDay($0) }
        self.notes = notes
        self.recurrenceConfigurationVersion = frequencyText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? 1 : 0
        self.createdAt = .now
    }


    var theme: RecurringTheme {
        get { RecurringTheme(rawValue: themeRawValue) ?? .general }
        set { themeRawValue = newValue.rawValue }
    }

    var recurrenceKind: RecurrenceKind {
        get { RecurrenceKind(rawValue: recurrenceKindRawValue) ?? .interval }
        set { recurrenceKindRawValue = newValue.rawValue }
    }

    var intervalUnit: RecurrenceUnit {
        get { RecurrenceUnit(rawValue: intervalUnitRawValue) ?? .week }
        set { intervalUnitRawValue = newValue.rawValue }
    }
}
