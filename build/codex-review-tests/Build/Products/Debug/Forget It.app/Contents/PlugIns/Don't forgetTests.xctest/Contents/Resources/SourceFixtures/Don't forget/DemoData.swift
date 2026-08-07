import Foundation
import SwiftData

enum DemoData {
    static let historyMarker = "Demo afgerond"
    private static let legacyHistoryMarker = "Demo geschiedenis"

    static func isHistoryDemoText(_ text: String) -> Bool {
        text.hasPrefix(historyMarker) || text.hasPrefix(legacyHistoryMarker)
    }

    @MainActor
    static func insertScreenshotData(in modelContext: ModelContext) {
        if demoAlreadyExists(in: modelContext) {
            return
        }

        let agendaItems: [(date: Date, text: String)] = [
            (makeDate(year: 2026, month: 6, day: 22), "Cabralstraat 1 OR training"),
            (makeDate(year: 2026, month: 6, day: 22), "slagverbetering les 20u?"),

            (makeDate(year: 2026, month: 6, day: 24), "sanctum marie"),
            (makeDate(year: 2026, month: 6, day: 25), "eindemaandborrel VL"),
            (makeDate(year: 2026, month: 6, day: 26), "oesters en paella"),
            (makeDate(year: 2026, month: 6, day: 28), "Vaderdag vieren ipv"),

            (makeDate(year: 2026, month: 6, day: 29), "eerste OR vergadering"),
            (makeDate(year: 2026, month: 6, day: 29), "vessel restaurant 18u"),
            (makeDate(year: 2026, month: 6, day: 29), "John Johnson comedy 20u"),

            (makeDate(year: 2026, month: 6, day: 30), "chef special???"),
            (makeDate(year: 2026, month: 7, day: 2), "tuin borrel audrey?"),
            (makeDate(year: 2026, month: 7, day: 3), "OR middagje?"),
            (makeDate(year: 2026, month: 7, day: 4), "iets met Querine")
        ]

        for (index, item) in agendaItems.enumerated() {
            let entry = DayEntry(
                date: item.date,
                rawText: item.text,
                manualOrder: Double(index)
            )

            modelContext.insert(entry)
        }

        let todos: [(text: String, bucket: TodoBucket)] = [
            ("appstructuur simpeler maken", .shortTerm),
            ("tijdherkenning testen met 20u en 17-18u", .shortTerm),
            ("recurring logica uitwerken", .shortTerm),
            ("widget vandaag ontwerpen", .shortTerm),
            ("alle talen voorbereiden", .longTerm)
        ]

        for todo in todos {
            modelContext.insert(
                TodoItem(
                    text: todo.text,
                    bucket: todo.bucket
                )
            )
        }

        let recurringItems: [(title: String, frequency: String, nextDate: Date)] = [
            ("Kapper", "elke 6 weken", makeDate(year: 2026, month: 7, day: 10)),
            ("Verjaardag papa", "jaarlijks", makeDate(year: 2026, month: 8, day: 14)),
            ("Tandarts check", "elke 6 maanden", makeDate(year: 2026, month: 9, day: 3))
        ]

        for item in recurringItems {
            modelContext.insert(
                RecurringItem(
                    title: item.title,
                    frequencyText: item.frequency,
                    nextDate: item.nextDate
                )
            )
        }
    }

    @MainActor
    static func insertHistoryData(in modelContext: ModelContext) {
        let existingEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        let existingTodos = (try? modelContext.fetch(FetchDescriptor<TodoItem>())) ?? []
        guard !existingEntries.contains(where: { isHistoryDemoText($0.rawText) }),
              !existingTodos.contains(where: { isHistoryDemoText($0.text) }) else {
            return
        }

        let calendar = AppCalendar.calendar
        let today = AppCalendar.startOfDay(.now)

        for dayOffset in 0..<365 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            let weeksAgo = dayOffset / 7
            let weekday = calendar.component(.weekday, from: day)
            let baseByWeekday = [1: 0, 2: 1, 3: 2, 4: 1, 5: 2, 6: 1, 7: 0]
            var dailyCount = baseByWeekday[weekday, default: 1]

            // Een rustige golf per week voorkomt een te regelmatig patroon.
            let weeklyWave = [0, 1, 0, -1, 1, 0][weeksAgo % 6]
            if weekday == 2 || weekday == 5 {
                dailyCount = max(0, dailyCount + weeklyWave)
            }

            // De recentere maanden groeien licht, verdeeld over enkele weekdagen.
            if weeksAgo < 24, weekday == 4, weeksAgo.isMultiple(of: 2) {
                dailyCount += 1
            }
            if weeksAgo < 12, weekday == 2 || weekday == 6 {
                dailyCount += 1
            }

            // Maandagen fluctueren extra, maar blijven bewust bescheiden.
            if weekday == 2, weeksAgo.isMultiple(of: 4) {
                dailyCount += 1
            }
            if dayOffset % 31 == 0 {
                dailyCount += 1
            }

            for itemIndex in 0..<dailyCount {
                let proposedCompletion = calendar.date(
                    byAdding: .hour,
                    value: 9 + itemIndex * 3,
                    to: day
                ) ?? day
                let completionDate = min(proposedCompletion, .now)
                let sequence = dayOffset + itemIndex

                if sequence.isMultiple(of: 3) {
                    let todo = TodoItem(text: "\(historyMarker) · taak \(dayOffset)-\(itemIndex)")
                    todo.createdAt = calendar.date(byAdding: .day, value: -2, to: completionDate) ?? completionDate
                    todo.isDone = true
                    todo.completedAt = completionDate
                    modelContext.insert(todo)
                } else {
                    let source: EntrySource = sequence.isMultiple(of: 2) ? .recurring : .manual
                    let entry = DayEntry(
                        date: day,
                        rawText: "\(historyMarker) · \(source == .recurring ? "herhaling" : "agenda") \(dayOffset)-\(itemIndex)",
                        source: source
                    )
                    entry.createdAt = calendar.date(byAdding: .day, value: -3, to: completionDate) ?? completionDate
                    entry.isDone = true
                    entry.completedAt = completionDate
                    if source == .recurring {
                        entry.accentRawValue = RecurringTheme.general.rawValue
                    }
                    modelContext.insert(entry)
                }
            }
        }

        _ = PersistenceSafety.save(modelContext)
    }

    @MainActor
    static func removeHistoryData(in modelContext: ModelContext) {
        let entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        let todos = (try? modelContext.fetch(FetchDescriptor<TodoItem>())) ?? []

        for entry in entries where isHistoryDemoText(entry.rawText) {
            modelContext.delete(entry)
        }
        for todo in todos where isHistoryDemoText(todo.text) {
            modelContext.delete(todo)
        }

        _ = PersistenceSafety.save(modelContext)
    }

    @MainActor
    private static func demoAlreadyExists(in modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<DayEntry>()

        guard let entries = try? modelContext.fetch(descriptor) else {
            return false
        }

        return entries.contains {
            $0.rawText == "Cabralstraat 1 OR training"
        }
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        return AppCalendar.calendar.date(from: components) ?? .now
    }
}
