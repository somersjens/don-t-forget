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

    var createdAt: Date

    init(
        title: String = "",
        frequencyText: String = "",
        nextDate: Date = .now,
        reminderMinutesBefore: Int? = nil,
        showOnWidget: Bool = true
    ) {
        self.id = UUID()
        self.title = title
        self.frequencyText = frequencyText
        self.nextDate = AppCalendar.startOfDay(nextDate)
        self.reminderMinutesBefore = reminderMinutesBefore
        self.showOnWidget = showOnWidget
        self.createdAt = .now
    }
}
