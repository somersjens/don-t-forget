import EventKit
import Foundation
import SwiftData

@MainActor
enum CalendarSyncService {
    private static let eventStore = EKEventStore()
    private static let pendingDeletionKey = "calendarSync.pendingDeletionIdentifiers"

    static func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    static func requestAccessAndSync(entries: [DayEntry]) async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()

        guard granted else {
            return false
        }

        try sync(entries: entries)
        return true
    }

    static func sync(entries: [DayEntry]) throws {
        try flushPendingDeletions()

        let activeEntries = entries.filter {
            !$0.isRemoved
                && !$0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var usedEventIdentifiers = Set<String>()
        var obsoleteEventIdentifiers = Set<String>()
        var pendingAssignments: [(event: EKEvent, entries: [DayEntry])] = []

        for entry in activeEntries.filter({ $0.startMinutes != nil }) {
            try syncTimed(
                entry: entry,
                usedEventIdentifiers: &usedEventIdentifiers,
                pendingAssignments: &pendingAssignments
            )
        }

        let allDayEntries = activeEntries.filter { $0.startMinutes == nil }
        let entriesByTitle = Dictionary(grouping: allDayEntries, by: normalizedTitle)

        for title in entriesByTitle.keys.sorted() {
            let sortedEntries = (entriesByTitle[title] ?? []).sorted {
                if AppCalendar.isSameDay($0.date, $1.date) {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.date < $1.date
            }
            var consecutiveGroup: [DayEntry] = []

            for entry in sortedEntries {
                if let previous = consecutiveGroup.last,
                   !isNextCalendarDay(entry.date, after: previous.date) {
                    try syncAllDayGroup(
                        consecutiveGroup,
                        usedEventIdentifiers: &usedEventIdentifiers,
                        obsoleteEventIdentifiers: &obsoleteEventIdentifiers,
                        pendingAssignments: &pendingAssignments
                    )
                    consecutiveGroup = []
                }

                consecutiveGroup.append(entry)
            }

            if !consecutiveGroup.isEmpty {
                try syncAllDayGroup(
                    consecutiveGroup,
                    usedEventIdentifiers: &usedEventIdentifiers,
                    obsoleteEventIdentifiers: &obsoleteEventIdentifiers,
                    pendingAssignments: &pendingAssignments
                )
            }
        }

        for identifier in obsoleteEventIdentifiers.subtracting(usedEventIdentifiers) {
            if let obsoleteEvent = eventStore.event(withIdentifier: identifier) {
                try eventStore.remove(obsoleteEvent, span: .thisEvent, commit: false)
            }
        }

        try eventStore.commit()

        // A newly-created EKEvent does not reliably receive its permanent
        // identifier until the store commits, especially just after launch.
        for assignment in pendingAssignments {
            guard let identifier = assignment.event.eventIdentifier else { continue }
            for entry in assignment.entries {
                entry.calendarEventIdentifier = identifier
            }
        }
    }

    static func syncAll(in modelContext: ModelContext) throws {
        let entries = try modelContext.fetch(FetchDescriptor<DayEntry>())
        try sync(entries: entries)
    }

    static func removeSyncedEvents(for entries: [DayEntry]) throws {
        let identifiers = Set(entries.compactMap(\.calendarEventIdentifier))

        for identifier in identifiers {
            guard let event = eventStore.event(withIdentifier: identifier) else { continue }
            try eventStore.remove(event, span: .thisEvent, commit: false)
        }

        if !identifiers.isEmpty {
            try eventStore.commit()
        }
        UserDefaults.standard.removeObject(forKey: pendingDeletionKey)
    }

    /// Predicate-based variant for latency-sensitive paths (deleting or moving
    /// a single entry). The common case — no linked calendar event — performs
    /// no fetch at all; otherwise only rows sharing this identifier are
    /// counted instead of loading the complete table.
    static func deleteEventIfUnshared(
        for entry: DayEntry,
        in modelContext: ModelContext
    ) {
        guard let identifier = entry.calendarEventIdentifier else { return }

        let entryID = entry.id
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { other in
                other.calendarEventIdentifier == identifier
                    && other.id != entryID
                    && !other.isRemoved
            }
        )
        let isShared = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0

        guard !isShared else { return }
        enqueueEventDeletion(withIdentifier: identifier)
        entry.calendarEventIdentifier = nil
    }

    static func deleteEventIfUnshared(
        for entry: DayEntry,
        among entries: [DayEntry]
    ) {
        guard let identifier = entry.calendarEventIdentifier else {
            return
        }

        let isShared = entries.contains {
            $0.id != entry.id && $0.calendarEventIdentifier == identifier
        }

        guard !isShared else {
            return
        }

        enqueueEventDeletion(withIdentifier: identifier)
        entry.calendarEventIdentifier = nil
    }

    static func enqueueEventDeletion(withIdentifier identifier: String) {
        var identifiers = pendingDeletionIdentifiers
        identifiers.insert(identifier)
        UserDefaults.standard.set(Array(identifiers), forKey: pendingDeletionKey)
    }

    static func cancelEventDeletion(withIdentifier identifier: String) {
        var identifiers = pendingDeletionIdentifiers
        identifiers.remove(identifier)
        UserDefaults.standard.set(Array(identifiers), forKey: pendingDeletionKey)
    }

    private static func syncTimed(
        entry: DayEntry,
        usedEventIdentifiers: inout Set<String>,
        pendingAssignments: inout [(event: EKEvent, entries: [DayEntry])]
    ) throws {
        let event = reusableEvent(
            candidates: [entry.calendarEventIdentifier],
            usedEventIdentifiers: &usedEventIdentifiers
        )

        event.title = entry.rawText
        event.isAllDay = false
        event.startDate = date(on: entry.date, minutes: entry.startMinutes ?? 0)

        if let endMinutes = entry.endMinutes {
            event.endDate = date(on: entry.date, minutes: endMinutes)
        } else {
            event.endDate = AppCalendar.calendar.date(
                byAdding: .hour,
                value: 1,
                to: event.startDate
            ) ?? event.startDate
        }

        try eventStore.save(event, span: .thisEvent, commit: false)
        pendingAssignments.append((event, [entry]))
        if let eventIdentifier = event.eventIdentifier {
            usedEventIdentifiers.insert(eventIdentifier)
        }
    }

    private static func syncAllDayGroup(
        _ entries: [DayEntry],
        usedEventIdentifiers: inout Set<String>,
        obsoleteEventIdentifiers: inout Set<String>,
        pendingAssignments: inout [(event: EKEvent, entries: [DayEntry])]
    ) throws {
        guard let firstEntry = entries.first, let lastEntry = entries.last else {
            return
        }

        let identifiers = entries.map(\.calendarEventIdentifier)
        let event = reusableEvent(
            candidates: identifiers,
            usedEventIdentifiers: &usedEventIdentifiers
        )

        event.title = firstEntry.rawText
        event.isAllDay = true
        event.startDate = AppCalendar.startOfDay(firstEntry.date)

        let dayAfterLast = AppCalendar.calendar.date(
            byAdding: .day,
            value: 1,
            to: AppCalendar.startOfDay(lastEntry.date)
        ) ?? AppCalendar.startOfDay(lastEntry.date)
        // Keep the boundary inside the final intended calendar day. Some
        // Calendar backends expose midnight of the following day as an extra
        // visible all-day date (for example 24–26 for entries on 24 and 25).
        event.endDate = dayAfterLast.addingTimeInterval(-1)

        try eventStore.save(event, span: .thisEvent, commit: false)
        pendingAssignments.append((event, entries))

        if let eventIdentifier = event.eventIdentifier {
            usedEventIdentifiers.insert(eventIdentifier)
        }

        let obsoleteIdentifiers = Set(identifiers.compactMap { $0 })
            .subtracting(event.eventIdentifier.map { [$0] } ?? [])
        obsoleteEventIdentifiers.formUnion(obsoleteIdentifiers)
    }

    private static func reusableEvent(
        candidates: [String?],
        usedEventIdentifiers: inout Set<String>
    ) -> EKEvent {
        for identifier in candidates.compactMap({ $0 })
            where !usedEventIdentifiers.contains(identifier) {
            if let event = eventStore.event(withIdentifier: identifier) {
                return event
            }
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = eventStore.defaultCalendarForNewEvents
        return event
    }

    private static var pendingDeletionIdentifiers: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: pendingDeletionKey) ?? [])
    }

    private static func flushPendingDeletions() throws {
        let identifiers = pendingDeletionIdentifiers
        guard !identifiers.isEmpty else { return }

        for identifier in identifiers {
            guard let event = eventStore.event(withIdentifier: identifier) else { continue }
            try eventStore.remove(event, span: .thisEvent, commit: false)
        }

        try eventStore.commit()
        UserDefaults.standard.removeObject(forKey: pendingDeletionKey)
    }

    private static func normalizedTitle(for entry: DayEntry) -> String {
        entry.rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func isNextCalendarDay(_ date: Date, after previousDate: Date) -> Bool {
        guard let expectedDate = AppCalendar.calendar.date(
            byAdding: .day,
            value: 1,
            to: AppCalendar.startOfDay(previousDate)
        ) else {
            return false
        }

        return AppCalendar.isSameDay(expectedDate, date)
    }

    private static func date(on day: Date, minutes: Int) -> Date {
        let startOfDay = AppCalendar.startOfDay(day)
        return AppCalendar.calendar.date(
            byAdding: .minute,
            value: minutes,
            to: startOfDay
        ) ?? startOfDay
    }
}
