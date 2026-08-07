import Foundation
import SwiftData

/// Identity of one generated recurrence occurrence.
///
/// Both parts are stored on the entry and travel through iCloud, so every
/// device derives the same identity for the same occurrence. That is what lets
/// two independently generated copies be recognised as one row after CloudKit
/// has merged them into the store.
nonisolated struct OccurrenceIdentity: Hashable, Sendable {
    let itemID: UUID
    let key: String
}

/// Rules shared by every recurrence reconciliation path.
///
/// Occurrences are generated locally on each device instead of being synced as
/// a plan, so two invariants have to hold everywhere:
///
/// 1. A reconciliation may only delete inside the window it generated itself.
///    Deleting everything from today onwards let a device with a three-month
///    horizon erase the occurrences a device with a two-year horizon had
///    already generated and synced. The other device recreated them with fresh
///    identifiers on its next pass, and the two kept overwriting each other
///    through iCloud — which is what produced both the missing and the
///    duplicated birthdays and recurring items.
/// 2. When iCloud does deliver two copies of the same occurrence, every device
///    has to collapse them onto the *same* survivor. Choosing by the synced
///    `id` guarantees that: without a shared rule each device would keep a
///    different copy and delete the other's, so the duplicate never
///    disappears.
///
/// Everything here runs over arrays the callers already fetched. It adds one
/// dictionary pass and no extra store access. It stays off the main actor so
/// the private-context workers can call it where they do their diffing.
nonisolated enum RecurringOccurrenceReconciler {
    static func identity(of entry: DayEntry) -> OccurrenceIdentity? {
        guard let itemID = entry.recurringItemIdentifier,
              let key = entry.recurringOccurrenceKey,
              !key.isEmpty else {
            return nil
        }
        return OccurrenceIdentity(itemID: itemID, key: key)
    }

    /// Occurrences outside the generated window are left untouched: they were
    /// produced by a device with a longer horizon and are still wanted there.
    static func isInsideGeneratedWindow(
        _ entry: DayEntry,
        from startDate: Date,
        through endDate: Date
    ) -> Bool {
        entry.date >= startDate && entry.date <= endDate
    }

    /// Collapses occurrences that share an identity onto one deterministic
    /// survivor and returns the survivors, so callers can use this index
    /// instead of building their own.
    @discardableResult
    static func collapseDuplicates(
        among entries: inout [DayEntry],
        in context: ModelContext
    ) -> [OccurrenceIdentity: DayEntry] {
        var survivors: [OccurrenceIdentity: DayEntry] = [:]
        var discarded: [DayEntry] = []

        for entry in entries {
            guard let identity = identity(of: entry) else { continue }
            guard let rival = survivors[identity] else {
                survivors[identity] = entry
                continue
            }

            // The lowest identifier is the same choice on every device.
            let survivor = rival.id.uuidString <= entry.id.uuidString ? rival : entry
            let duplicate = survivor === rival ? entry : rival
            absorb(duplicate, into: survivor)
            survivors[identity] = survivor
            discarded.append(duplicate)
        }

        guard !discarded.isEmpty else { return survivors }

        let discardedIDs = Set(discarded.map(\.id))
        // A calendar event that moved to the survivor above must stay.
        let retainedEventIdentifiers = Set(entries.compactMap { entry in
            discardedIDs.contains(entry.id) ? nil : entry.calendarEventIdentifier
        })
        let obsoleteEventIdentifiers = Set(discarded.compactMap(\.calendarEventIdentifier))
            .subtracting(retainedEventIdentifiers)

        for identifier in obsoleteEventIdentifiers {
            Task { @MainActor in
                CalendarSyncService.enqueueEventDeletion(withIdentifier: identifier)
            }
        }
        for entry in discarded {
            context.delete(entry)
        }
        entries.removeAll { discardedIDs.contains($0.id) }

        return survivors
    }

    /// Keeps the state that only exists on the copy being discarded. The two
    /// rows are the same occurrence, so completing, hiding or moving either of
    /// them expressed one and the same intent.
    ///
    /// Every write is guarded: an unconditional assignment would mark the
    /// survivor dirty on every pass and push a pointless record to CloudKit.
    private static func absorb(_ duplicate: DayEntry, into survivor: DayEntry) {
        if duplicate.isRemoved, !survivor.isRemoved {
            survivor.isRemoved = true
        }
        if duplicate.isDone, !survivor.isDone {
            survivor.isDone = true
            survivor.completedAt = duplicate.completedAt
        } else if let duplicateCompletedAt = duplicate.completedAt,
                  let survivorCompletedAt = survivor.completedAt,
                  duplicateCompletedAt < survivorCompletedAt {
            survivor.completedAt = duplicateCompletedAt
        }
        if !duplicate.showOnWidget, survivor.showOnWidget {
            survivor.showOnWidget = false
        }
        if survivor.recurringDateOverride == nil,
           let override = duplicate.recurringDateOverride {
            survivor.recurringDateOverride = override
            if survivor.date != override {
                survivor.date = override
            }
        }
        if survivor.calendarEventIdentifier == nil,
           let identifier = duplicate.calendarEventIdentifier {
            survivor.calendarEventIdentifier = identifier
        }
        if survivor.manualOrder == 0, duplicate.manualOrder != 0 {
            survivor.manualOrder = duplicate.manualOrder
        }
        if duplicate.createdAt < survivor.createdAt {
            survivor.createdAt = duplicate.createdAt
        }
    }
}

/// Fingerprint of everything a generated series depends on.
///
/// Stored per device (never mirrored through iCloud) so each device can skip a
/// reconciliation it has already performed, while still repeating it after a
/// rule change, a horizon change or a date rollover.
enum RecurringSyncSignature {
    static func make(items: [RecurringItem]) -> String {
        let series = items.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [
                $0.id.uuidString, $0.title, $0.themeRawValue, $0.recurrenceKindRawValue,
                String($0.nextDate.timeIntervalSinceReferenceDate), String($0.intervalValue),
                $0.scheduleShiftsData, $0.intervalUnitRawValue, String($0.monthlyDay),
                String($0.monthlyOrdinal), String($0.monthlyWeekday),
                String($0.reminderDaysBefore ?? -1),
                String($0.birthDate?.timeIntervalSinceReferenceDate ?? -1),
                String($0.birthdayYearUncertain),
                String($0.annualMonth), $0.notes, $0.linksData
            ].joined(separator: "|")
        }.joined(separator: "\n")

        let today = AppCalendar.calendar.dateComponents(
            [.year, .month, .day],
            from: AppCalendar.today
        )
        return [
            series,
            RecurringGenerationWindow.horizonOption.rawValue,
            String(format: "%04d-%02d-%02d", today.year ?? 0, today.month ?? 0, today.day ?? 0)
        ].joined(separator: "\n")
    }
}

/// The window recurrence occurrences are generated for.
///
/// macOS and iOS used to pick this independently — three months in the Mac
/// calendar, two years when a Mac item was created, the user's preference on
/// iOS — which is exactly what made the two platforms fight over the same
/// series. Both platforms now read the same iCloud-synced preference.
enum RecurringGenerationWindow {
    static var horizonOption: RecurringHorizonOption {
        RecurringHorizonOption(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.recurringHorizon) ?? ""
        ) ?? .threeMonths
    }

    /// The preferred end date, extended to whatever this device already
    /// generated beyond it so a shorter preference never truncates a longer
    /// horizon that is still on screen.
    static func endDate(from startDate: Date = .now) -> Date {
        let preferred = AppCalendar.calendar.date(
            byAdding: .month,
            value: horizonOption.months,
            to: startDate
        ) ?? startDate
        let extendedThrough = UserDefaults.standard.double(
            forKey: SettingsKeys.recurringExtendedThrough
        )
        guard extendedThrough > 0 else { return preferred }
        return max(preferred, Date(timeIntervalSinceReferenceDate: extendedThrough))
    }
}
