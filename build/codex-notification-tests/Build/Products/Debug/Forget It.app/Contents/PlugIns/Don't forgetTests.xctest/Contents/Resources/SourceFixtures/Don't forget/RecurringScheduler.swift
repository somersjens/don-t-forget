import Foundation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let recurringSyncRequested = Notification.Name("recurring.syncRequested")
}

@MainActor
@Observable
final class AppActivityState {
    enum Activity: Hashable {
        case recurringSync
        case themeChange
        case calendarSync
        case calendarExtension
    }

    static let shared = AppActivityState()
    private(set) var activeActivities: Set<Activity> = []

    /// Drives the visible indicator. It intentionally lags `isActive`: very
    /// short activities finish before this becomes true, so the indicator
    /// never flickers, and it is cleared immediately once all work is done.
    private(set) var isIndicatorVisible = false

    @ObservationIgnored private var delayedFinishTasks: [Activity: Task<Void, Never>] = [:]
    @ObservationIgnored private var indicatorPresentationTask: Task<Void, Never>?

    var isActive: Bool { !activeActivities.isEmpty }
    var isRecurringSyncActive: Bool { activeActivities.contains(.recurringSync) }

    private init() {}

    func begin(_ activity: Activity) {
        delayedFinishTasks[activity]?.cancel()
        delayedFinishTasks[activity] = nil
        activeActivities.insert(activity)
        scheduleIndicatorPresentationIfNeeded()
    }

    private func scheduleIndicatorPresentationIfNeeded() {
        guard !isIndicatorVisible, indicatorPresentationTask == nil else { return }
        indicatorPresentationTask = Task { @MainActor in
            // Present only when the work lasts long enough to be noticeable.
            try? await Task.sleep(for: .milliseconds(400))
            indicatorPresentationTask = nil
            guard !Task.isCancelled, !activeActivities.isEmpty else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                isIndicatorVisible = true
            }
        }
    }

    /// A private-context save completes before live queries have merged the
    /// inserted occurrences and SwiftUI has laid out the affected calendar.
    /// Keep the indicator visible through that short settling phase.
    func finish(_ activity: Activity, after delay: Duration = .milliseconds(750)) {
        delayedFinishTasks[activity]?.cancel()
        guard activeActivities.contains(activity) else { return }
        delayedFinishTasks[activity] = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Give the query merge and the resulting layout their own turns.
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            activeActivities.remove(activity)
            delayedFinishTasks[activity] = nil
            if activeActivities.isEmpty {
                // Hide immediately once the interface is fully interactive
                // again; never let the indicator linger.
                indicatorPresentationTask?.cancel()
                indicatorPresentationTask = nil
                isIndicatorVisible = false
            }
        }
    }
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

    /// Captures a complete recurrence sync as value types so the SwiftData
    /// fetch, diff and save can run in a private context off the UI actor.
    static func fullSyncPlan(
        items: [RecurringItem],
        through endDate: Date
    ) -> RecurringFullSyncPlan {
        let today = AppCalendar.startOfDay(.now)
        return RecurringFullSyncPlan(
            today: today,
            series: items.map { item in
                RecurrenceEngine.prepareLegacyItem(item)
                return RecurringFullSyncPlan.Series(
                    itemID: item.id,
                    baseTitle: item.title,
                    entries: seriesPlan(
                        for: item,
                        from: today,
                        through: endDate
                    ).entries
                )
            }
        )
    }

    /// Precomputes recurrence dates on the UI actor from the already-fetched
    /// recurring items. The heavier SwiftData fetch, diff and save are applied
    /// by `RecurringExtensionWorker` away from the UI actor.
    static func extensionPlan(
        items: [RecurringItem],
        from startDate: Date,
        through endDate: Date
    ) -> RecurringExtensionPlan {
        let largestReminderOffset = items.compactMap(\.reminderDaysBefore).max() ?? 0
        let generationStart = AppCalendar.calendar.date(
            byAdding: .day,
            value: -max(0, largestReminderOffset),
            to: AppCalendar.startOfDay(startDate)
        ) ?? AppCalendar.startOfDay(startDate)

        let series = items.map { item in
            RecurrenceEngine.prepareLegacyItem(item)
            return RecurringExtensionPlan.Series(
                itemID: item.id,
                entries: desiredEntries(
                    for: item,
                    from: generationStart,
                    through: endDate
                ).map {
                    RecurringSeriesSyncPlan.Entry(
                        key: $0.key,
                        legacyKey: $0.legacyKey,
                        date: $0.date,
                        title: $0.title,
                        accent: $0.accent
                    )
                }
            )
        }

        return RecurringExtensionPlan(
            generationStart: generationStart,
            endDate: endDate,
            series: series
        )
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
                occurrenceTitle = age.map { "🎂 \(item.title) · \($0)" } ?? "🎂 \(item.title)"
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
                let reminderTiming = AppCalendar.locale.localizedFormat(
                    days == 1 ? "birthday.reminder.inOneDay" : "birthday.reminder.inDays",
                    days
                )
                let reminderTitle = "\(item.title) 🎂 \(reminderTiming)"

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

struct RecurringExtensionPlan: Sendable {
    struct Series: Sendable {
        let itemID: UUID
        let entries: [RecurringSeriesSyncPlan.Entry]
    }

    let generationStart: Date
    let endDate: Date
    let series: [Series]
}

struct RecurringFullSyncPlan: Sendable {
    struct Series: Sendable {
        let itemID: UUID
        let baseTitle: String
        let entries: [RecurringSeriesSyncPlan.Entry]
    }

    let today: Date
    let series: [Series]
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

/// Shared by the private-context workers. Writes only fields that actually
/// changed: unconditional assignments marked every touched occurrence dirty,
/// which turned each horizon extension into a large save whose merge stalled
/// the main actor (visible as scrolling that briefly stopped responding).
nonisolated enum RecurringWorkerUpdate {
    static func apply(
        _ desired: RecurringSeriesSyncPlan.Entry,
        to entry: DayEntry,
        itemID: UUID
    ) {
        let desiredDate = entry.recurringDateOverride ?? desired.date
        let needsParsing = entry.rawText != desired.title
        if entry.date != desiredDate {
            entry.date = desiredDate
        }
        if needsParsing {
            entry.rawText = desired.title
        }
        if !entry.showOnWidget {
            entry.showOnWidget = true
        }
        if entry.recurringItemIdentifier != itemID {
            entry.recurringItemIdentifier = itemID
        }
        if entry.recurringOccurrenceKey != desired.key {
            entry.recurringOccurrenceKey = desired.key
        }
        if entry.accentRawValue != desired.accent {
            entry.accentRawValue = desired.accent
        }
        if needsParsing {
            entry.refreshParsedFields()
        }
    }
}

/// Reconciles all generated occurrences in one private-context transaction.
/// This avoids publishing hundreds of individual inserts on the main context
/// when a daily (or dense weekly) series is added.
nonisolated enum RecurringFullSyncWorker {
    private struct Identity: Hashable {
        let itemID: UUID
        let key: String
    }

    private struct LegacyEntryKey: Hashable {
        let date: Date
        let title: String

        init(date: Date, title: String) {
            self.date = Calendar.current.startOfDay(for: date)
            self.title = title
        }
    }

    static func sync(
        plan: RecurringFullSyncPlan,
        in modelContainer: ModelContainer
    ) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var entries = try context.fetch(FetchDescriptor<DayEntry>())
        let validItemIDs = Set(plan.series.map(\.itemID))

        let orphaned = entries.filter { entry in
            guard let itemID = entry.recurringItemIdentifier else { return false }
            return entry.date >= plan.today && !validItemIDs.contains(itemID)
        }
        remove(orphaned, from: &entries, in: context)

        var linkedByIdentity: [Identity: DayEntry] = [:]
        var linkedByItem: [UUID: [DayEntry]] = [:]
        var legacyByDateAndTitle: [LegacyEntryKey: DayEntry] = [:]

        for entry in entries {
            if let itemID = entry.recurringItemIdentifier {
                linkedByItem[itemID, default: []].append(entry)
                if let key = entry.recurringOccurrenceKey {
                    let identity = Identity(itemID: itemID, key: key)
                    if linkedByIdentity[identity] == nil {
                        linkedByIdentity[identity] = entry
                    }
                }
            } else if entry.source == .recurring {
                let key = LegacyEntryKey(date: entry.date, title: entry.rawText)
                if legacyByDateAndTitle[key] == nil {
                    legacyByDateAndTitle[key] = entry
                }
            }
        }

        for series in plan.series {
            let validKeys = Set(series.entries.flatMap { [$0.key, $0.legacyKey] })
            let stale = (linkedByItem[series.itemID] ?? []).filter { entry in
                entry.date >= plan.today
                    && !validKeys.contains(entry.recurringOccurrenceKey ?? "")
            }
            remove(stale, from: &entries, in: context)

            for desired in series.entries {
                let identity = Identity(itemID: series.itemID, key: desired.key)
                let legacyIdentity = Identity(itemID: series.itemID, key: desired.legacyKey)
                let legacyEntry = legacyByDateAndTitle[
                    LegacyEntryKey(date: desired.date, title: series.baseTitle)
                ] ?? legacyByDateAndTitle[
                    LegacyEntryKey(date: desired.date, title: desired.title)
                ]

                if let existing = linkedByIdentity[identity]
                    ?? linkedByIdentity[legacyIdentity]
                    ?? legacyEntry {
                    if legacyEntry?.id == existing.id {
                        legacyByDateAndTitle.removeValue(
                            forKey: LegacyEntryKey(date: desired.date, title: series.baseTitle)
                        )
                        legacyByDateAndTitle.removeValue(
                            forKey: LegacyEntryKey(date: desired.date, title: desired.title)
                        )
                    }
                    update(existing, with: desired, itemID: series.itemID)
                    linkedByIdentity[identity] = existing
                    continue
                }

                let entry = DayEntry(
                    date: desired.date,
                    rawText: desired.title,
                    source: .recurring,
                    manualOrder: 0
                )
                entry.showOnWidget = true
                entry.recurringItemIdentifier = series.itemID
                entry.recurringOccurrenceKey = desired.key
                entry.accentRawValue = desired.accent
                context.insert(entry)
                entries.append(entry)
                linkedByIdentity[identity] = entry
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
        RecurringWorkerUpdate.apply(desired, to: entry, itemID: itemID)
    }

    private static func remove(
        _ removed: [DayEntry],
        from entries: inout [DayEntry],
        in context: ModelContext
    ) {
        guard !removed.isEmpty else { return }
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

/// Appends precomputed future occurrences in a private SwiftData context.
/// Keeping this work off the main actor prevents reaching the agenda boundary
/// from pausing touch delivery while the batch is fetched and saved.
nonisolated enum RecurringExtensionWorker {
    private struct Identity: Hashable {
        let itemID: UUID
        let key: String
    }

    static func extend(
        plan: RecurringExtensionPlan,
        in modelContainer: ModelContainer
    ) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let generationStart = plan.generationStart
        let endDate = plan.endDate
        let existingEntries = try context.fetch(FetchDescriptor<DayEntry>(
            predicate: #Predicate { entry in
                entry.recurringItemIdentifier != nil
                    && entry.date >= generationStart
                    && entry.date <= endDate
            }
        ))
        var existingByIdentity: [Identity: DayEntry] = [:]

        for entry in existingEntries {
            guard let itemID = entry.recurringItemIdentifier,
                  let key = entry.recurringOccurrenceKey else {
                continue
            }
            existingByIdentity[Identity(itemID: itemID, key: key)] = entry
        }

        // Save in bounded batches. One monolithic save merged hundreds of new
        // occurrences into the main context in a single pass, which stalled
        // touch handling exactly when the user resumed scrolling. Smaller
        // merges let user interaction interleave with the background work.
        let saveBatchSize = 120
        var insertedSinceLastSave = 0

        for series in plan.series {
            for desired in series.entries {
                let identity = Identity(itemID: series.itemID, key: desired.key)
                let legacyIdentity = Identity(itemID: series.itemID, key: desired.legacyKey)
                if let existing = existingByIdentity[identity]
                    ?? existingByIdentity[legacyIdentity] {
                    update(existing, with: desired, itemID: series.itemID)
                    existingByIdentity[identity] = existing
                    continue
                }

                let entry = DayEntry(
                    date: desired.date,
                    rawText: desired.title,
                    source: .recurring,
                    manualOrder: 0
                )
                entry.showOnWidget = true
                entry.recurringItemIdentifier = series.itemID
                entry.recurringOccurrenceKey = desired.key
                entry.accentRawValue = desired.accent
                context.insert(entry)
                existingByIdentity[identity] = entry
                insertedSinceLastSave += 1

                if insertedSinceLastSave >= saveBatchSize {
                    try context.save()
                    insertedSinceLastSave = 0
                }
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
        RecurringWorkerUpdate.apply(desired, to: entry, itemID: itemID)
    }
}

/// Applies a precomputed single-series plan in a private SwiftData context.
/// The recurrence math is cheap and remains on the UI actor; fetching,
/// diffing, deleting, inserting and saving the generated rows happens here.
nonisolated enum RecurringSeriesWorker {
    static func sync(
        itemID: UUID,
        plan: RecurringSeriesSyncPlan,
        in modelContainer: ModelContainer
    ) throws -> Bool {
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

        let didChangeEntries = context.hasChanges
        if didChangeEntries {
            try context.save()
        }
        return didChangeEntries
    }

    private static func update(
        _ entry: DayEntry,
        with desired: RecurringSeriesSyncPlan.Entry,
        itemID: UUID
    ) {
        RecurringWorkerUpdate.apply(desired, to: entry, itemID: itemID)
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
