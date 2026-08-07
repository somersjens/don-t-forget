import Foundation
import SwiftData

/// Chooses the shared day time zone once, from the data the user already has.
///
/// Every stored day is the midnight of that day in whichever zone the device
/// that wrote it was in, so the rows themselves reveal that zone. Reading it
/// back out — instead of simply taking the current device's zone — means a
/// user who installs this version while travelling does not have their whole
/// agenda shift by a day.
///
/// Runs at most once per device, and the result is mirrored through iCloud, so
/// a second device adopts the same answer rather than deriving its own.
@MainActor
enum DayTimeZonePin {
    /// Enough rows to cover both halves of a daylight saving year without
    /// turning launch into a full table scan.
    private static let sampleLimit = 400

    static func resolveIfNeeded(in container: ModelContainer) {
        guard AppDayTimeZone.storedSecondsFromGMT == nil else { return }

        let context = ModelContext(container)
        var offsets: [Int] = []

        var entryDescriptor = FetchDescriptor<DayEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        entryDescriptor.fetchLimit = sampleLimit
        if let entries = try? context.fetch(entryDescriptor) {
            offsets.append(contentsOf: entries.map { impliedOffset(of: $0.date) })
        }

        var itemDescriptor = FetchDescriptor<RecurringItem>()
        itemDescriptor.fetchLimit = sampleLimit
        if let items = try? context.fetch(itemDescriptor) {
            offsets.append(contentsOf: items.map { impliedOffset(of: $0.nextDate) })
        }

        AppDayTimeZone.pin(secondsFromGMT: resolvedOffset(from: offsets))
    }

    /// The largest observed offset. Within one zone the offsets differ only by
    /// the daylight saving hour, and reading a winter midnight in the summer
    /// offset lands on hour 1 of the same day, while the reverse would land on
    /// hour 23 of the day before.
    static func resolvedOffset(from offsets: [Int]) -> Int {
        offsets.max() ?? TimeZone.current.secondsFromGMT()
    }

    /// The zone offset a stored midnight was written in.
    ///
    /// A day value is `startOfDay - offset` in UTC terms, so the time of day it
    /// lands on in UTC gives the offset back. That leaves the offset ambiguous
    /// by a whole day, which the device's own offset resolves: the two
    /// candidates are 24 hours apart and no device is that far from home.
    static func impliedOffset(
        of storedDay: Date,
        deviceOffset: Int = TimeZone.current.secondsFromGMT()
    ) -> Int {
        let day = 24 * 3600
        let secondsIntoUTCDay = Int(storedDay.timeIntervalSince1970.rounded())
            .modulo(day)
        let candidate = (day - secondsIntoUTCDay).modulo(day)
        let alternative = candidate - day
        return abs(candidate - deviceOffset) <= abs(alternative - deviceOffset)
            ? candidate
            : alternative
    }
}

private extension Int {
    /// Swift's `%` keeps the sign of the dividend; day arithmetic needs the
    /// non-negative remainder.
    func modulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}
