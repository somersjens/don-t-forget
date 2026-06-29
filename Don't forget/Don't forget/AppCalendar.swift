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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = locale
        calendar.firstWeekday = weekStart.calendarWeekday
        calendar.minimumDaysInFirstWeek = weekRule == .iso8601 ? 4 : 1
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static var monthSymbols: [String] {
        if language == .dutch {
            return [
                "januari", "februari", "maart", "april", "mei", "juni",
                "juli", "augustus", "september", "oktober", "november", "december"
            ]
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter.monthSymbols
    }

    static func monthName(_ month: Int) -> String {
        let symbols = monthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }

    static func localizedDate(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func localizedLongDate(_ date: Date, includeYear: Bool) -> String {
        if language == .dutch {
            let components = calendar.dateComponents([.day, .month, .year], from: date)
            let base = "\(components.day ?? 0) \(monthName(components.month ?? 1))"
            return includeYear ? "\(base) \(components.year ?? 0)" : base
        }

        return localizedDate(date, template: includeYear ? "dMMMMyyyy" : "dMMMM")
    }

    static func weekSections(
        startingFrom date: Date = .now,
        numberOfWeeks: Int = 12
    ) -> [WeekSection] {
        let configuredCalendar = calendar
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateFormat = "dd-MM"

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

        let language = AppLanguage.effective(
            from: UserDefaults.standard.string(forKey: SettingsKeys.language),
            holidayCountryCode: UserDefaults.standard.string(forKey: SettingsKeys.recurringHolidayCountry)
        )

        if language == .english {
            switch weekday {
            case 2: return "M"
            case 3: return "T"
            case 4: return "W"
            case 5: return "T"
            case 6: return "F"
            case 7: return "S"
            default: return "S"
            }
        }

        switch weekday {
        case 2: return "M"
        case 3: return "D"
        case 4: return "W"
        case 5: return "D"
        case 6: return "V"
        case 7: return "Z"
        default: return "Z"
        }
    }
}
