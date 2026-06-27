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
    static var calendar: Calendar {
        let defaults = UserDefaults.standard
        let weekStart = WeekStartOption(
            rawValue: defaults.string(forKey: SettingsKeys.weekStart) ?? ""
        ) ?? .monday
        let weekRule = WeekNumberRule(
            rawValue: defaults.string(forKey: SettingsKeys.weekNumberRule) ?? ""
        ) ?? .iso8601
        let language = AppLanguage(
            rawValue: defaults.string(forKey: SettingsKeys.language) ?? ""
        ) ?? .system

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = language.locale
        calendar.firstWeekday = weekStart.calendarWeekday
        calendar.minimumDaysInFirstWeek = weekRule == .iso8601 ? 4 : 1
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func weekSections(
        startingFrom date: Date = .now,
        numberOfWeeks: Int = 12
    ) -> [WeekSection] {
        let configuredCalendar = calendar
        let dateFormatter = DateFormatter()
        dateFormatter.locale = configuredCalendar.locale
        dateFormatter.dateFormat = "dd-MM"
        let monthFormatter = DateFormatter()
        monthFormatter.locale = configuredCalendar.locale
        monthFormatter.dateFormat = "MMMM"
        let weekStartFormatter = DateFormatter()
        weekStartFormatter.locale = configuredCalendar.locale
        weekStartFormatter.dateFormat = "d MMMM"

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
                startDateLabel: weekStartFormatter.string(from: weekStart),
                weekNumber: weekNumber,
                monthTitle: monthFormatter.string(from: weekStart).capitalized,
                days: days
            )
        }
    }

    static func isSameDay(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    private static func weekdayLetter(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)

        let language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.language) ?? ""
        ) ?? .system

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
