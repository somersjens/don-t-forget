import SwiftUI
import SwiftData
import Charts

private struct HistoryRecurringCategoryAppearance: Decodable {
    let id: String
    let colorRawValue: String
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "Alles"
    case agenda = "Agenda"
    case recurring = "Recurring"
    case todo = "Taken"

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
    @Environment(\.locale) private var locale

    @Query(sort: \DayEntry.date, order: .reverse)
    private var entries: [DayEntry]

    @Query(sort: \TodoItem.createdAt, order: .reverse)
    private var todos: [TodoItem]

    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.recurringBirthdayCategoryDeleted) private var birthdayCategoryDeleted = false
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""
    @AppStorage(SettingsKeys.historyShowsDeletedItems) private var showsDeletedItems = false

    @State private var filter: HistoryFilter = .all
    @State private var isScrolled = false
    @State private var isShowingSettings = false
    @State private var recentlyRestoredTitle: String?
    @State private var dismissRestoreTask: Task<Void, Never>?
    @State private var selectedDeletionRowID: UUID?
    @State private var pendingPermanentDeletion: HistoryRow?
    @State private var permanentDeletionTask: Task<Void, Never>?

    private var allRows: [HistoryRow] {
        let recurringColors = recurringCategoryColors
        let todoColors = todoCategoryColors
        let agendaRows = entries
            .filter { ($0.isDone || $0.isRemoved) && $0.source != .recurring }
            .map { HistoryRow(entry: $0, source: .agenda, color: .gray) }
        let recurringRows = entries
            .filter { ($0.isDone || $0.isRemoved) && $0.source == .recurring }
            .map { entry in
                let categoryID = entry.accentRawValue == "birthdayReminder"
                    ? RecurringTheme.birthday.rawValue
                    : entry.accentRawValue
                return HistoryRow(
                    entry: entry,
                    source: .recurring,
                    color: recurringColors[categoryID] ?? .gray
                )
            }
        let todoRows = todos
            .filter { $0.isDone || $0.isRemoved }
            .map { todo in
                HistoryRow(
                    todo: todo,
                    color: todoColors[todo.bucketRawValue] ?? .gray
                )
            }

        return (agendaRows + recurringRows + todoRows).sorted {
            $0.completedAt > $1.completedAt
        }
    }

    private var recurringCategoryColors: [String: Color] {
        let appearances: [HistoryRecurringCategoryAppearance]
        if let data = recurringCategoriesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([HistoryRecurringCategoryAppearance].self, from: data) {
            appearances = decoded
        } else {
            appearances = [
                HistoryRecurringCategoryAppearance(
                    id: RecurringTheme.birthday.rawValue,
                    colorRawValue: RecurringThemeColorOption.blue.rawValue
                ),
                HistoryRecurringCategoryAppearance(
                    id: "holidays",
                    colorRawValue: RecurringThemeColorOption.orange.rawValue
                ),
                HistoryRecurringCategoryAppearance(
                    id: RecurringTheme.general.rawValue,
                    colorRawValue: RecurringThemeColorOption.yellow.rawValue
                )
            ]
        }

        return Dictionary(uniqueKeysWithValues: appearances.compactMap { appearance in
            guard (!birthdayCategoryDeleted || appearance.id != RecurringTheme.birthday.rawValue),
                  let color = RecurringThemeColorOption(rawValue: appearance.colorRawValue)?.color else {
                return nil
            }
            return (appearance.id, color)
        })
    }

    private var todoCategoryColors: [String: Color] {
        Dictionary(uniqueKeysWithValues: TodoGroupStore.decode(todoGroupsData).map {
            ($0.id, $0.color)
        })
    }

    private var visibleRows: [HistoryRow] {
        allRows.filter { row in
            (showsDeletedItems || !row.isRemoved)
                && row.id != pendingPermanentDeletion?.id
                && (filter == .all || row.source.filter == filter)
        }
    }

    private var sections: [HistoryDaySection] {
        let grouped = Dictionary(grouping: visibleRows) {
            AppCalendar.startOfDay($0.completedAt)
        }
        return grouped
            .map { HistoryDaySection(date: $0.key, rows: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var completedLastSevenDays: Int {
        let today = AppCalendar.startOfDay(.now)
        let start = AppCalendar.calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return completedRows.count { $0.completedAt >= start }
    }

    private var completedRows: [HistoryRow] {
        allRows.filter { !$0.isRemoved }
    }

    private var isHistoryDemoActive: Bool {
        entries.contains { $0.rawText.hasPrefix(DemoData.historyMarker) }
            || todos.contains { $0.text.hasPrefix(DemoData.historyMarker) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HistorySummaryCard(
                        total: completedRows.count,
                        lastSevenDays: completedLastSevenDays,
                        completionDates: completedRows.map(\.completedAt),
                        isDemoActive: isHistoryDemoActive,
                        activateDemoData: activateHistoryDemoData,
                        deactivateDemoData: deactivateHistoryDemoData
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
                                selectedDeletionRowID: selectedDeletionRowID,
                                revealPermanentDelete: revealPermanentDelete,
                                permanentlyDelete: beginPermanentDeletion,
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
                ZStack {
                    Text(AppSection.history.title(for: locale))
                        .font(.system(size: 26, weight: .bold))
                        .opacity(isScrolled ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: isScrolled)

                    HStack {
                        Spacer()

                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel("Instellingen")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if let pendingPermanentDeletion {
                    permanentDeletionBar(title: pendingPermanentDeletion.title)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let recentlyRestoredTitle {
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
        let rows = allRows.filter { showsDeletedItems || !$0.isRemoved }
        guard filter != .all else { return rows.count }
        return rows.count { $0.source.filter == filter }
    }

    private func activateHistoryDemoData() {
        DemoData.insertHistoryData(in: modelContext)
        try? modelContext.save()
    }

    private func deactivateHistoryDemoData() {
        DemoData.removeHistoryData(in: modelContext)
        try? modelContext.save()
    }

    private func restore(_ row: HistoryRow) {
        selectedDeletionRowID = nil
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

    private func revealPermanentDelete(_ row: HistoryRow) {
        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
            selectedDeletionRowID = selectedDeletionRowID == row.id ? nil : row.id
        }
    }

    private func beginPermanentDeletion(_ row: HistoryRow) {
        if let previous = pendingPermanentDeletion {
            commitPermanentDeletion(previous)
        }

        permanentDeletionTask?.cancel()
        dismissRestoreTask?.cancel()
        recentlyRestoredTitle = nil
        withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
            selectedDeletionRowID = nil
            pendingPermanentDeletion = row
        }

        permanentDeletionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            commitPermanentDeletion(row)
        }
    }

    private func undoPermanentDeletion() {
        permanentDeletionTask?.cancel()
        permanentDeletionTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            pendingPermanentDeletion = nil
        }
    }

    private func commitPermanentDeletion(_ row: HistoryRow) {
        permanentDeletionTask?.cancel()
        permanentDeletionTask = nil
        row.permanentlyDelete(in: modelContext)
        try? modelContext.save()
        withAnimation(.easeOut(duration: 0.2)) {
            if pendingPermanentDeletion?.id == row.id {
                pendingPermanentDeletion = nil
            }
        }
    }

    private func permanentDeletionBar(title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)
            Text("‘\(title)’ definitief verwijderd")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Ongedaan maken", action: undoPermanentDeletion)
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
    @Environment(\.colorScheme) private var colorScheme
    let total: Int
    let lastSevenDays: Int
    let completionDates: [Date]
    let isDemoActive: Bool
    let activateDemoData: () -> Void
    let deactivateDemoData: () -> Void
    @State private var isExpanded = false

    private var chartsHeight: CGFloat {
        let count = HistoryChartPeriod.available(for: completionDates).count
        return 28 + (CGFloat(count) * HistoryBarChart.layoutHeight) + (CGFloat(max(0, count - 1)) * 18)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(colorScheme == .light ? Color.brandLightBlue : Color.brandHardBlue.opacity(0.22))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.brandHardBlue)
                }
                .frame(width: 42, height: 42)
                .contentShape(RoundedRectangle(cornerRadius: 11))
                .onTapGesture(count: isDemoActive ? 1 : 5) {
                    if isDemoActive {
                        deactivateDemoData()
                    } else {
                        activateDemoData()
                        withAnimation(.snappy(duration: 0.38, extraBounce: 0)) {
                            isExpanded = true
                        }
                    }
                }
                .accessibilityAction(named: isDemoActive ? "Demodata verwijderen" : "Demodata activeren") {
                    if isDemoActive {
                        deactivateDemoData()
                    } else {
                        activateDemoData()
                        withAnimation(.snappy(duration: 0.38, extraBounce: 0)) {
                            isExpanded = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(total) afgerond")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(lastSevenDays) in afgelopen 7 dagen")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                chartControl
            }
            .padding(14)

            Divider()
                .overlay(Color.primary.opacity(0.07))
                .padding(.horizontal, 14)
                .frame(height: isExpanded ? 1 : 0)
                .clipped()

            HistoryCharts(completionDates: completionDates)
                .padding(14)
                .frame(height: isExpanded ? chartsHeight : 0, alignment: .top)
                .clipped()
        }
        .animation(.snappy(duration: 0.38, extraBounce: 0), value: isExpanded)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.045), lineWidth: 1)
        }
    }

    private var chartControl: some View {
        Button {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 17, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(.secondary)
            .frame(width: 52, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Grafieken inklappen" : "Grafieken uitklappen")
    }
}

private struct HistoryCharts: View {
    let completionDates: [Date]

    private var availablePeriods: [HistoryChartPeriod] {
        HistoryChartPeriod.available(for: completionDates)
    }

    var body: some View {
        VStack(spacing: 18) {
            ForEach(availablePeriods) { period in
                HistoryBarChart(
                    period: period,
                    buckets: period.buckets(for: completionDates)
                )
            }
        }
    }
}

private struct HistoryBarChart: View {
    static let layoutHeight: CGFloat = 193

    let period: HistoryChartPeriod
    let buckets: [HistoryChartBucket]

    private var yMaximum: Double {
        let highest = buckets.map(\.count).max() ?? 0
        return Double(highest + max(1, Int(ceil(Double(highest) * 0.15))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(period.title)
                .font(.system(size: 14, weight: .semibold))

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Periode", bucket.label),
                    y: .value("Afgerond", bucket.count),
                    width: .ratio(0.62)
                )
                .foregroundStyle(bucket.isCurrent ? Color.brandHardBlue : Color.brandHardBlue.opacity(0.52))
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 4
                ))
                .annotation(position: .top, spacing: 3) {
                    if bucket.isCurrent {
                        Text("\(bucket.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.gray)
                    }
                }
            }
            .chartXScale(domain: buckets.map(\.label))
            .chartYScale(domain: 0...yMaximum)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                        .foregroundStyle(Color.primary.opacity(0.07))
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.gray)
                }
            }
            .frame(height: 142)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .frame(height: Self.layoutHeight, alignment: .top)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

private struct HistoryChartBucket: Identifiable {
    let start: Date
    let label: String
    let count: Int
    let isCurrent: Bool

    var id: Date { start }
}

private enum HistoryChartPeriod: String, Identifiable {
    case days
    case weeks
    case months

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: "Afgelopen 7 dagen"
        case .weeks: "Afgelopen 10 weken"
        case .months: "Afgelopen 12 maanden"
        }
    }

    static func available(for dates: [Date]) -> [HistoryChartPeriod] {
        var periods: [HistoryChartPeriod] = [.days]
        guard let oldest = dates.min() else { return periods }

        let calendar = AppCalendar.calendar
        let today = AppCalendar.startOfDay(.now)
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        if oldest < fourteenDaysAgo {
            periods.append(.weeks)
        }

        let currentMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: currentMonth) ?? currentMonth
        if oldest < twoMonthsAgo {
            periods.append(.months)
        }

        return periods
    }

    func buckets(for dates: [Date]) -> [HistoryChartBucket] {
        let calendar = AppCalendar.calendar
        let today = AppCalendar.startOfDay(.now)
        let currentStart: Date
        let component: Calendar.Component
        let numberOfBuckets: Int

        switch self {
        case .days:
            currentStart = today
            component = .day
            numberOfBuckets = 7
        case .weeks:
            currentStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            component = .weekOfYear
            numberOfBuckets = 10
        case .months:
            currentStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
            component = .month
            numberOfBuckets = 12
        }

        return (0..<numberOfBuckets).map { index in
            let offset = index - (numberOfBuckets - 1)
            let start = calendar.date(byAdding: component, value: offset, to: currentStart) ?? currentStart
            let end = calendar.date(byAdding: component, value: 1, to: start) ?? start
            return HistoryChartBucket(
                start: start,
                label: label(for: start, calendar: calendar),
                count: dates.count { $0 >= start && $0 < end },
                isCurrent: index == numberOfBuckets - 1
            )
        }
    }

    private func label(for date: Date, calendar: Calendar) -> String {
        switch self {
        case .days:
            AppCalendar.localizedDate(date, template: "EEE")
        case .weeks:
            "w\(calendar.component(.weekOfYear, from: date))"
        case .months:
            AppCalendar.localizedDate(date, template: "MMM")
        }
    }
}

private struct HistoryFilterBar: View {
    @Binding var selection: HistoryFilter
    let count: (HistoryFilter) -> Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(HistoryFilter.allCases) { filter in
                HistoryFilterChip(
                    filter: filter,
                    itemCount: count(filter),
                    isSelected: selection == filter,
                    showsTitle: filter == .all
                ) {
                    selection = filter
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryFilterChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let filter: HistoryFilter
    let itemCount: Int
    let isSelected: Bool
    let showsTitle: Bool
    let select: () -> Void

    private var foregroundColor: Color {
        isSelected ? Color.brandHardBlue : Color.secondary
    }

    private var backgroundColor: Color {
        isSelected
            ? (colorScheme == .light ? .brandLightBlue : Color.brandHardBlue.opacity(0.22))
            : Color(.tertiarySystemFill)
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
                .font(.system(size: 13.2, weight: .semibold))

            if showsTitle {
                Text(filter.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .frame(
            minWidth: showsTitle ? 100 : nil,
            maxWidth: showsTitle ? nil : .infinity,
            minHeight: 36,
            maxHeight: 36
        )
        .background(backgroundColor, in: Capsule())
        .overlay {
            if isSelected {
                Capsule()
                    .stroke(Color.brandHardBlue.opacity(0.78), lineWidth: 1.5)
            }
        }
    }
}

private struct HistoryDayCard: View {
    let section: HistoryDaySection
    let selectedDeletionRowID: UUID?
    let revealPermanentDelete: (HistoryRow) -> Void
    let permanentlyDelete: (HistoryRow) -> Void
    let restore: (HistoryRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    HistoryItemRow(
                        row: row,
                        showsPermanentDelete: selectedDeletionRowID == row.id,
                        revealPermanentDelete: { revealPermanentDelete(row) },
                        permanentlyDelete: { permanentlyDelete(row) },
                        restore: { restore(row) }
                    )
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .padding(.vertical, 11)

                    if index < section.rows.count - 1 {
                        Divider()
                            .overlay(Color.primary.opacity(0.06))
                            .padding(.leading, 67)
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
    let showsPermanentDelete: Bool
    let revealPermanentDelete: () -> Void
    let permanentlyDelete: () -> Void
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Button(action: revealPermanentDelete) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(row.color.opacity(0.16))
                    Image(systemName: row.source.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(row.color)
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Acties voor \(row.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .strikethrough(row.isRemoved)

                HStack(spacing: 5) {
                    Text(row.source.title)
                    Text("·")
                    Text(row.completedAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if showsPermanentDelete {
                Button(role: .destructive, action: permanentlyDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
                .accessibilityLabel("Definitief verwijderen")
            } else {
                Button(action: restore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.color)
                        .frame(width: 36, height: 36)
                        .background(row.color.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
                .accessibilityLabel("Zet terug naar \(row.source.title)")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Terugzetten", systemImage: "arrow.uturn.backward", action: restore)
            Button("Definitief verwijderen", systemImage: "trash", role: .destructive, action: permanentlyDelete)
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
        return AppCalendar.localizedDate(date, template: "EEEEdMMMM")
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
        case .todo: "Taken"
        }
    }

    var icon: String {
        switch self {
        case .agenda: "calendar"
        case .recurring: "repeat"
        case .todo: "checklist"
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
    let color: Color
    let isRemoved: Bool
    private let entry: DayEntry?
    private let todo: TodoItem?

    init(entry: DayEntry, source: HistorySource, color: Color) {
        id = entry.id
        title = entry.rawText
        self.source = source
        completedAt = entry.completedAt ?? entry.date
        self.color = color
        isRemoved = entry.isRemoved
        self.entry = entry
        todo = nil
    }

    init(todo: TodoItem, color: Color) {
        id = todo.id
        title = todo.text
        source = .todo
        completedAt = todo.completedAt ?? todo.createdAt
        self.color = color
        isRemoved = todo.isRemoved
        entry = nil
        self.todo = todo
    }

    func restore() {
        entry?.isDone = false
        entry?.isRemoved = false
        entry?.completedAt = nil
        todo?.isDone = false
        todo?.isRemoved = false
        todo?.completedAt = nil
    }

    func permanentlyDelete(in modelContext: ModelContext) {
        if let entry {
            let entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
            CalendarSyncService.deleteEventIfUnshared(for: entry, among: entries)
            modelContext.delete(entry)
        }
        if let todo {
            modelContext.delete(todo)
        }
    }
}
