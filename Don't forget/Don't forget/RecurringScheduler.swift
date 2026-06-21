import Foundation
import SwiftData

@MainActor
enum RecurringScheduler {
    static func syncAllVisibleWeeks(
        items: [RecurringItem],
        in modelContext: ModelContext,
        weeksAhead: Int = 12
    ) {
        guard let endDate = AppCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: weeksAhead,
            to: .now
        ) else {
            return
        }

        for item in items {
            syncItem(
                item,
                until: endDate,
                in: modelContext
            )
        }
    }

    static func syncItem(
        _ item: RecurringItem,
        until endDate: Date,
        in modelContext: ModelContext
    ) {
        let dates = RecurrenceParser.upcomingDates(
            startingAt: item.nextDate,
            frequencyText: item.frequencyText,
            until: endDate
        )

        for date in dates {
            insertOccurrenceIfNeeded(
                item: item,
                date: date,
                in: modelContext
            )
        }
    }

    static func insertNextOccurrenceAndAdvance(
        item: RecurringItem,
        in modelContext: ModelContext
    ) {
        insertOccurrenceIfNeeded(
            item: item,
            date: item.nextDate,
            in: modelContext
        )

        if let nextDate = RecurrenceParser.nextDate(
            after: item.nextDate,
            frequencyText: item.frequencyText
        ) {
            item.nextDate = nextDate
        }
    }

    static func insertOccurrenceIfNeeded(
        item: RecurringItem,
        date: Date,
        in modelContext: ModelContext
    ) {
        let cleanTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            return
        }

        let targetDate = AppCalendar.startOfDay(date)
        let recurringSource = EntrySource.recurring.rawValue

        let descriptor = FetchDescriptor<DayEntry>()
        let existingEntries = (try? modelContext.fetch(descriptor)) ?? []

        let alreadyExists = existingEntries.contains { entry in
            entry.rawText == cleanTitle &&
            AppCalendar.isSameDay(entry.date, targetDate) &&
            entry.sourceRawValue == recurringSource
        }

        guard !alreadyExists else {
            return
        }

        let entry = DayEntry(
            date: targetDate,
            rawText: cleanTitle,
            source: .recurring,
            manualOrder: 0
        )

        entry.showOnWidget = item.showOnWidget

        modelContext.insert(entry)
    }
}
