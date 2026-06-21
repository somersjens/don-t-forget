import Foundation

struct WeekSection: Identifiable {
    let id: Date
    let startDate: Date
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
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func weekSections(
        startingFrom date: Date = .now,
        numberOfWeeks: Int = 12
    ) -> [WeekSection] {
        guard let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return []
        }

        return (0..<numberOfWeeks).compactMap { weekOffset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: firstWeekStart) else {
                return nil
            }

            let weekNumber = calendar.component(.weekOfYear, from: weekStart)

            let days: [DayInfo] = (0..<7).compactMap { dayOffset in
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                    return nil
                }

                return DayInfo(
                    id: startOfDay(dayDate),
                    date: startOfDay(dayDate),
                    dateLabel: dateLabel(for: dayDate),
                    weekdayLetter: weekdayLetter(for: dayDate)
                )
            }

            return WeekSection(
                id: weekStart,
                startDate: weekStart,
                weekNumber: weekNumber,
                monthTitle: monthTitle(for: weekStart),
                days: days
            )
        }
    }

    static func isSameDay(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    private static func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM"
        return formatter.string(from: date)
    }

    private static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date).capitalized
    }

    private static func weekdayLetter(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)

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
