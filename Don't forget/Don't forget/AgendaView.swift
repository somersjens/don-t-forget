import SwiftUI
import SwiftData

struct AgendaView: View {
    @Query(sort: \DayEntry.date, order: .forward)
    private var entries: [DayEntry]

    @FocusState private var focusedField: AgendaField?

    private var weeks: [WeekSection] {
        AppCalendar.weekSections(numberOfWeeks: 12)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Toetsenbord sluiten")
                }
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("--- Week \(week.weekNumber) \(week.monthTitle)")
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(week.days) { day in
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

            Button {
                entry.toggleDone()
            } label: {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            if let startMinutes = entry.startMinutes {
                Text(TimeParser.timeLabel(startMinutes, end: entry.endMinutes))
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(Color(.systemBackground).opacity(0.85))
                    }
            }

            TextField("", text: $entry.rawText, axis: .vertical)
                .font(.system(size: 16, design: .monospaced))
                .textFieldStyle(.plain)
                .strikethrough(entry.isDone)
                .foregroundStyle(entry.isDone ? .secondary : .primary)
                .focused(focusedField, equals: .entry(entry.id))
                .onChange(of: entry.rawText) { _, _ in
                    entry.refreshParsedFields()
                }

            if entry.isUncertain {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Button {
                entry.showOnWidget.toggle()
            } label: {
                Image(systemName: entry.showOnWidget ? "iphone.gen3" : "iphone.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                modelContext.delete(entry)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, entry.hasTime ? 5 : 0)
        .padding(.horizontal, entry.hasTime ? 7 : 0)
        .background {
            if entry.hasTime {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(.systemBackground).opacity(0.55))
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            AgendaLinePrefix(dateLabel: dateLabel, weekdayLetter: weekdayLetter)

            TextField(
                "",
                text: $text,
                prompt: Text("typ iets").foregroundStyle(.secondary),
                axis: .vertical
            )
                .font(.system(size: 16, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .focused(focusedField, equals: .newEntry(date))
                .submitLabel(.return)
                .onSubmit {
                    addEntry()
                }

            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
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

        modelContext.insert(entry)
        text = ""

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
        .font(.system(size: 16, design: .monospaced))
    }
}
