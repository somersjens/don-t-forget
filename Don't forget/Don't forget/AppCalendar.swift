import Foundation
import SwiftUI

extension View {
    /// Puts the shared day zone into the environment, so a `DatePicker` shows
    /// and produces the same calendar day the stored value means — on a device
    /// in another time zone too.
    func appDayTimeZone() -> some View {
        environment(\.calendar, AppCalendar.calendar)
            .environment(\.timeZone, AppDayTimeZone.current)
    }
}

/// The time zone every stored calendar *day* is expressed in.
///
/// `DayEntry.date`, `RecurringItem.nextDate` and the generated occurrence keys
/// are day values, but they are stored as absolute instants. Reading such an
/// instant with the device's own time zone yields a different calendar day
/// abroad than at home, so an iPhone that had travelled produced different
/// occurrence keys — and different midnights — than the Mac at home. The two
/// then deleted and recreated each other's occurrences on every sync. No
/// single instant maps to the same calendar day in every zone, so the reading
/// side is what has to be shared.
///
/// The zone is derived from the data the user already has (see
/// `DayTimeZonePin`), which keeps every existing day on the label it has
/// today, and it is mirrored through iCloud so a second device adopts it
/// instead of choosing its own. It carries no daylight saving rules on
/// purpose: uniform 24-hour days keep recurrence arithmetic from drifting an
/// hour across a transition.
nonisolated enum AppDayTimeZone {
    static var current: TimeZone {
        guard let seconds = storedSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: seconds) else {
            return TimeZone.current
        }
        return timeZone
    }

    static var storedSecondsFromGMT: Int? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKeys.dayTimeZoneSeconds) != nil else { return nil }
        return defaults.integer(forKey: SettingsKeys.dayTimeZoneSeconds)
    }

    static func pin(secondsFromGMT: Int) {
        UserDefaults.standard.set(secondsFromGMT, forKey: SettingsKeys.dayTimeZoneSeconds)
    }
}

/// Day arithmetic, in the shared day time zone.
///
/// Deliberately reachable off the main actor: the private-context recurrence
/// workers compare and normalise stored days too, and they used
/// `Calendar.current` for it, which reintroduced the device's own zone.
nonisolated enum AppDayCalendar {
    static var calendar: Calendar {
        let defaults = UserDefaults.standard
        let weekStart = WeekStartOption(
            rawValue: defaults.string(forKey: SettingsKeys.weekStart) ?? ""
        ) ?? .monday
        let weekRule = WeekNumberRule(
            rawValue: defaults.string(forKey: SettingsKeys.weekNumberRule) ?? ""
        ) ?? .iso8601
        let timeZone = AppDayTimeZone.current
        let cacheKey = [
            "AppDayCalendar.calendar",
            timeZone.identifier,
            String(weekStart.calendarWeekday),
            weekRule.rawValue
        ].joined(separator: "|")
        if let cached = Thread.current.threadDictionary[cacheKey] as? Calendar {
            return cached
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = weekStart.calendarWeekday
        calendar.minimumDaysInFirstWeek = weekRule == .iso8601 ? 4 : 1
        Thread.current.threadDictionary[cacheKey] = calendar
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The stored day value for the calendar day it is *right now on this
    /// device*. The user's own clock decides which day it is; the shared zone
    /// decides how that day is written down.
    static var today: Date {
        day(containing: .now)
    }

    /// The stored day value for the calendar day `instant` falls on locally.
    /// Use this for real instants — "now", `createdAt`, a picked date — never
    /// for a value that already is a stored day.
    static func day(containing instant: Date) -> Date {
        let components = localCalendar.dateComponents([.year, .month, .day], from: instant)
        return calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day
        )) ?? startOfDay(instant)
    }

    /// The instant a stored day starts at on *this* device. Only for things
    /// that must happen at a local wall-clock moment, such as a calendar event
    /// or a notification.
    static func localStartOfDay(for storedDay: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: storedDay)
        return localCalendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day
        )) ?? storedDay
    }

    /// Cached per thread like the day calendar: `today` is read from view
    /// bodies and row builders, so this must not allocate a `Calendar` on
    /// every call.
    private static var localCalendar: Calendar {
        let timeZone = TimeZone.current
        let cacheKey = "AppDayCalendar.localCalendar|" + timeZone.identifier
        if let cached = Thread.current.threadDictionary[cacheKey] as? Calendar {
            return cached
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        Thread.current.threadDictionary[cacheKey] = calendar
        return calendar
    }
}

struct WeekSection: Identifiable {
    let id: Date
    let startDate: Date
    let startDateLabel: String
    let weekNumber: Int
    let monthTitle: String
    let days: [DayInfo]
}

struct DayInfo: Identifiable {
    let id: Date
    let date: Date
    let dateLabel: String
    let weekdayLetter: String
}

enum AppCalendar {
    static var language: AppLanguage {
        AppLanguage.effective(
            from: UserDefaults.standard.string(forKey: SettingsKeys.language),
            holidayCountryCode: UserDefaults.standard.string(forKey: SettingsKeys.recurringHolidayCountry)
        )
    }

    static var locale: Locale {
        return language.locale
    }

    /// The day calendar plus the display locale. Day arithmetic is identical
    /// to `AppDayCalendar.calendar`; the locale only affects symbols.
    static var calendar: Calendar {
        let locale = locale
        var calendar = AppDayCalendar.calendar
        let cacheKey = [
            "AppCalendar.calendar",
            locale.identifier,
            calendar.timeZone.identifier,
            String(calendar.firstWeekday),
            String(calendar.minimumDaysInFirstWeek)
        ].joined(separator: "|")
        if let cached = Thread.current.threadDictionary[cacheKey] as? Calendar {
            return cached
        }

        calendar.locale = locale
        Thread.current.threadDictionary[cacheKey] = calendar
        return calendar
    }

    static var dateFormatOption: DateFormatOption {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.dateFormat)
        let selected = DateFormatOption.resolved(from: stored)
        guard selected != .system else {
            return DateFormatOption.localeDefault(for: locale)
        }
        return selected
    }

    static var weekdayLabelLength: Int {
        WeekdayLabelLengthOption.resolved(
            storedValue: UserDefaults.standard.integer(forKey: SettingsKeys.weekdayLabelLength),
            locale: locale
        )
    }

    /// Normalises a value that already *is* a stored day.
    static func startOfDay(_ date: Date) -> Date {
        AppDayCalendar.startOfDay(date)
    }

    /// The stored day for the calendar day it is right now on this device.
    ///
    /// Use this rather than `startOfDay(.now)`: `.now` is a real instant, and
    /// normalising it in the shared day zone would name the day it is at home
    /// while the user is travelling.
    static var today: Date {
        AppDayCalendar.today
    }

    /// The stored day for the calendar day `instant` falls on locally.
    static func day(containing instant: Date) -> Date {
        AppDayCalendar.day(containing: instant)
    }

    static var monthSymbols: [String] {
        return cachedFormatter(template: "MMMM").monthSymbols
    }

    static func monthName(_ month: Int) -> String {
        let symbols = monthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }

    static func localizedDate(_ date: Date, template: String) -> String {
        cachedFormatter(template: template).string(from: date)
    }

    static func localizedShortDayMonth(_ date: Date) -> String {
        if let dateFormat = dateFormatOption.dateFormat {
            return cachedFormatter(dateFormat: dateFormat).string(from: date)
        }
        return cachedFormatter(dateFormat: "dd/MM").string(from: date)
    }

    static func localizedLongDate(_ date: Date, includeYear: Bool) -> String {
        return localizedDate(date, template: includeYear ? "dMMMMyyyy" : "dMMMM")
    }

    static func weekSections(
        startingFrom date: Date = .now,
        numberOfWeeks: Int = 12
    ) -> [WeekSection] {
        let configuredCalendar = calendar
        let configuredDateFormat = dateFormatOption.dateFormat ?? "dd/MM"
        let dateFormatter = cachedFormatter(dateFormat: configuredDateFormat)
        let longDateFormatter = cachedFormatter(template: "dMMMM")
        let weekdaySymbols = cachedFormatter(template: "EEEE").weekdaySymbols ?? []
        let configuredWeekdayLabelLength = weekdayLabelLength
        let configuredMonthSymbols = cachedFormatter(template: "MMMM").monthSymbols ?? []

        guard let firstWeekStart = configuredCalendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return []
        }

        return (0..<numberOfWeeks).compactMap { weekOffset in
            guard let weekStart = configuredCalendar.date(
                byAdding: .weekOfYear,
                value: weekOffset,
                to: firstWeekStart
            ) else {
                return nil
            }

            let weekNumber = configuredCalendar.component(.weekOfYear, from: weekStart)

            let days: [DayInfo] = (0..<7).compactMap { dayOffset in
                guard let dayDate = configuredCalendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: weekStart
                ) else {
                    return nil
                }
                let normalizedDate = configuredCalendar.startOfDay(for: dayDate)
                let weekday = configuredCalendar.component(.weekday, from: dayDate)
                let weekdayIndex = weekday - 1
                let weekdayName = weekdaySymbols.indices.contains(weekdayIndex)
                    ? weekdaySymbols[weekdayIndex]
                    : ""

                return DayInfo(
                    id: normalizedDate,
                    date: normalizedDate,
                    dateLabel: dateFormatter.string(from: dayDate),
                    weekdayLetter: String(weekdayName.prefix(configuredWeekdayLabelLength))
                        .localizedCapitalized
                )
            }

            let month = configuredCalendar.component(.month, from: weekStart)
            let monthIndex = month - 1

            return WeekSection(
                id: weekStart,
                startDate: weekStart,
                startDateLabel: longDateFormatter.string(from: weekStart),
                weekNumber: weekNumber,
                monthTitle: configuredMonthSymbols.indices.contains(monthIndex)
                    ? configuredMonthSymbols[monthIndex]
                    : "",
                days: days
            )
        }
    }

    static func isSameDay(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    private static func weekdayLetter(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)

        let symbols = cachedFormatter(template: "EEEE").weekdaySymbols ?? []
        let index = max(0, min(symbols.count - 1, weekday - 1))
        guard symbols.indices.contains(index) else { return "" }
        return String(symbols[index].prefix(weekdayLabelLength)).localizedCapitalized
    }

    private static func cachedFormatter(template: String) -> DateFormatter {
        cachedFormatter(cacheComponent: "template:\(template)") { formatter in
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
    }

    private static func cachedFormatter(dateFormat: String) -> DateFormatter {
        cachedFormatter(cacheComponent: "format:\(dateFormat)") { formatter in
            formatter.dateFormat = dateFormat
        }
    }

    private static func cachedFormatter(
        cacheComponent: String,
        configure: (DateFormatter) -> Void
    ) -> DateFormatter {
        let configuredCalendar = calendar
        let configuredLocale = locale
        let cacheKey = [
            "AppCalendar.formatter",
            configuredLocale.identifier,
            configuredCalendar.timeZone.identifier,
            String(configuredCalendar.firstWeekday),
            String(configuredCalendar.minimumDaysInFirstWeek),
            UserDefaults.standard.string(forKey: SettingsKeys.dateFormat)
                ?? DateFormatOption.system.rawValue,
            cacheComponent
        ].joined(separator: "|")

        if let formatter = Thread.current.threadDictionary[cacheKey] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = configuredLocale
        formatter.calendar = configuredCalendar
        configure(formatter)
        Thread.current.threadDictionary[cacheKey] = formatter
        return formatter
    }
}
