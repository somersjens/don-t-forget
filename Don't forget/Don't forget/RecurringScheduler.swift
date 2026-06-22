import Foundation
import SwiftData

@MainActor
enum RecurringScheduler {
    static func syncAll(
        items: [RecurringItem],
        in modelContext: ModelContext,
        through endDate: Date
    ) {
        let today = AppCalendar.startOfDay(.now)
        var allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        let validItemIDs = Set(items.map(\.id))
        let orphanedEntries = allEntries.filter {
            guard let itemID = $0.recurringItemIdentifier else { return false }
            return $0.date >= today && !validItemIDs.contains(itemID)
        }
        remove(orphanedEntries, from: &allEntries, in: modelContext)

        for item in items {
            RecurrenceEngine.prepareLegacyItem(item)
            let desired = desiredEntries(for: item, from: today, through: endDate)
            sync(item: item, desired: desired, allEntries: &allEntries, in: modelContext)
        }
    }

    static func syncTwoYears(items: [RecurringItem], in modelContext: ModelContext) {
        guard let endDate = AppCalendar.calendar.date(byAdding: .year, value: 2, to: .now) else {
            return
        }
        syncAll(items: items, in: modelContext, through: endDate)
    }

    static func insertNextOccurrenceAndAdvance(item: RecurringItem, in modelContext: ModelContext) {
        guard let date = RecurrenceEngine.nextDate(for: item) else { return }
        var entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        let desired = desiredEntries(for: item, from: date, through: date)
        sync(item: item, desired: desired, allEntries: &entries, in: modelContext)
    }

    private struct DesiredEntry {
        let key: String
        let date: Date
        let title: String
        let accent: String
    }

    private static func desiredEntries(
        for item: RecurringItem,
        from startDate: Date,
        through endDate: Date
    ) -> [DesiredEntry] {
        let dates = RecurrenceEngine.dates(for: item, from: startDate, through: endDate)
        var result: [DesiredEntry] = []

        for date in dates {
            let dateKey = occurrenceDateKey(date)
            let age = item.recurrenceKind == .birthday
                ? RecurrenceEngine.ageTurning(for: item, on: date)
                : nil
            let occurrenceTitle: String

            if item.recurrenceKind == .birthday {
                occurrenceTitle = age.map { "🎂 \(item.title) · \($0) jaar" } ?? "🎂 \(item.title)"
            } else {
                occurrenceTitle = item.title
            }

            result.append(DesiredEntry(
                key: "occurrence:\(dateKey)",
                date: date,
                title: occurrenceTitle,
                accent: item.theme.rawValue
            ))

            if item.recurrenceKind == .birthday,
               let days = item.reminderDaysBefore,
               days > 0,
               let reminderDate = AppCalendar.calendar.date(byAdding: .day, value: -days, to: date),
               reminderDate >= AppCalendar.startOfDay(startDate) {
                let reminderTitle = age.map {
                    "\(item.title) wordt over \(days) dagen \($0)"
                } ?? "Verjaardag \(item.title) over \(days) dagen"

                result.append(DesiredEntry(
                    key: "reminder:\(dateKey):\(days)",
                    date: reminderDate,
                    title: reminderTitle,
                    accent: "birthdayReminder"
                ))
            }
        }

        return result
    }

    private static func sync(
        item: RecurringItem,
        desired: [DesiredEntry],
        allEntries: inout [DayEntry],
        in modelContext: ModelContext
    ) {
        let today = AppCalendar.startOfDay(.now)
        let desiredKeys = Set(desired.map(\.key))
        let linkedEntries = allEntries.filter {
            $0.recurringItemIdentifier == item.id && $0.date >= today
        }
        let staleEntries = linkedEntries.filter {
            guard let key = $0.recurringOccurrenceKey else { return true }
            return !desiredKeys.contains(key)
        }
        remove(staleEntries, from: &allEntries, in: modelContext)

        for desiredEntry in desired {
            let existing = allEntries.first {
                $0.recurringItemIdentifier == item.id &&
                $0.recurringOccurrenceKey == desiredEntry.key
            } ?? allEntries.first {
                $0.recurringItemIdentifier == nil &&
                $0.source == .recurring &&
                AppCalendar.isSameDay($0.date, desiredEntry.date) &&
                ($0.rawText == item.title || $0.rawText == desiredEntry.title)
            }

            if let existing {
                existing.date = AppCalendar.startOfDay(desiredEntry.date)
                existing.rawText = desiredEntry.title
                existing.showOnWidget = item.showOnWidget
                existing.recurringItemIdentifier = item.id
                existing.recurringOccurrenceKey = desiredEntry.key
                existing.accentRawValue = desiredEntry.accent
                existing.refreshParsedFields()
            } else {
                let entry = DayEntry(
                    date: desiredEntry.date,
                    rawText: desiredEntry.title,
                    source: .recurring,
                    manualOrder: 0
                )
                entry.showOnWidget = item.showOnWidget
                entry.recurringItemIdentifier = item.id
                entry.recurringOccurrenceKey = desiredEntry.key
                entry.accentRawValue = desiredEntry.accent
                modelContext.insert(entry)
                allEntries.append(entry)
            }
        }
    }

    private static func occurrenceDateKey(_ date: Date) -> String {
        let components = AppCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func remove(
        _ entries: [DayEntry],
        from allEntries: inout [DayEntry],
        in modelContext: ModelContext
    ) {
        let removedIDs = Set(entries.map(\.id))
        let eventIDs = Set(entries.compactMap(\.calendarEventIdentifier))
        let remainingEventIDs = Set(allEntries.compactMap { entry in
            removedIDs.contains(entry.id) ? nil : entry.calendarEventIdentifier
        })

        for identifier in eventIDs.subtracting(remainingEventIDs) {
            try? CalendarSyncService.deleteEvent(withIdentifier: identifier)
        }
        for entry in entries {
            modelContext.delete(entry)
        }
        allEntries.removeAll { removedIDs.contains($0.id) }
    }
}
