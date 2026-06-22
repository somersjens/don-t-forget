import SwiftUI
import SwiftData

struct AgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    @Query(sort: \DayEntry.date, order: .forward)
    private var entries: [DayEntry]

    @FocusState private var focusedField: AgendaField?

    private var weeks: [WeekSection] {
        let today = AppCalendar.startOfDay(.now)
        let oldestOpenDate = entries
            .filter { !$0.isDone && $0.date < today }
            .map(\.date)
            .min()
        let startDate = oldestOpenDate ?? today
        let endDate = AppCalendar.calendar.date(byAdding: .year, value: 2, to: today) ?? today
        let startOfFirstWeek = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        let startOfLastWeek = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: endDate)?.start ?? endDate
        let weekCount = (AppCalendar.calendar.dateComponents(
            [.weekOfYear],
            from: startOfFirstWeek,
            to: startOfLastWeek
        ).weekOfYear ?? 104) + 1

        return AppCalendar.weekSections(
            startingFrom: startDate,
            numberOfWeeks: weekCount
        )
        .filter { week in
            week.days.contains(where: isVisible)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(weeks) { week in
                        WeekCard(
                            week: week,
                            entries: entries,
                            focusedField: $focusedField
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .navigationTitle("Kalender")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!(undoManager?.canUndo ?? false))
                    .accessibilityLabel("Laatste wijziging terugdraaien")

                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(focusedField == nil)
                    .accessibilityLabel("Toetsenbord sluiten")
                }
            }
            .onAppear {
                modelContext.undoManager = undoManager
            }
        }
    }

    private func isVisible(_ day: DayInfo) -> Bool {
        let today = AppCalendar.startOfDay(.now)

        if day.date >= today {
            return true
        }

        return entries.contains {
            AppCalendar.isSameDay($0.date, day.date) && !$0.isDone
        }
    }
}

enum AgendaField: Hashable {
    case entry(UUID)
    case newEntry(Date)
}

struct WeekCard: View {
    let week: WeekSection
    let entries: [DayEntry]
    let focusedField: FocusState<AgendaField?>.Binding

    private var visibleDays: [DayInfo] {
        let today = AppCalendar.startOfDay(.now)

        return week.days.filter { day in
            if day.date >= today {
                return true
            }

            return entries.contains {
                AppCalendar.isSameDay($0.date, day.date) && !$0.isDone
            }
        }
    }

    private var startDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: week.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "week #\(week.weekNumber) - start \(startDateLabel)",
                systemImage: "calendar"
            )
                .font(.system(size: 17, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(visibleDays) { day in
                    DayBlock(
                        day: day,
                        entries: entriesForDay(day.date),
                        focusedField: focusedField
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 17)
                .fill(Color(.secondarySystemBackground))
        }
    }

    private func entriesForDay(_ date: Date) -> [DayEntry] {
        entries.filter {
            AppCalendar.isSameDay($0.date, date)
        }
    }
}

struct DayBlock: View {
    let day: DayInfo
    let entries: [DayEntry]
    let focusedField: FocusState<AgendaField?>.Binding

    private var sortedEntries: [DayEntry] {
        entries.sorted { first, second in
            switch (first.startMinutes, second.startMinutes) {
            case let (a?, b?):
                if a == b {
                    return first.manualOrder < second.manualOrder
                }
                return a < b

            case (_?, nil):
                return true

            case (nil, _?):
                return false

            case (nil, nil):
                return first.manualOrder < second.manualOrder
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if sortedEntries.isEmpty {
                AgendaInputLine(
                    dateLabel: day.dateLabel,
                    weekdayLetter: day.weekdayLetter,
                    date: day.date,
                    nextOrder: 0,
                    focusedField: focusedField
                )
            } else {
                ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                    AgendaEntryLine(
                        dateLabel: index == 0 ? day.dateLabel : "",
                        weekdayLetter: day.weekdayLetter,
                        entry: entry,
                        focusedField: focusedField
                    )
                }

                AgendaInputLine(
                    dateLabel: "",
                    weekdayLetter: day.weekdayLetter,
                    date: day.date,
                    nextOrder: Double(sortedEntries.count + 1),
                    focusedField: focusedField
                )
            }
        }
    }
}

struct AgendaEntryLine: View {
    let dateLabel: String
    let weekdayLetter: String

    @Bindable var entry: DayEntry
    let focusedField: FocusState<AgendaField?>.Binding

    @Environment(\.modelContext)
    private var modelContext

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            AgendaLinePrefix(dateLabel: dateLabel, weekdayLetter: weekdayLetter)

            TextField("", text: $entry.rawText, axis: .vertical)
                .font(.system(size: 15, design: .monospaced))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .strikethrough(entry.isDone)
                .foregroundStyle(entry.isDone ? .secondary : .primary)
                .focused(focusedField, equals: .entry(entry.id))
                .onChange(of: entry.rawText) { _, _ in
                    if entry.rawText.contains("\n") {
                        entry.rawText = entry.rawText
                            .replacingOccurrences(of: "\n", with: "")
                        entry.refreshParsedFields()
                        focusedField.wrappedValue = .newEntry(entry.date)
                        return
                    }

                    if entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        modelContext.delete(entry)
                        return
                    }
                }
                .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
                    if oldValue == .entry(entry.id), newValue != oldValue {
                        entry.refreshParsedFields()
                    }
                }

            if entry.isUncertain {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            Button {
                entry.toggleDone()
            } label: {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AgendaInputLine: View {
    let dateLabel: String
    let weekdayLetter: String
    let date: Date
    let nextOrder: Double
    let focusedField: FocusState<AgendaField?>.Binding

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            AgendaLinePrefix(dateLabel: dateLabel, weekdayLetter: weekdayLetter)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("typ iets")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 15, design: .monospaced))
                    .textFieldStyle(.plain)
                    .lineLimit(1...)
                    .foregroundStyle(.primary)
                    .focused(focusedField, equals: .newEntry(date))
                    .submitLabel(.return)
                    .onChange(of: text) { _, newValue in
                        guard newValue.contains("\n") else {
                            return
                        }

                        text = newValue.replacingOccurrences(of: "\n", with: "")
                        addEntry()
                    }
                    .onSubmit {
                        addEntry()
                    }
            }

            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
    }

    private func addEntry() {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            return
        }

        let entry = DayEntry(
            date: date,
            rawText: cleanText,
            manualOrder: nextOrder
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            modelContext.insert(entry)
            text = ""
        }

        // Keep typing on the newly-created line after Return is pressed.
        Task { @MainActor in
            focusedField.wrappedValue = .newEntry(date)
        }
    }
}

private struct AgendaLinePrefix: View {
    let dateLabel: String
    let weekdayLetter: String

    var body: some View {
        HStack(spacing: 5) {
            Text(dateLabel.isEmpty ? "     " : dateLabel)
                .foregroundStyle(dateLabel.isEmpty ? .clear : .primary)

            Text(weekdayLetter)
                .foregroundStyle(.secondary)

            Text("|")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 15, design: .monospaced))
    }
}
