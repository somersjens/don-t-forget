import SwiftUI
import SwiftData

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "Alles"
    case agenda = "Agenda"
    case recurring = "Recurring"
    case todo = "To-do"

    var id: String {
        rawValue
    }
}

struct HistoryView: View {
    @Query(sort: \DayEntry.date, order: .reverse)
    private var entries: [DayEntry]

    @Query(sort: \TodoItem.createdAt, order: .reverse)
    private var todos: [TodoItem]

    @State private var filter: HistoryFilter = .all

    private var historyRows: [HistoryRow] {
        let agendaRows = entries
            .filter { $0.isDone }
            .filter { $0.source == .manual }
            .map {
                HistoryRow(
                    title: $0.rawText,
                    source: "Agenda",
                    icon: "calendar",
                    completedAt: $0.completedAt ?? .distantPast
                )
            }

        let recurringRows = entries
            .filter { $0.isDone }
            .filter { $0.source == .recurring }
            .map {
                HistoryRow(
                    title: $0.rawText,
                    source: "Recurring",
                    icon: "repeat",
                    completedAt: $0.completedAt ?? .distantPast
                )
            }

        let todoRows = todos
            .filter { $0.isDone }
            .map {
                HistoryRow(
                    title: $0.text,
                    source: "To-do",
                    icon: "checklist",
                    completedAt: $0.completedAt ?? .distantPast
                )
            }

        let combined: [HistoryRow]

        switch filter {
        case .all:
            combined = agendaRows + recurringRows + todoRows
        case .agenda:
            combined = agendaRows
        case .recurring:
            combined = recurringRows
        case .todo:
            combined = todoRows
        }

        return combined.sorted {
            $0.completedAt > $1.completedAt
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Filter", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Text(filter.rawValue)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if historyRows.isEmpty {
                    ContentUnavailableView(
                        "Nog geen history",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Vink agenda-items, recurring-items of to-do’s af om ze hier te zien.")
                    )
                } else {
                    List {
                        ForEach(historyRows) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: row.icon)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title)
                                        .font(.body)

                                    Text("\(row.source) · \(row.completedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

struct HistoryRow: Identifiable {
    let id = UUID()
    let title: String
    let source: String
    let icon: String
    let completedAt: Date
}
