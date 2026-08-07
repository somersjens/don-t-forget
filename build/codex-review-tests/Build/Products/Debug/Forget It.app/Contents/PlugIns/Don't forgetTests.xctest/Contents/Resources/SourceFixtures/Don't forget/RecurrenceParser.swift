import Foundation

struct ParsedRecurrence {
    let amount: Int
    let component: Calendar.Component
    let displayText: String
}

enum RecurrenceParser {
    static func parse(_ text: String) -> ParsedRecurrence? {
        let clean = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else {
            return nil
        }

        if clean.contains("dagelijks") || clean.contains("elke dag") || clean.contains("iedere dag") || clean.contains("daily") {
            return ParsedRecurrence(amount: 1, component: .day, displayText: "Elke dag")
        }

        if clean.contains("wekelijks") || clean.contains("elke week") || clean.contains("iedere week") || clean.contains("weekly") {
            return ParsedRecurrence(amount: 1, component: .weekOfYear, displayText: "Elke week")
        }

        if clean.contains("maandelijks") || clean.contains("elke maand") || clean.contains("iedere maand") || clean.contains("monthly") {
            return ParsedRecurrence(amount: 1, component: .month, displayText: "Elke maand")
        }

        if clean.contains("jaarlijks") || clean.contains("elk jaar") || clean.contains("ieder jaar") || clean.contains("verjaardag") || clean.contains("yearly") || clean.contains("annually") {
            return ParsedRecurrence(amount: 1, component: .year, displayText: "Elk jaar")
        }

        if let numbered = parseNumberedFrequency(clean) {
            return numbered
        }

        return nil
    }

    static func nextDate(after date: Date, frequencyText: String) -> Date? {
        guard let parsed = parse(frequencyText) else {
            return nil
        }

        return AppCalendar.calendar.date(
            byAdding: parsed.component,
            value: parsed.amount,
            to: AppCalendar.startOfDay(date)
        )
    }

    static func upcomingDates(
        startingAt startDate: Date,
        frequencyText: String,
        until endDate: Date
    ) -> [Date] {
        guard parse(frequencyText) != nil else {
            return []
        }

        var result: [Date] = []
        var currentDate = AppCalendar.startOfDay(startDate)
        let cleanEndDate = AppCalendar.startOfDay(endDate)

        var safetyCounter = 0

        while currentDate <= cleanEndDate && safetyCounter < 300 {
            result.append(currentDate)

            guard let next = nextDate(after: currentDate, frequencyText: frequencyText) else {
                break
            }

            currentDate = next
            safetyCounter += 1
        }

        return result
    }

    static func statusText(for frequencyText: String) -> String {
        guard let parsed = parse(frequencyText) else {
            if frequencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AppCalendar.locale.localized("recurrence.frequency.add")
            }

            return AppCalendar.locale.localized("recurrence.frequency.unrecognized")
        }

        return parsed.displayText
    }

    private static func parseNumberedFrequency(_ text: String) -> ParsedRecurrence? {
        let pattern = #"(?:elke|iedere|om de)?\s*(\d+)\s*(dag|dagen|week|weken|maand|maanden|jaar|jaren)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        guard
            let amountText = group(1, in: match, text),
            let unitText = group(2, in: match, text),
            let amount = Int(amountText)
        else {
            return nil
        }

        switch unitText {
        case "dag", "dagen":
            return ParsedRecurrence(
                amount: amount,
                component: .day,
                displayText: "Elke \(amount) dagen"
            )

        case "week", "weken":
            return ParsedRecurrence(
                amount: amount,
                component: .weekOfYear,
                displayText: "Elke \(amount) weken"
            )

        case "maand", "maanden":
            return ParsedRecurrence(
                amount: amount,
                component: .month,
                displayText: "Elke \(amount) maanden"
            )

        case "jaar", "jaren":
            return ParsedRecurrence(
                amount: amount,
                component: .year,
                displayText: "Elke \(amount) jaren"
            )

        default:
            return nil
        }
    }

    private static func group(_ index: Int, in match: NSTextCheckingResult, _ text: String) -> String? {
        let range = match.range(at: index)

        guard range.location != NSNotFound else {
            return nil
        }

        return (text as NSString).substring(with: range)
    }
}
