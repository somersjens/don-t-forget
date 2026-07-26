import Foundation

enum HolidayCountry: String, CaseIterable, Identifiable {
    case netherlands = "NL"
    case belgium = "BE"
    case germany = "DE"
    case france = "FR"
    case unitedKingdom = "GB"
    case unitedStates = "US"
    case morocco = "MA"
    case suriname = "SR"
    case turkey = "TR"

    var id: String { rawValue }

    var title: String { title(for: AppCalendar.locale) }

    func title(for locale: Locale) -> String {
        locale.localizedCatalogKey("country.\(rawValue)", defaultValue: rawValue)
    }

    static var localeDefault: HolidayCountry {
        let region = Locale.current.region?.identifier ?? "NL"
        return HolidayCountry(rawValue: region) ?? .netherlands
    }
}

struct HolidayDefinition: Identifiable, Hashable {
    enum Rule: Hashable {
        case fixed(month: Int, day: Int)
        case easter(offset: Int)
        case weekday(month: Int, weekday: Int, ordinal: Int)
        case islamic(month: Int, day: Int)
    }

    let id: String
    let rule: Rule

    var title: String {
        AppCalendar.locale.localizedCatalogKey("holiday.\(id)", defaultValue: id)
    }

    var recurrenceDescription: String {
        recurrenceDescription(onOrAfter: .now)
    }

    func recurrenceDescription(onOrAfter referenceDate: Date) -> String {
        let locale = AppCalendar.locale
        switch rule {
        case let .fixed(month, day):
            let date = AppCalendar.calendar.date(from: DateComponents(year: 2026, month: month, day: day))
            let dateText = date.map { AppCalendar.localizedLongDate($0, includeYear: false) }
                ?? "\(day) \(AppCalendar.monthName(month))"
            return dateText
        case let .weekday(month, weekday, ordinal):
            let description = locale.localizedFormat(
                "recurrence.ordinalWeekdayOfNamedMonth",
                Self.ordinalName(ordinal).capitalized,
                Self.weekdayName(weekday),
                AppCalendar.monthName(month)
            )
            return "\(nextDateText(onOrAfter: referenceDate)) · \(description)"
        case .easter:
            return "\(nextDateText(onOrAfter: referenceDate)) · \(locale.localized("Rond Pasen"))"
        case .islamic:
            return "\(nextDateText(onOrAfter: referenceDate)) · \(locale.localized("Islamitische kalender"))"
        }
    }

    private func nextDateText(onOrAfter referenceDate: Date) -> String {
        let date = HolidayCatalog.nextDate(for: self, after: referenceDate)
        return AppCalendar.localizedLongDate(date, includeYear: true)
    }

    private static func ordinalName(_ ordinal: Int) -> String {
        let key = switch ordinal {
        case 1: "ordinal.first"
        case 2: "ordinal.second"
        case 3: "ordinal.third"
        case 4: "ordinal.fourth"
        default: "ordinal.last"
        }
        return AppCalendar.locale.localized(key)
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppCalendar.locale
        let symbols = formatter.weekdaySymbols ?? []
        let names = [""] + symbols
        return names.indices.contains(weekday) ? names[weekday] : names[1]
    }

}

struct HolidayOption: Identifiable {
    let country: HolidayCountry
    let definition: HolidayDefinition

    var id: String { "\(country.rawValue):\(definition.id)" }
}

enum HolidayCatalog {
    static let markerPrefix = "[app-feestdag:"

    static func holidays(for country: HolidayCountry) -> [HolidayDefinition] {
        switch country {
        case .netherlands:
            return netherlands
        case .belgium:
            return belgium
        case .germany:
            return commonChristian + [
                fixed("unity-day", 10, 3)
            ]
        case .france:
            return [
                fixed("new-year", 1, 1),
                easter("easter-monday", 1),
                fixed("labour-day", 5, 1),
                fixed("victory-day", 5, 8),
                easter("ascension", 39),
                easter("whit-monday", 50),
                fixed("bastille-day", 7, 14),
                fixed("assumption", 8, 15),
                fixed("all-saints", 11, 1),
                fixed("armistice", 11, 11),
                fixed("christmas", 12, 25)
            ]
        case .unitedKingdom:
            return [
                fixed("new-year", 1, 1),
                easter("good-friday", -2),
                easter("easter-monday", 1),
                weekday("early-may", 5, 2, 1),
                weekday("spring-bank", 5, 2, 5),
                weekday("summer-bank", 8, 2, 5),
                fixed("christmas", 12, 25),
                fixed("boxing-day", 12, 26)
            ]
        case .unitedStates:
            return [
                fixed("new-year", 1, 1),
                weekday("mlk-day", 1, 2, 3),
                weekday("presidents-day", 2, 2, 3),
                weekday("memorial-day", 5, 2, 5),
                fixed("juneteenth", 6, 19),
                fixed("independence-day", 7, 4),
                weekday("labor-day", 9, 2, 1),
                weekday("columbus-day", 10, 2, 2),
                fixed("veterans-day", 11, 11),
                weekday("thanksgiving", 11, 5, 4),
                fixed("christmas", 12, 25)
            ]
        case .morocco:
            return islamicObservances + [
                islamic("mawlid", 3, 12),
                fixed("new-year", 1, 1),
                fixed("independence-manifesto", 1, 11),
                fixed("amazigh-new-year", 1, 14),
                fixed("labour-day", 5, 1),
                fixed("throne-day", 7, 30),
                fixed("oued-eddahab-day", 8, 14),
                fixed("revolution-day-ma", 8, 20),
                fixed("youth-day-ma", 8, 21),
                fixed("unity-day-ma", 10, 31),
                fixed("green-march", 11, 6),
                fixed("morocco-independence", 11, 18)
            ]
        case .suriname:
            return [
                fixed("new-year", 1, 1),
                easter("good-friday", -2),
                easter("easter-monday", 1),
                fixed("labour-day", 5, 1),
                fixed("keti-koti", 7, 1),
                fixed("indigenous-day", 8, 9),
                fixed("maroons-day", 10, 10),
                fixed("suriname-independence", 11, 25),
                fixed("christmas", 12, 25),
                fixed("boxing-day", 12, 26)
            ] + islamicObservances
        case .turkey:
            return islamicObservances + [
                fixed("new-year", 1, 1),
                fixed("children-day", 4, 23),
                fixed("labour-solidarity-day", 5, 1),
                fixed("youth-day", 5, 19),
                fixed("democracy-day", 7, 15),
                fixed("victory-day-tr", 8, 30),
                fixed("republic-day", 10, 29)
            ]
        }
    }

    static func options(for country: HolidayCountry, onlyLocal: Bool) -> [HolidayOption] {
        if onlyLocal {
            return holidays(for: country).map { HolidayOption(country: country, definition: $0) }
        }

        let all = HolidayCountry.allCases.flatMap { sourceCountry in
            holidays(for: sourceCountry).map { HolidayOption(country: sourceCountry, definition: $0) }
        }
        let grouped = Dictionary(grouping: all, by: { $0.definition.id })
        return grouped.values.compactMap { group in
            let preferred = primaryCountry(for: group[0].definition.id)
            return group.first(where: { $0.country == preferred }) ?? group.first
        }.sorted { lhs, rhs in
            lhs.definition.title.localizedCaseInsensitiveCompare(rhs.definition.title) == .orderedAscending
        }
    }

    static func defaultSelectionIDs(
        for country: HolidayCountry,
        onlyLocal: Bool = true
    ) -> Set<String> {
        let officialIDs: Set<String> = switch country {
        case .netherlands:
            [
                "new-year", "good-friday", "easter-sunday", "easter-monday",
                "kings-day", "liberation-day", "ascension", "whit-sunday",
                "whit-monday", "christmas", "boxing-day"
            ]
        case .belgium:
            [
                "new-year", "easter-monday", "labour-day", "ascension",
                "whit-monday", "national-day", "assumption", "all-saints",
                "armistice", "christmas"
            ]
        case .germany:
            [
                "new-year", "good-friday", "easter-monday", "labour-day",
                "ascension", "whit-monday", "unity-day", "christmas", "boxing-day"
            ]
        case .france:
            [
                "new-year", "easter-monday", "labour-day", "victory-day",
                "ascension", "whit-monday", "bastille-day", "assumption",
                "all-saints", "armistice", "christmas"
            ]
        case .unitedKingdom:
            [
                "new-year", "good-friday", "easter-monday", "early-may",
                "spring-bank", "summer-bank", "christmas", "boxing-day"
            ]
        case .unitedStates:
            [
                "new-year", "mlk-day", "presidents-day", "memorial-day",
                "juneteenth", "independence-day", "labor-day", "columbus-day",
                "veterans-day", "thanksgiving", "christmas"
            ]
        case .morocco:
            [
                "eid-al-fitr", "islamic-new-year", "eid-al-adha", "mawlid",
                "new-year", "independence-manifesto", "amazigh-new-year",
                "labour-day", "throne-day", "oued-eddahab-day",
                "revolution-day-ma", "youth-day-ma", "unity-day-ma",
                "green-march", "morocco-independence"
            ]
        case .suriname:
            [
                "new-year", "good-friday", "easter-monday", "labour-day",
                "keti-koti", "indigenous-day", "maroons-day",
                "suriname-independence", "christmas", "boxing-day",
                "eid-al-fitr", "eid-al-adha"
            ]
        case .turkey:
            [
                "new-year", "eid-al-fitr", "eid-al-adha", "children-day",
                "labour-solidarity-day", "youth-day", "democracy-day", "victory-day-tr",
                "republic-day"
            ]
        }

        assert(
            officialIDs.isSubset(of: Set(holidays(for: country).map(\.id))),
            "Official holiday selection contains an unknown ID for \(country.rawValue)"
        )

        return Set(options(for: country, onlyLocal: onlyLocal)
            .filter { officialIDs.contains($0.definition.id) }
            .map(\.id))
    }

    static func marker(country: HolidayCountry, holidayID: String) -> String {
        "\(markerPrefix)\(country.rawValue):\(holidayID)]"
    }

    static func managedHoliday(from notes: String) -> (country: HolidayCountry, definition: HolidayDefinition)? {
        guard notes.hasPrefix(markerPrefix), let end = notes.firstIndex(of: "]") else { return nil }
        let value = notes[notes.index(notes.startIndex, offsetBy: markerPrefix.count)..<end]
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let country = HolidayCountry(rawValue: parts[0]),
              let definition = holidays(for: country).first(where: { $0.id == parts[1] }) else { return nil }
        return (country, definition)
    }

    static func dates(for definition: HolidayDefinition, from start: Date, through end: Date) -> [Date] {
        let start = AppCalendar.startOfDay(start)
        let end = AppCalendar.startOfDay(end)
        guard start <= end else { return [] }

        if case let .islamic(month, day) = definition.rule {
            var islamic = Calendar(identifier: .islamicUmmAlQura)
            islamic.timeZone = AppCalendar.calendar.timeZone
            var current = start
            var result: [Date] = []
            while current <= end {
                if islamic.component(.month, from: current) == month,
                   islamic.component(.day, from: current) == day {
                    result.append(current)
                }
                guard let next = AppCalendar.calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            return result
        }

        let calendar = AppCalendar.calendar
        let firstYear = calendar.component(.year, from: start)
        let lastYear = calendar.component(.year, from: end)
        return (firstYear...lastYear).compactMap { date(for: definition.rule, year: $0) }
            .filter { $0 >= start && $0 <= end }
    }

    static func nextDate(for definition: HolidayDefinition, after referenceDate: Date = .now) -> Date {
        let end = AppCalendar.calendar.date(byAdding: .year, value: 3, to: referenceDate) ?? referenceDate
        return dates(for: definition, from: referenceDate, through: end).first
            ?? AppCalendar.startOfDay(referenceDate)
    }

    private static let netherlands: [HolidayDefinition] = [
        fixed("new-year", 1, 1),
        easter("good-friday", -2),
        easter("easter-sunday", 0),
        easter("easter-monday", 1),
        fixed("kings-day", 4, 27),
        fixed("remembrance-day", 5, 4),
        fixed("liberation-day", 5, 5),
        weekday("mothers-day", 5, 1, 2),
        easter("ascension", 39),
        easter("whit-sunday", 49),
        easter("whit-monday", 50),
        weekday("fathers-day", 6, 1, 3),
        fixed("keti-koti", 7, 1),
        weekday("prinsjesdag", 9, 3, 3),
        fixed("sinterklaas", 12, 5),
        fixed("christmas", 12, 25),
        fixed("boxing-day", 12, 26)
    ] + islamicObservances

    private static let belgium: [HolidayDefinition] = [
        fixed("new-year", 1, 1),
        easter("easter-monday", 1),
        fixed("labour-day", 5, 1),
        easter("ascension", 39),
        easter("whit-monday", 50),
        fixed("flemish-community", 7, 11),
        fixed("national-day", 7, 21),
        fixed("assumption", 8, 15),
        fixed("french-community", 9, 27),
        fixed("all-saints", 11, 1),
        fixed("armistice", 11, 11),
        fixed("german-community", 11, 15),
        fixed("christmas", 12, 25)
    ] + islamicObservances

    private static let commonChristian: [HolidayDefinition] = [
        fixed("new-year", 1, 1),
        easter("good-friday", -2),
        easter("easter-monday", 1),
        fixed("labour-day", 5, 1),
        easter("ascension", 39),
        easter("whit-monday", 50),
        fixed("christmas", 12, 25),
        fixed("boxing-day", 12, 26)
    ]

    private static let islamicObservances: [HolidayDefinition] = [
        islamic("ramadan-start", 9, 1),
        islamic("eid-al-fitr", 10, 1),
        islamic("eid-al-adha", 12, 10),
        islamic("islamic-new-year", 1, 1)
    ]

    private static func fixed(_ id: String, _ month: Int, _ day: Int) -> HolidayDefinition {
        .init(id: id, rule: .fixed(month: month, day: day))
    }

    private static func easter(_ id: String, _ offset: Int) -> HolidayDefinition {
        .init(id: id, rule: .easter(offset: offset))
    }

    private static func weekday(_ id: String, _ month: Int, _ weekday: Int, _ ordinal: Int) -> HolidayDefinition {
        .init(id: id, rule: .weekday(month: month, weekday: weekday, ordinal: ordinal))
    }

    private static func islamic(_ id: String, _ month: Int, _ day: Int) -> HolidayDefinition {
        .init(id: id, rule: .islamic(month: month, day: day))
    }

    private static func primaryCountry(for holidayID: String) -> HolidayCountry? {
        switch holidayID {
        case "keti-koti": .suriname
        case "ramadan-start", "eid-al-fitr", "eid-al-adha", "islamic-new-year": .morocco
        default: nil
        }
    }

    private static func date(for rule: HolidayDefinition.Rule, year: Int) -> Date? {
        let calendar = AppCalendar.calendar
        switch rule {
        case let .fixed(month, day):
            return calendar.date(from: DateComponents(year: year, month: month, day: day)).map { AppCalendar.startOfDay($0) }
        case let .easter(offset):
            guard let easter = easterSunday(year: year) else { return nil }
            return calendar.date(byAdding: .day, value: offset, to: easter).map { AppCalendar.startOfDay($0) }
        case let .weekday(month, weekday, ordinal):
            guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            let firstWeekday = calendar.component(.weekday, from: monthStart)
            let baseOffset = (weekday - firstWeekday + 7) % 7
            let dayOffset: Int
            if ordinal == 5 {
                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                      let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return nil }
                let lastWeekday = calendar.component(.weekday, from: lastDay)
                dayOffset = calendar.component(.day, from: lastDay) - 1 - (lastWeekday - weekday + 7) % 7
            } else {
                dayOffset = baseOffset + (ordinal - 1) * 7
            }
            return calendar.date(byAdding: .day, value: dayOffset, to: monthStart).map { AppCalendar.startOfDay($0) }
        case .islamic:
            return nil
        }
    }

    private static func easterSunday(year: Int) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return AppCalendar.calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
