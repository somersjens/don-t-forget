import Foundation

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

    static var calendar: Calendar {
        let defaults = UserDefaults.standard
        let weekStart = WeekStartOption(
            rawValue: defaults.string(forKey: SettingsKeys.weekStart) ?? ""
        ) ?? .monday
        let weekRule = WeekNumberRule(
            rawValue: defaults.string(forKey: SettingsKeys.weekNumberRule) ?? ""
        ) ?? .iso8601
        let locale = locale
        let timeZone = TimeZone.current
        let cacheKey = [
            "AppCalendar.calendar",
            locale.identifier,
            timeZone.identifier,
            String(weekStart.calendarWeekday),
            weekRule.rawValue
        ].joined(separator: "|")
        if let cached = Thread.current.threadDictionary[cacheKey] as? Calendar {
            return cached
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = weekStart.calendarWeekday
        calendar.minimumDaysInFirstWeek = weekRule == .iso8601 ? 4 : 1
        Thread.current.threadDictionary[cacheKey] = calendar
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
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

    static func localizedLongDate(_ date: Date, includeYear: Bool) -> String {
        return localizedDate(date, template: includeYear ? "dMMMMyyyy" : "dMMMM")
    }

    static func weekSections(
        startingFrom date: Date = .now,
        numberOfWeeks: Int = 12
    ) -> [WeekSection] {
        let configuredCalendar = calendar
        let dateFormatter = cachedFormatter(dateFormat: "dd-MM")

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

                return DayInfo(
                    id: normalizedDate,
                    date: normalizedDate,
                    dateLabel: dateFormatter.string(from: dayDate),
                    weekdayLetter: weekdayLetter(
                        for: dayDate,
                        calendar: configuredCalendar
                    )
                )
            }

            return WeekSection(
                id: weekStart,
                startDate: weekStart,
                startDateLabel: localizedLongDate(weekStart, includeYear: false),
                weekNumber: weekNumber,
                monthTitle: monthName(configuredCalendar.component(.month, from: weekStart)),
                days: days
            )
        }
    }

    static func isSameDay(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    private static func weekdayLetter(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)

        let symbols = cachedFormatter(template: "EEEEE").veryShortWeekdaySymbols ?? []
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols.indices.contains(index) ? symbols[index] : ""
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
