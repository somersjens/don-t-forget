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

    func title(for locale: Locale) -> String {
        switch self {
        case .all: locale.localized("Alles", "All")
        case .agenda: locale.localized("Agenda", "Calendar")
        case .recurring: locale.localized("Herhalingen", "Recurring")
        case .todo: locale.localized("Taken", "Tasks")
        }
    }

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

    var backgroundColor: Color {
        switch self {
        case .all: Color(.tertiarySystemFill)
        case .agenda: RecurringThemeColorOption.blue.backgroundColor
        case .recurring: RecurringThemeColorOption.orange.backgroundColor
        case .todo: RecurringThemeColorOption.green.backgroundColor
        }
    }
}

struct HistoryView: View {
    private static let pageSize = 250

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.locale) private var locale

    @Query(
        filter: #Predicate<DayEntry> { entry in
            entry.isDone || entry.isRemoved
        },
        sort: \DayEntry.date,
        order: .reverse
    )
    private var entries: [DayEntry]

    @Query(
        filter: #Predicate<TodoItem> { todo in
            todo.isDone || todo.isRemoved
        },
        sort: \TodoItem.createdAt,
        order: .reverse
    )
    private var todos: [TodoItem]

    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.recurringBirthdayCategoryDeleted) private var birthdayCategoryDeleted = false
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""
    @AppStorage(SettingsKeys.historyShowsDeletedItems) private var showsDeletedItems = true

    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var isScrolled = false
    @State private var isShowingSettings = false
    @State private var recentlyRestoredRow: HistoryRow?
    @State private var dismissRestoreTask: Task<Void, Never>?
    @State private var selectedDeletionRowID: UUID?
    @State private var pendingPermanentDeletion: HistoryRow?
    @State private var permanentDeletionTask: Task<Void, Never>?
    @State private var visibleHistoryLimit = Self.pageSize

    private var allRows: [HistoryRow] {
        let recurringColors = recurringCategoryColors
        let recurringBackgroundColors = recurringCategoryBackgroundColors
        let todoColors = todoCategoryColors
        let todoBackgroundColors = todoCategoryBackgroundColors
        let agendaRows = entries
            .filter { $0.source != .recurring }
            .map {
                HistoryRow(
                    entry: $0,
                    source: .agenda,
                    color: RecurringThemeColorOption.gray.color,
                    backgroundColor: RecurringThemeColorOption.gray.backgroundColor
                )
            }
        let recurringRows = entries
            .filter { $0.source == .recurring }
            .map { entry in
                let categoryID = entry.accentRawValue == "birthdayReminder"
                    ? RecurringTheme.birthday.rawValue
                    : entry.accentRawValue
                return HistoryRow(
                    entry: entry,
                    source: .recurring,
                    color: recurringColors[categoryID] ?? RecurringThemeColorOption.gray.color,
                    backgroundColor: recurringBackgroundColors[categoryID]
                        ?? RecurringThemeColorOption.gray.backgroundColor
                )
            }
        let todoRows = todos
            .map { todo in
                HistoryRow(
                    todo: todo,
                    color: todoColors[todo.bucketRawValue] ?? RecurringThemeColorOption.gray.color,
                    backgroundColor: todoBackgroundColors[todo.bucketRawValue]
                        ?? RecurringThemeColorOption.gray.backgroundColor
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

    private var recurringCategoryBackgroundColors: [String: Color] {
        Dictionary(uniqueKeysWithValues: recurringCategoryAppearances.compactMap { appearance in
            guard let color = RecurringThemeColorOption(rawValue: appearance.colorRawValue) else { return nil }
            return (appearance.id, color.backgroundColor)
        })
    }

    private var todoCategoryBackgroundColors: [String: Color] {
        Dictionary(uniqueKeysWithValues: TodoGroupStore.decode(todoGroupsData).map {
            ($0.id, $0.backgroundColor)
        })
    }

    private var recurringCategoryAppearances: [HistoryRecurringCategoryAppearance] {
        if let data = recurringCategoriesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([HistoryRecurringCategoryAppearance].self, from: data) {
            return decoded
        }
        return [
            HistoryRecurringCategoryAppearance(id: RecurringTheme.birthday.rawValue, colorRawValue: RecurringThemeColorOption.blue.rawValue),
            HistoryRecurringCategoryAppearance(id: "holidays", colorRawValue: RecurringThemeColorOption.orange.rawValue),
            HistoryRecurringCategoryAppearance(id: RecurringTheme.general.rawValue, colorRawValue: RecurringThemeColorOption.yellow.rawValue)
        ]
    }

    private func visibleRows(from rows: [HistoryRow]) -> [HistoryRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            (showsDeletedItems || !row.isRemoved)
                && row.id != pendingPermanentDeletion?.id
                && (filter == .all || row.source.filter == filter)
                && (query.isEmpty || row.title.localizedStandardContains(query))
        }
    }

    private func sections(from rows: [HistoryRow]) -> [HistoryDaySection] {
        let grouped = Dictionary(grouping: rows) {
            AppCalendar.startOfDay($0.completedAt)
        }
        return grouped
            .map { HistoryDaySection(date: $0.key, rows: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func completedLastSevenDays(in rows: [HistoryRow]) -> Int {
        let today = AppCalendar.startOfDay(.now)
        let start = AppCalendar.calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return rows.count { $0.completedAt >= start }
    }

    private var isHistoryDemoActive: Bool {
        entries.contains { DemoData.isHistoryDemoText($0.rawText) }
            || todos.contains { DemoData.isHistoryDemoText($0.text) }
    }

    var body: some View {
        let historyRows = allRows
        let completedRows = historyRows.filter { !$0.isRemoved }
        let chartRows = completedRows.filter {
            filter == .all || $0.source.filter == filter
        }
        let filteredRows = visibleRows(from: historyRows)
        let pagedRows = Array(filteredRows.prefix(visibleHistoryLimit))
        let sections = sections(from: pagedRows)
        let remainingRowCount = max(0, filteredRows.count - pagedRows.count)

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HistoryFilterBar(
                        selection: $filter,
                        count: { count(for: $0, among: historyRows) }
                    )

                    HistorySummaryCard(
                        total: chartRows.count,
                        lastSevenDays: completedLastSevenDays(in: chartRows),
                        completionDates: chartRows.map(\.completedAt),
                        isDemoActive: isHistoryDemoActive,
                        activateDemoData: activateHistoryDemoData,
                        deactivateDemoData: deactivateHistoryDemoData
                    )

                    HistorySearchBar(text: $searchText)

                    if sections.isEmpty {
                        HistoryEmptyState(
                            filter: filter,
                            hasSearchQuery: !searchText
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    } else {
                        ForEach(sections) { section in
                            HistoryDayCard(
                                section: section,
                                searchText: searchText,
                                selectedDeletionRowID: selectedDeletionRowID,
                                revealPermanentDelete: revealPermanentDelete,
                                permanentlyDelete: beginPermanentDeletion,
                                restore: restore
                            )
                        }
                        if remainingRowCount > 0 {
                            Button {
                                visibleHistoryLimit += Self.pageSize
                            } label: {
                                Label(
                                    locale.localized(
                                        "Laad oudere items (\(min(Self.pageSize, remainingRowCount)))",
                                        "Load Older Items (\(min(Self.pageSize, remainingRowCount)))"
                                    ),
                                    systemImage: "arrow.down.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.brandHardBlue)
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
                } else if let recentlyRestoredRow {
                    restoreBar(title: recentlyRestoredRow.title)
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
            .onChange(of: filter) { _, _ in
                visibleHistoryLimit = Self.pageSize
            }
            .onChange(of: showsDeletedItems) { _, _ in
                visibleHistoryLimit = Self.pageSize
            }
            .onChange(of: searchText) { _, _ in
                visibleHistoryLimit = Self.pageSize
            }
        }
    }

    private func count(for filter: HistoryFilter, among historyRows: [HistoryRow]) -> Int {
        let rows = historyRows.filter { showsDeletedItems || !$0.isRemoved }
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
            recentlyRestoredRow = row
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
        recentlyRestoredRow = nil
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
            Text(locale.localized(
                "‘\(title)’ definitief verwijderd",
                "‘\(title)’ permanently deleted"
            ))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(locale.localized("Ongedaan maken", "Undo"), action: undoPermanentDeletion)
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
            recentlyRestoredRow = nil
        }
    }

    private func restoreBar(title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.blue)
            Text(locale.localized(
                "‘\(title)’ teruggezet",
                "‘\(title)’ restored"
            ))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(locale.localized("Ongedaan maken", "Undo")) {
                undoRestore()
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

    private func undoRestore() {
        guard let row = recentlyRestoredRow else { return }
        row.undoRestore()
        try? modelContext.save()
        hideRestoreBar()
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
            .foregroundStyle(Color.brandHardBlue)
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
    @Environment(\.locale) private var locale

    static let layoutHeight: CGFloat = 193

    let period: HistoryChartPeriod
    let buckets: [HistoryChartBucket]

    private var yMaximum: Double {
        let highest = buckets.map(\.count).max() ?? 0
        return Double(highest + max(1, Int(ceil(Double(highest) * 0.15))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(period.title(for: locale))
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

    func title(for locale: Locale) -> String {
        switch self {
        case .days: locale.localized("Afgelopen 7 dagen", "Last 7 Days")
        case .weeks: locale.localized("Afgelopen 10 weken", "Last 10 Weeks")
        case .months: locale.localized("Afgelopen 12 maanden", "Last 12 Months")
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
    @Environment(\.locale) private var locale
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
        .accessibilityLabel("\(filter.title(for: locale)), \(itemCount) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: filter.icon)
                .font(.system(size: 13.2, weight: .semibold))

            if showsTitle {
                Text(filter.title(for: locale))
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

private struct HistorySearchBar: View {
    @Environment(\.locale) private var locale
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                locale.localized("Zoek in Afgerond", "Search Finished"),
                text: $text
            )
            .font(.system(size: 15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(locale.localized("Zoekopdracht wissen", "Clear search"))
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.045), lineWidth: 1)
        }
    }
}

private struct HistoryDayCard: View {
    @Environment(\.locale) private var locale

    let section: HistoryDaySection
    let searchText: String
    let selectedDeletionRowID: UUID?
    let revealPermanentDelete: (HistoryRow) -> Void
    let permanentlyDelete: (HistoryRow) -> Void
    let restore: (HistoryRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title(for: locale))
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    HistoryItemRow(
                        row: row,
                        searchText: searchText,
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
    @Environment(\.locale) private var locale

    let row: HistoryRow
    let searchText: String
    let showsPermanentDelete: Bool
    let revealPermanentDelete: () -> Void
    let permanentlyDelete: () -> Void
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Button(action: revealPermanentDelete) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(row.backgroundColor)
                    Image(systemName: row.source.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(row.color)
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Acties voor \(row.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(highlightedTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .strikethrough(row.isRemoved)

                HStack(spacing: 5) {
                    Text(row.source.title(for: locale))
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
                        .background(RecurringThemeColorOption.red.backgroundColor, in: Circle())
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
                        .background(row.backgroundColor, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
                .accessibilityLabel(locale.localized(
                    "Zet terug naar \(row.source.title(for: locale))",
                    "Restore to \(row.source.title(for: locale))"
                ))
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Terugzetten", systemImage: "arrow.uturn.backward", action: restore)
            Button("Definitief verwijderen", systemImage: "trash", role: .destructive, action: permanentlyDelete)
        }
    }

    private var highlightedTitle: AttributedString {
        var title = AttributedString(row.title)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return title
        }

        var searchRange = row.title.startIndex..<row.title.endIndex
        while let match = row.title.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            range: searchRange,
            locale: locale
        ) {
            if let attributedMatch = Range(match, in: title) {
                title[attributedMatch].backgroundColor = Color.brandLightBlue
                title[attributedMatch].foregroundColor = Color.brandHardBlue
                title[attributedMatch].font = .system(size: 15, weight: .semibold)
            }
            searchRange = match.upperBound..<row.title.endIndex
        }

        return title
    }
}

private struct HistoryEmptyState: View {
    @Environment(\.locale) private var locale

    let filter: HistoryFilter
    let hasSearchQuery: Bool

    private var title: String {
        if hasSearchQuery {
            return locale.localized("Geen zoekresultaten", "No search results")
        }
        if filter == .all {
            return locale.localized("Nog niets afgerond", "Nothing finished yet")
        }
        return locale.localized(
            "Geen afgeronde \(filter.title(for: locale).lowercased())-items",
            "No completed \(filter.title(for: locale).lowercased()) items"
        )
    }

    private var subtitle: String {
        hasSearchQuery
            ? locale.localized(
                "Probeer een andere zoekopdracht of wis de zoekbalk.",
                "Try another search or clear the search bar."
            )
            : locale.localized(
                "Afgeronde items verschijnen hier automatisch en kun je altijd weer terugzetten.",
                "Completed items appear here automatically and can always be restored."
            )
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(filter.backgroundColor)
                Image(systemName: hasSearchQuery ? "magnifyingglass" : (filter == .all ? "clock.arrow.circlepath" : filter.icon))
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(filter.color)
            }
            .frame(width: 62, height: 62)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
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

    func title(for locale: Locale) -> String {
        if AppCalendar.calendar.isDateInToday(date) { return locale.localized("Vandaag", "Today") }
        if AppCalendar.calendar.isDateInYesterday(date) { return locale.localized("Gisteren", "Yesterday") }
        return AppCalendar.localizedDate(date, template: "EEEEdMMMM")
    }

}

private enum HistorySource {
    case agenda
    case recurring
    case todo

    func title(for locale: Locale) -> String {
        switch self {
        case .agenda: locale.localized("Agenda", "Calendar")
        case .recurring: locale.localized("Herhalingen", "Recurring")
        case .todo: locale.localized("Taken", "Tasks")
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
    let backgroundColor: Color
    let isDone: Bool
    let isRemoved: Bool
    private let originalCompletedAt: Date?
    private let entry: DayEntry?
    private let todo: TodoItem?

    init(entry: DayEntry, source: HistorySource, color: Color, backgroundColor: Color) {
        id = entry.id
        title = entry.rawText
        self.source = source
        completedAt = entry.completedAt ?? entry.date
        self.color = color
        self.backgroundColor = backgroundColor
        isDone = entry.isDone
        isRemoved = entry.isRemoved
        originalCompletedAt = entry.completedAt
        self.entry = entry
        todo = nil
    }

    init(todo: TodoItem, color: Color, backgroundColor: Color) {
        id = todo.id
        title = todo.text
        source = .todo
        completedAt = todo.completedAt ?? todo.createdAt
        self.color = color
        self.backgroundColor = backgroundColor
        isDone = todo.isDone
        isRemoved = todo.isRemoved
        originalCompletedAt = todo.completedAt
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

    func undoRestore() {
        entry?.isDone = isDone
        entry?.isRemoved = isRemoved
        entry?.completedAt = originalCompletedAt
        todo?.isDone = isDone
        todo?.isRemoved = isRemoved
        todo?.completedAt = originalCompletedAt
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
