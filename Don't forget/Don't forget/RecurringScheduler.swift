import Foundation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let recurringSyncRequested = Notification.Name("recurring.syncRequested")
}

@MainActor
@Observable
final class RecurringSyncState {
    static let shared = RecurringSyncState()
    private(set) var isSyncing = false

    private init() {}

    func begin() { isSyncing = true }
    func finish() { isSyncing = false }
}

@MainActor
enum RecurringScheduler {
    /// Builds a complete recurrence batch in an isolated context. The app's
    /// live queries only observe the single save at the end, instead of every
    /// inserted or updated occurrence along the way.
    static func syncAll(
        in modelContainer: ModelContainer,
        through endDate: Date
    ) throws {
        let batchContext = ModelContext(modelContainer)
        batchContext.autosaveEnabled = false
        let items = try batchContext.fetch(FetchDescriptor<RecurringItem>(
            predicate: #Predicate { !$0.isRemoved }
        ))
        syncAll(items: items, in: batchContext, through: endDate)
        if batchContext.hasChanges {
            try batchContext.save()
        }
    }

    /// Appends one future batch without recalculating or deleting the already
    /// visible horizon. A small overlap preserves reminders that fall just
    /// before the new occurrence window.
    static func extendAll(
        in modelContainer: ModelContainer,
        from startDate: Date,
        through endDate: Date
    ) throws {
        let batchContext = ModelContext(modelContainer)
        batchContext.autosaveEnabled = false
        let items = try batchContext.fetch(FetchDescriptor<RecurringItem>(
            predicate: #Predicate { !$0.isRemoved }
        ))
        let largestReminderOffset = items.compactMap(\.reminderDaysBefore).max() ?? 0
        let generationStart = AppCalendar.calendar.date(
            byAdding: .day,
            value: -max(0, largestReminderOffset),
            to: AppCalendar.startOfDay(startDate)
        ) ?? AppCalendar.startOfDay(startDate)
        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { entry in
            entry.recurringItemIdentifier != nil
                && entry.date >= generationStart
                && entry.date <= endDate
        })
        let existingEntries = try batchContext.fetch(descriptor)
        var existingByIdentity: [OccurrenceIdentity: DayEntry] = [:]

        for entry in existingEntries {
            guard let itemID = entry.recurringItemIdentifier,
                  let key = entry.recurringOccurrenceKey else {
                continue
            }
            existingByIdentity[OccurrenceIdentity(itemID: itemID, key: key)] = entry
        }

        for item in items {
            RecurrenceEngine.prepareLegacyItem(item)
            let desired = desiredEntries(
                for: item,
                from: generationStart,
                through: endDate
            )

            for desiredEntry in desired {
                let identity = OccurrenceIdentity(itemID: item.id, key: desiredEntry.key)
                if let existing = existingByIdentity[identity] {
                    update(existing, with: desiredEntry, item: item)
                    continue
                }

                let entry = DayEntry(
                    date: desiredEntry.date,
                    rawText: desiredEntry.title,
                    source: .recurring,
                    manualOrder: 0
                )
                entry.recurringItemIdentifier = item.id
                entry.recurringOccurrenceKey = desiredEntry.key
                entry.accentRawValue = desiredEntry.accent
                batchContext.insert(entry)
                existingByIdentity[identity] = entry
            }
        }

        if batchContext.hasChanges {
            try batchContext.save()
        }
    }

    static func syncAll(
        items: [RecurringItem],
        in modelContext: ModelContext,
        through endDate: Date
    ) {
        let today = AppCalendar.startOfDay(.now)
        var allEntries: [DayEntry]
        do {
            allEntries = try modelContext.fetch(FetchDescriptor<DayEntry>())
        } catch {
            PersistenceSafety.report(error)
            return
        }
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
        var entries: [DayEntry]
        do {
            entries = try modelContext.fetch(FetchDescriptor<DayEntry>())
        } catch {
            PersistenceSafety.report(error)
            return
        }
        let desired = desiredEntries(for: item, from: date, through: date)
        sync(item: item, desired: desired, allEntries: &entries, in: modelContext)
    }

    static func seriesPlan(
        for item: RecurringItem,
        from startDate: Date,
        through endDate: Date
    ) -> RecurringSeriesSyncPlan {
        RecurringSeriesSyncPlan(entries: desiredEntries(
            for: item,
            from: startDate,
            through: endDate
        ).map {
            RecurringSeriesSyncPlan.Entry(
                key: $0.key,
                legacyKey: $0.legacyKey,
                date: $0.date,
                title: $0.title,
                accent: $0.accent
            )
        })
    }

    private struct DesiredEntry {
        let key: String
        let legacyKey: String
        let date: Date
        let title: String
        let accent: String
    }

    private struct OccurrenceIdentity: Hashable {
        let itemID: UUID
        let key: String
    }

    private static func desiredEntries(
        for item: RecurringItem,
        from startDate: Date,
        through endDate: Date
    ) -> [DesiredEntry] {
        let dates = RecurrenceEngine.scheduledDates(for: item, from: startDate, through: endDate)
        var result: [DesiredEntry] = []

        for scheduledDate in dates {
            let baseDateKey = occurrenceDateKey(scheduledDate.baseDate)
            let shiftedDateKey = occurrenceDateKey(scheduledDate.date)
            let date = scheduledDate.date
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
                key: "occurrence-v2:\(baseDateKey)",
                legacyKey: "occurrence:\(shiftedDateKey)",
                date: date,
                title: occurrenceTitle,
                accent: item.themeRawValue
            ))

            if item.recurrenceKind == .birthday,
               let days = item.reminderDaysBefore,
               days > 0,
               let reminderDate = AppCalendar.calendar.date(byAdding: .day, value: -days, to: date),
               reminderDate >= AppCalendar.startOfDay(startDate) {
                let reminderTitle = "\(item.title) 🎂 over \(days) \(days == 1 ? "dag" : "dagen")"

                result.append(DesiredEntry(
                    key: "reminder-v2:\(baseDateKey):\(days)",
                    legacyKey: "reminder:\(shiftedDateKey):\(days)",
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
        let desiredKeys = Set(desired.flatMap { [$0.key, $0.legacyKey] })
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
            let existing = linkedByKey[desiredEntry.key]?.first
                ?? linkedByKey[desiredEntry.legacyKey]?.first
                ?? legacyEntry

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

struct RecurringSeriesSyncPlan: Sendable {
    struct Entry: Sendable {
        let key: String
        let legacyKey: String
        let date: Date
        let title: String
        let accent: String
    }

    let entries: [Entry]
}

/// Applies a precomputed single-series plan in a private SwiftData context.
/// The recurrence math is cheap and remains on the UI actor; fetching,
/// diffing, deleting, inserting and saving the generated rows happens here.
nonisolated enum RecurringSeriesWorker {
    static func sync(
        itemID: UUID,
        plan: RecurringSeriesSyncPlan,
        in modelContainer: ModelContainer
    ) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var entries = try context.fetch(FetchDescriptor<DayEntry>(
            predicate: #Predicate { entry in
                entry.recurringItemIdentifier == itemID
            }
        ))
        let today = Calendar.current.startOfDay(for: .now)
        let validKeys = Set(plan.entries.flatMap { [$0.key, $0.legacyKey] })
        let stale = entries.filter {
            $0.date >= today && !validKeys.contains($0.recurringOccurrenceKey ?? "")
        }
        remove(stale, from: &entries, in: context)

        var entriesByKey = Dictionary(
            grouping: entries,
            by: { $0.recurringOccurrenceKey ?? "" }
        )
        for desired in plan.entries {
            if let entry = entriesByKey[desired.key]?.first
                ?? entriesByKey[desired.legacyKey]?.first {
                update(entry, with: desired, itemID: itemID)
                entriesByKey[desired.key] = [entry]
            } else {
                let entry = DayEntry(
                    date: desired.date,
                    rawText: desired.title,
                    source: .recurring,
                    manualOrder: 0
                )
                entry.showOnWidget = true
                entry.recurringItemIdentifier = itemID
                entry.recurringOccurrenceKey = desired.key
                entry.accentRawValue = desired.accent
                context.insert(entry)
                entries.append(entry)
                entriesByKey[desired.key] = [entry]
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private static func update(
        _ entry: DayEntry,
        with desired: RecurringSeriesSyncPlan.Entry,
        itemID: UUID
    ) {
        let desiredDate = entry.recurringDateOverride ?? desired.date
        let needsParsing = entry.rawText != desired.title
        entry.date = desiredDate
        entry.rawText = desired.title
        entry.showOnWidget = true
        entry.recurringItemIdentifier = itemID
        entry.recurringOccurrenceKey = desired.key
        entry.accentRawValue = desired.accent
        if needsParsing {
            entry.refreshParsedFields()
        }
    }

    private static func remove(
        _ removed: [DayEntry],
        from entries: inout [DayEntry],
        in context: ModelContext
    ) {
        let removedIDs = Set(removed.map(\.id))
        let eventIDs = Set(removed.compactMap(\.calendarEventIdentifier))
        let remainingEventIDs = Set(entries.compactMap { entry in
            removedIDs.contains(entry.id) ? nil : entry.calendarEventIdentifier
        })
        for identifier in eventIDs.subtracting(remainingEventIDs) {
            Task { @MainActor in
                CalendarSyncService.enqueueEventDeletion(withIdentifier: identifier)
            }
        }
        for entry in removed {
            context.delete(entry)
        }
        entries.removeAll { removedIDs.contains($0.id) }
    }
}
