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
            let age = item.recurrenceKind == .birthday && !item.birthdayYearUncertain
                ? RecurrenceEngine.ageTurning(for: item, on: date)
                : nil
            let occurrenceTitle: String

            if item.recurrenceKind == .birthday {
                occurrenceTitle = age.map { "🎂 \(item.title) · \($0) jaar" } ?? "🎂 \(item.title)"
            } else if item.recurrenceKind == .yearly {
                let years = max(0, AppCalendar.calendar.dateComponents(
                    [.year],
                    from: AppCalendar.startOfDay(item.nextDate),
                    to: AppCalendar.startOfDay(date)
                ).year ?? 0)
                occurrenceTitle = "\(item.title) · \(years) jaar"
            } else {
                occurrenceTitle = item.title
            }

            result.append(DesiredEntry(
                key: "occurrence:\(dateKey)",
                date: date,
                title: occurrenceTitle,
                accent: item.themeRawValue
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
                    accent: item.themeRawValue
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

        let linkedByKey = Dictionary(
            grouping: allEntries.filter { $0.recurringItemIdentifier == item.id },
            by: { $0.recurringOccurrenceKey ?? "" }
        )
        let legacyByDateAndTitle = Dictionary(
            grouping: allEntries.filter {
                $0.recurringItemIdentifier == nil && $0.source == .recurring
            }
        ) { entry in
            LegacyEntryKey(date: entry.date, title: entry.rawText)
        }

        for desiredEntry in desired {
            let legacyEntry = legacyByDateAndTitle[
                LegacyEntryKey(date: desiredEntry.date, title: item.title)
            ]?.first ?? legacyByDateAndTitle[
                LegacyEntryKey(date: desiredEntry.date, title: desiredEntry.title)
            ]?.first
            let existing = linkedByKey[desiredEntry.key]?.first ?? legacyEntry

            if let existing {
                update(
                    existing,
                    with: desiredEntry,
                    item: item
                )
            } else {
                let entry = DayEntry(
                    date: desiredEntry.date,
                    rawText: desiredEntry.title,
                    source: .recurring,
                    manualOrder: 0
                )
                entry.showOnWidget = true
                entry.recurringItemIdentifier = item.id
                entry.recurringOccurrenceKey = desiredEntry.key
                entry.accentRawValue = desiredEntry.accent
                modelContext.insert(entry)
                allEntries.append(entry)
            }
        }
    }

    private struct LegacyEntryKey: Hashable {
        let date: Date
        let title: String

        init(date: Date, title: String) {
            self.date = AppCalendar.startOfDay(date)
            self.title = title
        }
    }

    private static func update(
        _ entry: DayEntry,
        with desiredEntry: DesiredEntry,
        item: RecurringItem
    ) {
        let desiredDate = entry.recurringDateOverride
            ?? AppCalendar.startOfDay(desiredEntry.date)
        let needsParsing = entry.rawText != desiredEntry.title

        if entry.date != desiredDate {
            entry.date = desiredDate
        }
        if needsParsing {
            entry.rawText = desiredEntry.title
        }
        if !entry.showOnWidget {
            entry.showOnWidget = true
        }
        if entry.recurringItemIdentifier != item.id {
            entry.recurringItemIdentifier = item.id
        }
        if entry.recurringOccurrenceKey != desiredEntry.key {
            entry.recurringOccurrenceKey = desiredEntry.key
        }
        if entry.accentRawValue != desiredEntry.accent {
            entry.accentRawValue = desiredEntry.accent
        }
        if needsParsing {
            entry.refreshParsedFields()
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
            CalendarSyncService.enqueueEventDeletion(withIdentifier: identifier)
        }
        for entry in entries {
            modelContext.delete(entry)
        }
        allEntries.removeAll { removedIDs.contains($0.id) }
    }
}
