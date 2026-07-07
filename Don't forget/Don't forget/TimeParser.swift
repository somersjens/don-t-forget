import Foundation

struct ParsedEntryTime {
    let startMinutes: Int?
    let endMinutes: Int?
    let isUncertain: Bool
}

enum TimeParser {
    static func parse(_ text: String, locale: Locale = AppCalendar.locale) -> ParsedEntryTime {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUncertain = trimmed.hasSuffix("?")

        if let dayPeriodTime = parseDayPeriodTime(in: text, locale: locale) {
            return ParsedEntryTime(
                startMinutes: dayPeriodTime.start,
                endMinutes: dayPeriodTime.end,
                isUncertain: isUncertain
            )
        }

        if let rangeMatch = firstMatch(rangePattern, in: text) {
            let startHour = group(1, in: rangeMatch, text)
            let startMinuteA = group(2, in: rangeMatch, text)
            let startMinuteB = group(3, in: rangeMatch, text)

            let endHour = group(4, in: rangeMatch, text)
            let endMinuteA = group(5, in: rangeMatch, text)
            let endMinuteB = group(6, in: rangeMatch, text)

            return ParsedEntryTime(
                startMinutes: minutes(hour: startHour, minuteA: startMinuteA, minuteB: startMinuteB),
                endMinutes: minutes(hour: endHour, minuteA: endMinuteA, minuteB: endMinuteB),
                isUncertain: isUncertain
            )
        }

        if let singleMatch = firstMatch(singlePattern, in: text) {
            let hour = group(1, in: singleMatch, text)
            let minuteA = group(2, in: singleMatch, text)
            let minuteB = group(3, in: singleMatch, text)

            return ParsedEntryTime(
                startMinutes: minutes(hour: hour, minuteA: minuteA, minuteB: minuteB),
                endMinutes: nil,
                isUncertain: isUncertain
            )
        }

        return ParsedEntryTime(
            startMinutes: nil,
            endMinutes: nil,
            isUncertain: isUncertain
        )
    }

    static func timeLabel(_ startMinutes: Int, end endMinutes: Int?) -> String {
        let start = label(for: startMinutes)

        guard let endMinutes else {
            return start
        }

        return "\(start)–\(label(for: endMinutes))"
    }

    private static func label(for minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private static let rangePattern =
    #"(?<!\d)([01]?\d|2[0-3])(?:(?::|\.)([0-5]\d)|u(?:([0-5]\d))?)?\s*[-–]\s*([01]?\d|2[0-3])(?:(?::|\.)([0-5]\d)|u(?:([0-5]\d))?)?u?\??(?!\d)"#

    private static let singlePattern =
    #"(?<!\d)([01]?\d|2[0-3])(?:(?::|\.)([0-5]\d)|u(?:([0-5]\d))?)(?:\?)?(?!\d)"#

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range)
    }

    private static func group(_ index: Int, in match: NSTextCheckingResult, _ text: String) -> String? {
        let range = match.range(at: index)

        guard range.location != NSNotFound else {
            return nil
        }

        return (text as NSString).substring(with: range)
    }

    private static func minutes(hour: String?, minuteA: String?, minuteB: String?) -> Int? {
        guard let hour, let hourInt = Int(hour) else {
            return nil
        }

        let minuteText = minuteA ?? minuteB ?? "0"
        let minuteInt = Int(minuteText) ?? 0

        return hourInt * 60 + minuteInt
    }

    /// Recognizes both the locale's day-period symbols and the widely used
    /// AM/PM spellings. Locale symbols may occur before or after the time
    /// (for example `4 PM` and `下午4:00`).
    private static func parseDayPeriodTime(
        in text: String,
        locale: Locale
    ) -> (start: Int, end: Int?)? {
        let formatter = DateFormatter()
        formatter.locale = locale

        var periods: [(symbol: String, isPM: Bool)] = [
            ("am", false), ("a.m.", false),
            ("pm", true), ("p.m.", true),
            (formatter.amSymbol, false), (formatter.pmSymbol, true)
        ]
        var seen = Set<String>()
        periods = periods.filter {
            let normalized = $0.symbol
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            return !normalized.isEmpty && seen.insert(normalized).inserted
        }

        var candidates: [(range: NSRange, minutes: Int)] = []
        for period in periods {
            let symbol = NSRegularExpression.escapedPattern(for: period.symbol)
            let hourAndMinute = #"(1[0-2]|0?[1-9])(?:(?::|\.)([0-5]\d))?"#
            let patterns = [
                "(?<!\\d)\(hourAndMinute)\\s*\(symbol)(?!\\p{L})",
                "(?<!\\p{L})\(symbol)\\s*\(hourAndMinute)(?!\\d)"
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ) else { continue }

                let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
                for match in regex.matches(in: text, range: fullRange) {
                    guard let hour = localizedInteger(group(1, in: match, text), locale: locale) else {
                        continue
                    }
                    let minute = localizedInteger(group(2, in: match, text), locale: locale) ?? 0
                    let normalizedHour = (hour % 12) + (period.isPM ? 12 : 0)
                    candidates.append((match.range, normalizedHour * 60 + minute))
                }
            }
        }

        candidates.sort { $0.range.location < $1.range.location }
        guard let first = candidates.first else { return nil }

        let second = candidates.dropFirst().first { candidate in
            guard candidate.range.location >= NSMaxRange(first.range) else { return false }
            let separatorRange = NSRange(
                location: NSMaxRange(first.range),
                length: candidate.range.location - NSMaxRange(first.range)
            )
            let separator = (text as NSString).substring(with: separatorRange)
            return separator.range(of: #"^\s*[-–]\s*$"#, options: .regularExpression) != nil
        }
        return (first.minutes, second?.minutes)
    }

    private static func localizedInteger(_ value: String?, locale: Locale) -> Int? {
        guard let value else { return nil }
        if let integer = Int(value) { return integer }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.number(from: value)?.intValue
    }
}
