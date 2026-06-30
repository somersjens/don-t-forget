import SwiftUI
import SwiftData

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "Alles"
    case agenda = "Agenda"
    case recurring = "Recurring"
    case todo = "To-do"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .agenda: "calendar"
        case .recurring: "repeat"
        case .todo: "checklist"
        }
    }

    var color: Color {
        switch self {
        case .all: .primary
        case .agenda: .blue
        case .recurring: .orange
        case .todo: .green
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    @Query(sort: \DayEntry.date, order: .reverse)
    private var entries: [DayEntry]

    @Query(sort: \TodoItem.createdAt, order: .reverse)
    private var todos: [TodoItem]

    @State private var filter: HistoryFilter = .all
    @State private var isScrolled = false
    @State private var isShowingSettings = false
    @State private var recentlyRestoredTitle: String?
    @State private var dismissRestoreTask: Task<Void, Never>?

    private var allRows: [HistoryRow] {
        let agendaRows = entries
            .filter { $0.isDone && $0.source == .manual }
            .map { HistoryRow(entry: $0, source: .agenda) }
        let recurringRows = entries
            .filter { $0.isDone && $0.source == .recurring }
            .map { HistoryRow(entry: $0, source: .recurring) }
        let todoRows = todos
            .filter(\.isDone)
            .map { HistoryRow(todo: $0) }

        return (agendaRows + recurringRows + todoRows).sorted {
            $0.completedAt > $1.completedAt
        }
    }

    private var visibleRows: [HistoryRow] {
        guard filter != .all else { return allRows }
        return allRows.filter { $0.source.filter == filter }
    }

    private var sections: [HistoryDaySection] {
        let grouped = Dictionary(grouping: visibleRows) {
            AppCalendar.startOfDay($0.completedAt)
        }
        return grouped
            .map { HistoryDaySection(date: $0.key, rows: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var completedThisWeek: Int {
        guard let week = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: .now) else {
            return 0
        }
        return allRows.count { week.contains($0.completedAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HistorySummaryCard(
                        total: allRows.count,
                        thisWeek: completedThisWeek
                    )

                    HistoryFilterBar(
                        selection: $filter,
                        count: count(for:)
                    )

                    if sections.isEmpty {
                        HistoryEmptyState(filter: filter)
                    } else {
                        ForEach(sections) { section in
                            HistoryDayCard(
                                section: section,
                                restore: restore
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 12
            } action: { _, newValue in
                isScrolled = newValue
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("History")
                        .font(.system(size: 26, weight: .bold))
                        .opacity(isScrolled ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: isScrolled)

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            undoManager?.undo()
                            try? modelContext.save()
                            hideRestoreBar()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(!(undoManager?.canUndo ?? false))
                        .accessibilityLabel("Laatste wijziging terugdraaien")

                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel("Instellingen")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if let recentlyRestoredTitle {
                    restoreBar(title: recentlyRestoredTitle)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onAppear {
                modelContext.undoManager = undoManager
            }
        }
    }

    private func count(for filter: HistoryFilter) -> Int {
        guard filter != .all else { return allRows.count }
        return allRows.count { $0.source.filter == filter }
    }

    private func restore(_ row: HistoryRow) {
        dismissRestoreTask?.cancel()
        withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
            row.restore()
            recentlyRestoredTitle = row.title
        }
        try? modelContext.save()

        dismissRestoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            hideRestoreBar()
        }
    }

    private func hideRestoreBar() {
        dismissRestoreTask?.cancel()
        dismissRestoreTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyRestoredTitle = nil
        }
    }

    private func restoreBar(title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.blue)
            Text("‘\(title)’ teruggezet")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Ongedaan maken") {
                undoManager?.undo()
                try? modelContext.save()
                hideRestoreBar()
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

private struct HistorySummaryCard: View {
    let total: Int
    let thisWeek: Int

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.green.opacity(0.16))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(total == 1 ? "1 item afgerond" : "\(total) items afgerond")
                    .font(.system(size: 17, weight: .semibold))
                Text(thisWeek == 1 ? "1 deze week" : "\(thisWeek) deze week")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.045), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryFilterBar: View {
    @Binding var selection: HistoryFilter
    let count: (HistoryFilter) -> Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { filter in
                    HistoryFilterChip(
                        filter: filter,
                        itemCount: count(filter),
                        isSelected: selection == filter
                    ) {
                        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                            selection = filter
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct HistoryFilterChip: View {
    let filter: HistoryFilter
    let itemCount: Int
    let isSelected: Bool
    let select: () -> Void

    private var foregroundColor: Color {
        isSelected ? filter.color : .secondary
    }

    private var countColor: Color {
        isSelected ? filter.color : Color.secondary.opacity(0.65)
    }

    private var backgroundColor: Color {
        isSelected ? filter.color.opacity(0.13) : Color(.tertiarySystemFill)
    }

    var body: some View {
        Button(action: select) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.rawValue), \(itemCount) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: filter.icon)
                .font(.system(size: 11, weight: .semibold))

            Text(filter.rawValue)
                .font(.system(size: 13, weight: .semibold))

            Text("\(itemCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(countColor)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(backgroundColor, in: Capsule())
        .overlay {
            if isSelected {
                Capsule()
                    .stroke(filter.color.opacity(0.22), lineWidth: 1)
            }
        }
    }
}

private struct HistoryDayCard: View {
    let section: HistoryDaySection
    let restore: (HistoryRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(section.countText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    HistoryItemRow(row: row) {
                        restore(row)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)

                    if index < section.rows.count - 1 {
                        Divider()
                            .overlay(Color.primary.opacity(0.06))
                            .padding(.leading, 63)
                    }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
        }
    }
}

private struct HistoryItemRow: View {
    let row: HistoryRow
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(row.source.color.opacity(0.16))
                Image(systemName: row.source.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(row.source.color)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(row.source.title)
                    Text("·")
                    Text(row.completedAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button(action: restore) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(row.source.color)
                    .frame(width: 36, height: 36)
                    .background(row.source.color.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zet terug naar \(row.source.title)")
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Terugzetten", systemImage: "arrow.uturn.backward", action: restore)
        }
    }
}

private struct HistoryEmptyState: View {
    let filter: HistoryFilter

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(filter.color.opacity(0.12))
                Image(systemName: filter == .all ? "clock.arrow.circlepath" : filter.icon)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(filter.color)
            }
            .frame(width: 62, height: 62)

            Text(filter == .all ? "Nog geen history" : "Geen afgeronde \(filter.rawValue.lowercased())-items")
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Afgeronde items verschijnen hier automatisch en kun je altijd weer terugzetten.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct HistoryDaySection: Identifiable {
    let date: Date
    let rows: [HistoryRow]

    var id: Date { date }

    var title: String {
        if AppCalendar.calendar.isDateInToday(date) { return "Vandaag" }
        if AppCalendar.calendar.isDateInYesterday(date) { return "Gisteren" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var countText: String {
        rows.count == 1 ? "1 item" : "\(rows.count) items"
    }
}

private enum HistorySource {
    case agenda
    case recurring
    case todo

    var title: String {
        switch self {
        case .agenda: "Agenda"
        case .recurring: "Recurring"
        case .todo: "To-do"
        }
    }

    var icon: String {
        switch self {
        case .agenda: "calendar"
        case .recurring: "repeat"
        case .todo: "checklist"
        }
    }

    var color: Color {
        switch self {
        case .agenda: .blue
        case .recurring: .orange
        case .todo: .green
        }
    }

    var filter: HistoryFilter {
        switch self {
        case .agenda: .agenda
        case .recurring: .recurring
        case .todo: .todo
        }
    }
}

private struct HistoryRow: Identifiable {
    let id: UUID
    let title: String
    let source: HistorySource
    let completedAt: Date
    private let entry: DayEntry?
    private let todo: TodoItem?

    init(entry: DayEntry, source: HistorySource) {
        id = entry.id
        title = entry.rawText
        self.source = source
        completedAt = entry.completedAt ?? entry.date
        self.entry = entry
        todo = nil
    }

    init(todo: TodoItem) {
        id = todo.id
        title = todo.text
        source = .todo
        completedAt = todo.completedAt ?? todo.createdAt
        entry = nil
        self.todo = todo
    }

    func restore() {
        entry?.isDone = false
        entry?.completedAt = nil
        todo?.isDone = false
        todo?.completedAt = nil
    }
}
