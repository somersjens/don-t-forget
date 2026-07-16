#if os(macOS)
import AppKit
import Charts
import CloudKit
import SwiftData
import SwiftUI

private enum OpenSinceMacMenuIcon {
    /// A menu item title is positioned from an image's intrinsic size. Keep
    /// this equal to the standard AppKit menu-icon slot instead of relying on
    /// SwiftUI scaling, which AppKit ignores when it builds an NSMenu.
    static func make(text: String, color: Color) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let maximumPointSize: CGFloat = 9
        let maximumWidth = size.width - 1
        let baseFont = NSFont.monospacedDigitSystemFont(
            ofSize: maximumPointSize,
            weight: .semibold
        )
        let baseWidth = (text as NSString).size(withAttributes: [.font: baseFont]).width
        let pointSize = maximumPointSize * min(1, maximumWidth / max(baseWidth, 1))
        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(color),
            .paragraphStyle: paragraph
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            in: NSRect(
                x: 0,
                y: (size.height - textSize.height) / 2,
                width: size.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
        image.isTemplate = false
        return image
    }
}

extension Notification.Name {
    static let macCreateItem = Notification.Name("mac.createItem")
    static let macUndoAgendaAction = Notification.Name("mac.undoAgendaAction")
    static let macSearchScrollRequest = Notification.Name("mac.searchScrollRequest")
    static let macAgendaUndoAvailability = Notification.Name("mac.agendaUndoAvailability")
}

private extension View {
    @ViewBuilder
    func macInteractiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

enum MacSection: String, CaseIterable, Identifiable {
    case agenda, todo, recurring, history

    var id: Self { self }
    func title(for locale: Locale) -> String {
        switch self {
        case .agenda: AppSection.agenda.title(for: locale)
        case .todo: AppSection.todo.title(for: locale)
        case .recurring: AppSection.recurring.title(for: locale)
        case .history: AppSection.history.title(for: locale)
        }
    }
    var icon: String {
        switch self {
        case .agenda: "calendar"
        case .todo: "checklist"
        case .recurring: "repeat"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct MacRootView: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query private var dayEntries: [DayEntry]
    @Query private var todos: [TodoItem]
    @Query private var recurringItems: [RecurringItem]

    @AppStorage(SettingsKeys.defaultColorCombinationEnabled)
    private var defaultColorCombinationEnabled = true

    @State private var section: MacSection = .agenda
    @State private var selection: UUID?
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var currentSearchMatch = 0
    @State private var macAgendaCanUndo = false
    @FocusState private var isSearchFocused: Bool
    @State private var persistenceError: String?
    @State private var hasAppliedInitialWindowSize = false
    @State private var hasLoadedRecurringBoard = false
    @State private var appActivityState = AppActivityState.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar

            itemList
        }
        .overlay(alignment: .bottom) {
            bottomNavigation
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(Color.appCanvasBackground)
        .onAppear(perform: applyInitialWindowSize)
        .inspector(isPresented: inspectorPresented) {
            detail
                .inspectorColumnWidth(min: 300, ideal: 350, max: 440)
        }
        .onChange(of: section) { _, _ in
            selection = nil
            currentSearchMatch = 0
            macAgendaCanUndo = false
        }
        .onChange(of: searchText) { _, _ in
            currentSearchMatch = 0
            requestSearchScroll()
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && normalizedSearch.isEmpty && isSearchPresented { closeSearch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macCreateItem)) { _ in
            createItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macAgendaUndoAvailability)) { note in
            macAgendaCanUndo = note.object as? Bool ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: .persistenceSaveFailed)) { note in
            persistenceError = note.userInfo?[PersistenceSafety.errorUserInfoKey] as? String
        }
        .alert("Bewaren mislukt", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "")
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { if !$0 { selection = nil } }
        )
    }

    private func applyInitialWindowSize() {
        guard !hasAppliedInitialWindowSize else { return }
        hasAppliedInitialWindowSize = true
        Task { @MainActor in
            await Task.yield()
            guard let window = NSApp.keyWindow else { return }
            window.setContentSize(NSSize(width: 480, height: max(520, window.contentLayoutRect.height)))
        }
    }

    private var topBar: some View {
        let canReturn = selection != nil || (section == .agenda && macAgendaCanUndo)
        return VStack(spacing: 0) {
        ZStack {
            Text(section.title(for: locale))
                .font(.system(size: 22, weight: .semibold))
            HStack {
                Group {
                    if appActivityState.isActive {
                        AppActivitySpinner(controlSize: .small)
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial, in: Circle())
                            .accessibilityLabel("App is bezig")
                    } else {
                        Button(action: finishEditing) {
                            Image(systemName: "return")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(headerButtonBackground(isActive: canReturn), in: Circle())
                                .overlay { Circle().stroke(headerButtonBorder(isActive: canReturn), lineWidth: 1.5) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canReturn ? Color.brandHardBlue : Color.secondary.opacity(0.65))
                        .disabled(!canReturn)
                        .help("Terug")
                    }
                }
                Spacer()
                Button(action: toggleSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(headerButtonBackground(isActive: isSearchPresented), in: Circle())
                        .overlay { Circle().stroke(headerButtonBorder(isActive: isSearchPresented), lineWidth: 1.5) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandHardBlue)
                .help(isSearchPresented ? "Zoeken sluiten" : "Zoeken")
            }
        }
        .padding(.horizontal, 29)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, isSearchPresented ? 8 : 12)
        .background(Color.appCanvasBackground)
        if isSearchPresented {
            InlineMatchSearchBar(
                text: $searchText,
                isFocused: $isSearchFocused,
                matchCount: searchMatchIDs.count,
                currentMatch: currentSearchMatch,
                next: showNextSearchMatch,
                clear: clearSearch
            )
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .background(Color.appCanvasBackground)
        }
        }
    }

    private func headerButtonBackground(isActive: Bool) -> Color {
        .white
    }

    private func headerButtonBorder(isActive: Bool) -> Color {
        isActive ? Color.brandHardBlue : Color.primary.opacity(0.10)
    }

    private func toggleSearch() {
        if isSearchPresented { closeSearch() }
        else {
            isSearchPresented = true
            Task { @MainActor in isSearchFocused = true }
        }
    }

    private func closeSearch() {
        searchText = ""
        currentSearchMatch = 0
        isSearchFocused = false
        isSearchPresented = false
    }

    private func clearSearch() {
        searchText = ""
        currentSearchMatch = 0
        Task { @MainActor in isSearchFocused = true }
    }

    private func showNextSearchMatch() {
        guard !searchMatchIDs.isEmpty else { return }
        currentSearchMatch = (currentSearchMatch + 1) % searchMatchIDs.count
        requestSearchScroll()
    }

    private func requestSearchScroll() {
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(name: .macSearchScrollRequest, object: currentSearchMatchID)
        }
    }

    private func finishEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if section == .agenda {
            NotificationCenter.default.post(name: .macUndoAgendaAction, object: nil)
        } else {
            selection = nil
        }
    }

    private var bottomNavigation: some View {
        HStack(spacing: 5) {
            ForEach(MacSection.allCases) { item in
                Button {
                    selectSection(item)
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolVariant(section == item ? .fill : .none)
                        .foregroundStyle(section == item ? Color.brandHardBlue : Color.primary.opacity(0.72))
                        .frame(width: 58, height: 40)
                        .contentShape(Capsule())
                        .background {
                            if section == item {
                                Capsule()
                                    .fill(Color.brandHardBlue.opacity(0.14))
                                    .macInteractiveGlass(in: Capsule())
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title(for: locale))
                .help(item.title(for: locale))
            }
        }
        .padding(6)
        .macInteractiveGlass(in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 14, y: 7)
    }

    @ViewBuilder
    private var itemList: some View {
        ZStack {
            nonRecurringItemList

            if hasLoadedRecurringBoard || section == .recurring {
                MacRecurringBoard(searchText: searchText, currentMatchID: currentSearchMatchID, selection: $selection)
                    .opacity(section == .recurring ? 1 : 0)
                    .allowsHitTesting(section == .recurring)
                    .accessibilityHidden(section != .recurring)
                    .zIndex(section == .recurring ? 1 : 0)
            }
        }
        // The search bar already owns 8 pt of bottom spacing. Keep the same
        // visual gap below the regular header without stacking both insets
        // while search is presented.
        .padding(.top, isSearchPresented ? 0 : 8)
    }

    @ViewBuilder
    private var nonRecurringItemList: some View {
        switch section {
        case .agenda:
            MacCalendarView(entries: agendaItems, searchText: searchText, currentMatchID: currentSearchMatchID, selection: $selection)
        case .todo:
            MacTodoBoard(searchText: searchText, currentMatchID: currentSearchMatchID, selection: $selection)
        case .history:
            MacHistoryBoard(searchText: searchText, currentMatchID: currentSearchMatchID)
        case .recurring:
            EmptyView()
        }
    }

    private func selectSection(_ newSection: MacSection) {
        guard newSection != section else { return }
        if newSection == .recurring { hasLoadedRecurringBoard = true }
        // Keep navigation immediate: animating replacement of a complete board
        // makes SwiftUI diff every row before the tab press visually completes.
        section = newSection
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = dayEntries.first(where: { $0.id == selection }) {
            MacDayEntryEditor(entry: entry)
        } else if let todo = todos.first(where: { $0.id == selection }) {
            MacTodoEditor(todo: todo)
        } else if let item = recurringItems.first(where: { $0.id == selection }) {
            MacRecurringEditor(item: item)
        } else {
            EmptyView()
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchMatchIDs: [UUID] {
        guard !normalizedSearch.isEmpty else { return [] }
        switch section {
        case .agenda:
            return agendaItems.filter { matchesSearch($0.rawText) }.map(\.id)
        case .todo:
            return todoItems.filter { matchesSearch($0.text) }.map(\.id)
        case .recurring:
            return activeRecurringItems.filter { matchesSearch($0.title + " " + $0.notes) }.map(\.id)
        case .history:
            let dayIDs = historyDayEntries.filter { matchesSearch($0.rawText) }.map(\.id)
            let todoIDs = historyTodos.filter { matchesSearch($0.text) }.map(\.id)
            let recurringIDs = historyRecurringItems.filter { matchesSearch($0.title + " " + $0.notes) }.map(\.id)
            return dayIDs + todoIDs + recurringIDs
        }
    }

    private var currentSearchMatchID: UUID? {
        searchMatchIDs.indices.contains(currentSearchMatch) ? searchMatchIDs[currentSearchMatch] : nil
    }

    private var agendaItems: [DayEntry] {
        dayEntries
            .filter { !$0.isDone && !$0.isRemoved }
            .sorted { ($0.date, $0.manualOrder) < ($1.date, $1.manualOrder) }
    }

    private var todoItems: [TodoItem] {
        todos
            .filter { !$0.isDone && !$0.isRemoved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeRecurringItems: [RecurringItem] {
        recurringItems
            .filter { !$0.isRemoved }
            .sorted { $0.nextDate < $1.nextDate }
    }

    private var historyDayEntries: [DayEntry] {
        dayEntries
            .filter { $0.isDone || $0.isRemoved }
            .sorted { ($0.completedAt ?? $0.date) > ($1.completedAt ?? $1.date) }
    }

    private var historyTodos: [TodoItem] {
        todos
            .filter { $0.isDone || $0.isRemoved }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private var historyRecurringItems: [RecurringItem] {
        recurringItems
            .filter(\.isRemoved)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private func matchesSearch(_ value: String) -> Bool {
        value.localizedStandardContains(normalizedSearch)
    }

    @ViewBuilder
    private func emptyState(_ isEmpty: Bool, _ title: String, _ image: String) -> some View {
        if isEmpty {
            ContentUnavailableView.search(text: normalizedSearch)
                .opacity(normalizedSearch.isEmpty ? 0 : 1)
                .overlay {
                    if normalizedSearch.isEmpty {
                        ContentUnavailableView(title, systemImage: image)
                    }
                }
        }
    }

    private func createItem() {
        switch section {
        case .agenda:
            let item = DayEntry(date: .now)
            modelContext.insert(item)
            selection = item.id
        case .todo:
            let item = TodoItem()
            modelContext.insert(item)
            selection = item.id
        case .recurring:
            let item = RecurringItem(nextDate: .now)
            modelContext.insert(item)
            selection = item.id
        case .history:
            return
        }
        PersistenceSafety.save(modelContext)
    }

    private func removeSelection() {
        guard let selection else { return }
        if let item = dayEntries.first(where: { $0.id == selection }) {
            item.isRemoved = true
            item.completedAt = .now
        } else if let item = todos.first(where: { $0.id == selection }) {
            item.isRemoved = true
            item.completedAt = .now
        } else if let item = recurringItems.first(where: { $0.id == selection }) {
            item.isRemoved = true
            item.completedAt = .now
        }
        PersistenceSafety.save(modelContext)
        self.selection = nil
    }
}

private enum MacHistoryFilter: String, CaseIterable, Identifiable {
    case all = "Alles", agenda = "Agenda", todo = "Taken", recurring = "Herhalingen"
    var id: Self { self }
    func title(for locale: Locale) -> String { locale.localized(rawValue) }
    var icon: String {
        switch self { case .all: "square.grid.2x2"; case .agenda: "calendar"; case .recurring: "repeat"; case .todo: "checklist" }
    }
    var color: Color {
        switch self { case .all: .brandHardBlue; case .agenda: .blue; case .recurring: .orange; case .todo: .green }
    }
}

private enum MacHistorySource { case agenda, recurring, todo }

private struct MacHistoryItem: Identifiable {
    let id: UUID
    let title: String
    let source: MacHistorySource
    let category: String
    let completedAt: Date
    let isDone: Bool
    let isRemoved: Bool
    let color: Color
    let entry: DayEntry?
    let todo: TodoItem?
    let recurring: RecurringItem?

    var filter: MacHistoryFilter {
        switch source { case .agenda: .agenda; case .recurring: .recurring; case .todo: .todo }
    }
    var icon: String {
        switch source { case .agenda: "calendar"; case .recurring: "repeat"; case .todo: "checklist" }
    }
    func restore() {
        entry?.isDone = false; entry?.isRemoved = false; entry?.completedAt = nil
        todo?.isDone = false; todo?.isRemoved = false; todo?.completedAt = nil
        recurring?.isRemoved = false; recurring?.completedAt = nil
    }
    func delete(in context: ModelContext) {
        if let entry {
            let entries = (try? context.fetch(FetchDescriptor<DayEntry>())) ?? []
            CalendarSyncService.deleteEventIfUnshared(for: entry, among: entries)
            context.delete(entry)
        }
        if let todo { context.delete(todo) }
        if let recurring { context.delete(recurring) }
    }
}

private struct MacHistoryChartBucket: Identifiable {
    let start: Date
    let label: String
    let count: Int
    let isCurrent: Bool

    var id: Date { start }
}

private enum MacHistoryChartPeriod: String, Identifiable {
    case days
    case weeks
    case months

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .days: locale.localized("Afgelopen 7 dagen")
        case .weeks: locale.localized("Afgelopen 10 weken")
        case .months: locale.localized("Afgelopen 12 maanden")
        }
    }

    // Keep these thresholds aligned with the iOS history charts.
    static func available(for dates: [Date]) -> [MacHistoryChartPeriod] {
        var periods: [MacHistoryChartPeriod] = [.days]
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

    func buckets(for dates: [Date]) -> [MacHistoryChartBucket] {
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
            return MacHistoryChartBucket(
                start: start,
                label: label(for: start, calendar: calendar),
                count: dates.count { $0 >= start && $0 < end },
                isCurrent: index == numberOfBuckets - 1
            )
        }
    }

    private func label(for date: Date, calendar: Calendar) -> String {
        switch self {
        case .days: AppCalendar.localizedDate(date, template: "EEE")
        case .weeks: "w\(calendar.component(.weekOfYear, from: date))"
        case .months: AppCalendar.localizedDate(date, template: "MMM")
        }
    }
}

private struct MacHistoryCharts: View {
    let completionDates: [Date]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(MacHistoryChartPeriod.available(for: completionDates)) { period in
                MacHistoryBarChart(period: period, buckets: period.buckets(for: completionDates))
            }
        }
    }
}

private struct MacHistoryBarChart: View {
    @Environment(\.locale) private var locale

    static let layoutHeight: CGFloat = 200

    let period: MacHistoryChartPeriod
    let buckets: [MacHistoryChartBucket]

    private var yMaximum: Double {
        let highest = buckets.map(\.count).max() ?? 0
        return Double(highest + max(1, Int(ceil(Double(highest) * 0.15))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(period.title(for: locale))
                .font(.headline)

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
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .chartXScale(domain: buckets.map(\.label))
            .chartYScale(domain: 0...yMaximum)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 136)
        }
        .padding(12)
        .background(
            Color.appThemeColor(lightBlue: .brandCanvasBlue, gray: .clear),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .frame(height: Self.layoutHeight, alignment: .top)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

private struct MacHistoryBoard: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<DayEntry> { $0.isDone || $0.isRemoved }) private var entries: [DayEntry]
    @Query(filter: #Predicate<TodoItem> { $0.isDone || $0.isRemoved }) private var todos: [TodoItem]
    @Query(filter: #Predicate<RecurringItem> { $0.isRemoved }) private var recurringItems: [RecurringItem]
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""
    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.historyShowsDeletedItems) private var showsDeletedItems = true

    let searchText: String
    let currentMatchID: UUID?
    @State private var filter = MacHistoryFilter.all
    @State private var restored: MacHistoryItem?
    @State private var pendingDeletion: MacHistoryItem?
    @State private var dismissTask: Task<Void, Never>?
    @State private var deletionTask: Task<Void, Never>?
    @State private var isChartExpanded = false

    private var todoGroups: [MacTodoGroup] { MacTodoGroupStore.decode(todoGroupsData) }
    private var recurringGroups: [MacRecurringCategory] { MacRecurringCategoryStore.decode(recurringCategoriesData) }
    private var items: [MacHistoryItem] {
        let todoMap = Dictionary(uniqueKeysWithValues: todoGroups.map { ($0.id, $0) })
        let recurringMap = Dictionary(uniqueKeysWithValues: recurringGroups.map { ($0.id, $0) })
        let dayItems = entries.map { entry in
            let recurring = entry.source == .recurring
            let group = recurring ? recurringMap[entry.accentRawValue] : nil
            return MacHistoryItem(id: entry.id, title: entry.rawText, source: recurring ? .recurring : .agenda,
                category: group?.title ?? locale.localized(recurring ? "Herhalingen" : "Agenda"), completedAt: entry.completedAt ?? entry.date,
                isDone: entry.isDone, isRemoved: entry.isRemoved, color: group?.color ?? (recurring ? .orange : .blue), entry: entry, todo: nil, recurring: nil)
        }
        let todoItems = todos.map { todo in
            let group = todoMap[todo.bucketRawValue]
            return MacHistoryItem(id: todo.id, title: todo.text, source: .todo, category: group?.title ?? locale.localized("Taken"),
                completedAt: todo.completedAt ?? todo.createdAt, isDone: todo.isDone, isRemoved: todo.isRemoved, color: group?.color ?? .green,
                entry: nil, todo: todo, recurring: nil)
        }
        let removedRecurring = recurringItems.map { item in
            let group = recurringMap[item.themeRawValue]
            return MacHistoryItem(id: item.id, title: item.title, source: .recurring, category: group?.title ?? locale.localized("Herhalingen"),
                completedAt: item.completedAt ?? item.createdAt, isDone: false, isRemoved: true, color: group?.color ?? .orange,
                entry: nil, todo: nil, recurring: item)
        }
        return (dayItems + todoItems + removedRecurring).sorted { $0.completedAt > $1.completedAt }
    }
    private var visibleItems: [MacHistoryItem] {
        items.filter {
            $0.id != pendingDeletion?.id &&
            (showsDeletedItems || !$0.isRemoved) &&
            (filter == .all || $0.filter == filter)
        }
    }
    private var sections: [(Date, [MacHistoryItem])] {
        Dictionary(grouping: visibleItems) { AppCalendar.startOfDay($0.completedAt) }.sorted { $0.key > $1.key }
    }
    private var filteredItems: [MacHistoryItem] { items.filter { filter == .all || $0.filter == filter } }
    private var completedItems: [MacHistoryItem] { filteredItems.filter { !$0.isRemoved } }
    private var chartPeriods: [MacHistoryChartPeriod] {
        MacHistoryChartPeriod.available(for: completedItems.map(\.completedAt))
    }
    private var chartsHeight: CGFloat {
        28 + (CGFloat(chartPeriods.count) * MacHistoryBarChart.layoutHeight) + (CGFloat(max(0, chartPeriods.count - 1)) * 18)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 14) {
                controls
                summary
                if visibleItems.isEmpty { ContentUnavailableView("Nog niets afgerond", systemImage: "clock.arrow.circlepath") }
                ForEach(sections, id: \.0) { date, rows in
                    dayCard(date: date, rows: rows)
                        .id(date)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: currentMatchID) { _, id in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
        }
        .onChange(of: searchText) { _, _ in
            guard let id = currentMatchID else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSearchScrollRequest)) { note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in
                if let item = visibleItems.first(where: { $0.id == id }) {
                    proxy.scrollTo(AppCalendar.startOfDay(item.completedAt), anchor: .center)
                }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
                try? await Task.sleep(for: .milliseconds(260))
                proxy.scrollTo(id, anchor: .center)
            }
        }
        }
        .background(Color.appCanvasBackground)
        .animation(.easeInOut(duration: 0.18), value: filter)
        .animation(.easeInOut(duration: 0.18), value: showsDeletedItems)
        .safeAreaInset(edge: .bottom) {
            if let pendingDeletion { deletionUndoBar(pendingDeletion) }
            else if let restored { undoBar(restored) }
        }
        .onDisappear { commitPendingDeletion() }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(MacHistoryFilter.allCases) { item in
                Button { filter = item } label: {
                    HStack(spacing: 6) {
                        if item == .all { Image(systemName: item.icon) }
                        Text(item.title(for: locale))
                    }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(filter == item ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(
                            filter == item
                                ? Color.brandHardBlue
                                : Color.appThemeColor(
                                    lightBlue: .white,
                                    gray: Color.primary.opacity(0.055)
                                ),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    filter == item
                                        ? Color.clear
                                        : Color.appThemeColor(
                                            lightBlue: Color.appCardOutline,
                                            gray: Color.primary.opacity(0.12)
                                        )
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title(for: locale))
                .help(item.title(for: locale))
                .accessibilityAddTraits(filter == item ? .isSelected : [])
            }
        }
    }

    private var summary: some View {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: AppCalendar.startOfDay(.now)) ?? .now
        let recent = completedItems.filter { $0.completedAt >= start }.count
        return VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { isChartExpanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.brandHardBlue)
                        .frame(width: 34, height: 34)
                        .background(
                            Color.appThemeColor(
                                lightBlue: Color.brandCanvasBlue,
                                gray: Color.brandHardBlue.opacity(0.12)
                            ),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(completedItems.count) afgerond").font(.headline)
                        Text("\(recent) in afgelopen 7 dagen").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 32, height: 32)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(isChartExpanded ? 180 : 0))
                            .frame(width: 32, height: 32)
                    }
                    .foregroundStyle(Color.brandHardBlue)
                    .frame(height: 42)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(14)
            Divider()
                .padding(.horizontal, 14)
                .frame(height: isChartExpanded ? 1 : 0)
                .clipped()
            MacHistoryCharts(completionDates: completedItems.map(\.completedAt))
                .padding(14)
                .frame(height: isChartExpanded ? chartsHeight : 0, alignment: .top)
                .clipped()
        }
        .animation(.snappy(duration: 0.38, extraBounce: 0), value: isChartExpanded)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.appCardOutline) }
    }

    private func dayCard(date: Date, rows: [MacHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dayTitle(date))
                    .font(.headline)
                    .padding(.horizontal, 4)
                Spacer()
                if date == sections.first?.0 {
                    HStack(spacing: 3) {
                        Text("Verwijderde items").font(.caption).foregroundStyle(.secondary)
                        Button { showsDeletedItems.toggle() } label: {
                            Image(systemName: showsDeletedItems ? "checkmark.square.fill" : "square")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(showsDeletedItems ? Color.brandHardBlue : Color.secondary)
                                .frame(width: 28, height: 28)
                        }.buttonStyle(.plain).help("Toon ook items die eerder zijn verwijderd")
                    }
                    .padding(.trailing, 16)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    historyRow(item)
                    if index < rows.count - 1 { Divider().padding(.leading, 64) }
                }
            }
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.appCardOutline) }
        }
    }

    private func historyRow(_ item: MacHistoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon).foregroundStyle(item.color).frame(width: 34, height: 34).background(item.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).strikethrough(item.isRemoved).lineLimit(2)
                Text("\(item.category) · \(item.completedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { restore(item) } label: { Label("Terugzetten", systemImage: "arrow.uturn.backward").labelStyle(.iconOnly) }
                .buttonStyle(.plain)
                .foregroundStyle(item.color)
                .frame(width: 32, height: 32)
                .background(item.color.opacity(0.14), in: Circle())
                .overlay { Circle().stroke(item.color.opacity(0.2)) }
                .help(locale.localizedFormat("Terugzetten naar %@", item.filter.title(for: locale)))
            Button { beginDeletion(item) } label: { Label("Definitief verwijderen", systemImage: "trash").labelStyle(.iconOnly) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
                .frame(width: 32, height: 32)
                .background(Color.red.opacity(0.12), in: Circle())
                .overlay { Circle().stroke(Color.red.opacity(0.18)) }
                .help("Definitief verwijderen")
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .id(item.id)
            .modifier(SearchMatchHighlight(
                isMatch: !searchText.isEmpty && (item.title + " " + item.category).localizedCaseInsensitiveContains(searchText),
                isCurrent: currentMatchID == item.id
            ))
            .contentShape(Rectangle())
            .contextMenu { actions(for: item) }
            .help("\(item.title) — \(item.completedAt.formatted(date: .long, time: .shortened))")
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func actions(for item: MacHistoryItem) -> some View {
        Button("Terugzetten", systemImage: "arrow.uturn.backward") { restore(item) }
        Divider()
        Button("Definitief verwijderen", systemImage: "trash", role: .destructive) { beginDeletion(item) }
    }
    private func dayTitle(_ date: Date) -> String {
        if AppCalendar.calendar.isDateInToday(date) { return locale.localized("Vandaag") }
        if AppCalendar.calendar.isDateInYesterday(date) { return locale.localized("Gisteren") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }
    private func restore(_ item: MacHistoryItem) {
        dismissTask?.cancel(); item.restore(); restored = item; PersistenceSafety.save(modelContext)
        dismissTask = Task { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { await MainActor.run { restored = nil } } }
    }
    private func undoRestore(_ item: MacHistoryItem) {
        if let entry = item.entry { entry.isDone = item.isDone; entry.isRemoved = item.isRemoved; entry.completedAt = item.completedAt }
        if let todo = item.todo { todo.isDone = item.isDone; todo.isRemoved = item.isRemoved; todo.completedAt = item.completedAt }
        if let recurring = item.recurring { recurring.isRemoved = true; recurring.completedAt = item.completedAt }
        dismissTask?.cancel(); restored = nil; PersistenceSafety.save(modelContext)
    }
    private func beginDeletion(_ item: MacHistoryItem) {
        commitPendingDeletion()
        dismissTask?.cancel(); restored = nil
        pendingDeletion = item
        deletionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            commitPendingDeletion()
        }
    }
    private func undoDeletion() { deletionTask?.cancel(); deletionTask = nil; pendingDeletion = nil }
    private func commitPendingDeletion() {
        deletionTask?.cancel(); deletionTask = nil
        guard let item = pendingDeletion else { return }
        item.delete(in: modelContext); pendingDeletion = nil; PersistenceSafety.save(modelContext)
    }
    private func count(for filter: MacHistoryFilter) -> Int {
        items.count { (showsDeletedItems || !$0.isRemoved) && (filter == .all || $0.filter == filter) }
    }
    private func undoBar(_ item: MacHistoryItem) -> some View {
        HStack { Label("‘\(item.title)’ teruggezet", systemImage: "arrow.uturn.backward.circle.fill").lineLimit(1); Spacer(); Button("Ongedaan maken") { undoRestore(item) }.buttonStyle(.borderedProminent) }
            .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 18).padding(.bottom, 8)
    }
    private func deletionUndoBar(_ item: MacHistoryItem) -> some View {
        HStack { Label("‘\(item.title)’ verwijderd", systemImage: "trash.fill").lineLimit(1); Spacer(); Button("Terughalen") { undoDeletion() }.buttonStyle(.borderedProminent) }
            .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 18).padding(.bottom, 8)
    }
}

private struct MacTodoGroup: Codable, Identifiable {
    var id: String
    var title: String
    var icon: String
    var colorRawValue: String?
    var color: Color { RecurringThemeColorOption(rawValue: colorRawValue ?? "")?.color ?? .blue }
    var backgroundColor: Color { RecurringThemeColorOption(rawValue: colorRawValue ?? "")?.backgroundColor ?? .blue.opacity(0.18) }
}

private enum MacTodoGroupStore {
    static func decode(_ value: String) -> [MacTodoGroup] {
        if let data = value.data(using: .utf8), let groups = try? JSONDecoder().decode([MacTodoGroup].self, from: data), !groups.isEmpty { return groups }
        return [
            MacTodoGroup(id: TodoBucket.shortTerm.rawValue, title: "Binnenkort", icon: "bolt.fill", colorRawValue: "orange"),
            MacTodoGroup(id: TodoBucket.longTerm.rawValue, title: "Voor later", icon: "mountain.2.fill", colorRawValue: "indigo"),
            MacTodoGroup(id: "shopping", title: "Boodschappen", icon: "cart.fill", colorRawValue: "green")
        ]
    }
    static func encode(_ groups: [MacTodoGroup]) -> String {
        guard let data = try? JSONEncoder().encode(groups) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct MacTodoAgendaUndo {
    let entryID: UUID
    let date: Date
    let text: String
    let groupID: String
    let showOnWidget: Bool
    let createdAt: Date
}

private enum MacTodoFeedback {
    case completed(TodoItem)
    case removed(TodoItem, String)
    case agenda(MacTodoAgendaUndo)
}

private struct MacTodoBoard: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TodoItem> { !$0.isDone && !$0.isRemoved }, sort: \TodoItem.createdAt)
    private var todos: [TodoItem]
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""

    let searchText: String
    let currentMatchID: UUID?
    @Binding var selection: UUID?
    @State private var newGroupTitle = ""
    @State private var drafts: [String: String] = [:]
    @State private var feedback: MacTodoFeedback?
    @State private var dismissUndoTask: Task<Void, Never>?
    @State private var agendaTodo: TodoItem?
    @State private var agendaDate = AppCalendar.startOfDay(.now)
    @State private var openSinceTodo: TodoItem?
    @State private var openDaysDraft = 0
    @FocusState private var focusedNewTodoGroupID: String?
    @FocusState private var isOpenDaysFocused: Bool

    private var groups: [MacTodoGroup] {
        get { MacTodoGroupStore.decode(todoGroupsData) }
        nonmutating set { todoGroupsData = MacTodoGroupStore.encode(newValue) }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(visibleGroupEntries, id: \.element.id) { index, group in
                    groupCard(group, index: index)
                        .id(group.id)
                }
                if searchText.isEmpty { newGroupRow }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: currentMatchID) { _, id in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
        }
        .onChange(of: searchText) { _, _ in
            guard let id = currentMatchID else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSearchScrollRequest)) { note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in
                if let todo = todos.first(where: { $0.id == id }) {
                    proxy.scrollTo(todo.bucketRawValue, anchor: .center)
                }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
                try? await Task.sleep(for: .milliseconds(260))
                proxy.scrollTo(id, anchor: .center)
            }
        }
        }
        .background(Color.appCanvasBackground)
        .safeAreaInset(edge: .bottom) {
            if let feedback {
                HStack {
                    Label(feedbackText(feedback), systemImage: feedbackIcon(feedback))
                        .lineLimit(1)
                    Spacer()
                    Button("Ongedaan maken") { undoFeedback() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
        .onAppear(perform: repairUnknownGroups)
        .sheet(item: $agendaTodo) { todo in
            VStack(spacing: 16) {
                Text(locale.localized("todo.agendaDate.title")).font(.title2.bold())
                Text(todo.text).foregroundStyle(.secondary).lineLimit(2)
                DatePicker(locale.localized("todo.agendaDate.date"), selection: $agendaDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                HStack {
                    Button(locale.localized("todo.openSince.cancel"), role: .cancel) { agendaTodo = nil }
                    Spacer()
                    Button(locale.localized("todo.agendaDate.move")) { moveToAgenda(todo, date: agendaDate) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 390)
        }
        .sheet(item: $openSinceTodo) { todo in
            VStack(alignment: .leading, spacing: 18) {
                Text(locale.localized("todo.openSince"))
                    .font(.title3.bold())
                Text(locale.localized("todo.openSince.days"))
                    .font(.headline)
                TextField("", value: $openDaysDraft, format: .number)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .focused($isOpenDaysFocused)
                HStack {
                    Button(locale.localized("todo.openSince.cancel"), role: .cancel) {
                        openSinceTodo = nil
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(locale.localized("todo.openSince.save")) {
                        setOpenDays(openDaysDraft, for: todo)
                        openSinceTodo = nil
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    private var visibleGroupEntries: [(offset: Int, element: MacTodoGroup)] {
        Array(groups.enumerated())
    }

    private func groupCard(_ group: MacTodoGroup, index: Int) -> some View {
        let items = todos.filter { $0.bucketRawValue == group.id }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(group.backgroundColor)
                        Image(systemName: group.icon)
                            .foregroundStyle(group.color)
                    }
                    .frame(width: 32, height: 32)

                    Menu {
                        groupAppearanceMenu(group)
                    } label: {
                        Color.clear
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(group.color)
                }
                .frame(width: 32, height: 32)
                .help("Icoon en kleur wijzigen")
                VStack(alignment: .leading, spacing: 1) {
                    TextField("Groepsnaam", text: titleBinding(for: group.id))
                        .textFieldStyle(.plain)
                        .font(.headline)
                    Text(items.count == 1 ? "1 open" : "\(items.count) open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                groupMenu(group, index: index, isEmpty: items.isEmpty)
            }
            .padding(12)

            Divider()

            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(items) { todo in
                        todoRow(todo, group: group)
                    }
                }
                .padding(.top, items.isEmpty ? 0 : 6)
            }

            HStack(spacing: 10) {
                Button {
                    focusedNewTodoGroupID = group.id
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Nieuwe taak invoeren")
                TextField("Nieuwe taak", text: draftBinding(for: group.id))
                    .textFieldStyle(.plain)
                    .focused($focusedNewTodoGroupID, equals: group.id)
                    .onSubmit { addTodo(to: group.id, continueEditing: false) }
                    .onKeyPress(.tab) {
                        addTodo(to: group.id, continueEditing: true)
                        return .handled
                    }
                    .onChange(of: focusedNewTodoGroupID) { oldValue, newValue in
                        guard oldValue == group.id, newValue != group.id else { return }
                        addTodo(to: group.id, continueEditing: false)
                    }
            }
            .padding(12)
        }
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.appCardOutline) }
    }

    private func todoRow(_ todo: TodoItem, group: MacTodoGroup) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Text(ageBadge(todo.createdAt))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(group.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(group.color.opacity(0.20))
                    }

                Menu { todoActions(todo, group: group) } label: {
                    Color.clear
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(group.color)
            }
            .frame(width: 32, height: 24, alignment: .center)
            .help("Hoe lang open; klik voor verplaatsen")

            TextField("Taak", text: Binding(get: { todo.text }, set: { value in
                todo.text = value.replacingOccurrences(of: "\n", with: "")
                if todo.text.isEmpty {
                    if selection == todo.id { selection = nil }
                    modelContext.delete(todo)
                }
            }), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .onSubmit { save() }
            .onKeyPress(.tab) {
                save()
                drafts[group.id] = ""
                focusedNewTodoGroupID = group.id
                return .handled
            }
            .onChange(of: todo.text) { _, _ in save() }

            Menu { todoActions(todo, group: group) } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(group.color)
                    .frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(group.color)
            .fixedSize()
            .help("Verplaatsen of verwijderen")

            Button { complete(todo) } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(group.color)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .help("Markeer als afgerond")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(minHeight: 24)
        .id(todo.id)
        .modifier(SearchMatchHighlight(
            isMatch: !searchText.isEmpty && todo.text.localizedCaseInsensitiveContains(searchText),
            isCurrent: currentMatchID == todo.id
        ))
    }

    @ViewBuilder
    private func todoActions(_ todo: TodoItem, group: MacTodoGroup) -> some View {
        ForEach(groups.filter { $0.id != group.id }) { destination in
            Button { move(todo, to: destination.id) } label: {
                Label(destination.title, systemImage: destination.icon)
            }
        }
        if groups.count == 1 { Text(locale.localized("todo.menu.noOtherCategories")) }
        Divider()
        Button { moveToAgenda(todo, date: .now) } label: {
            Label(locale.localized("todo.menu.moveToToday"), systemImage: "calendar.badge.checkmark")
        }
        Button {
            agendaDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            agendaTodo = todo
        } label: { Label(locale.localized("todo.menu.otherAgendaDate"), systemImage: "calendar.badge.plus") }
        Divider()
        Button {
            openDaysDraft = openDays(for: todo.createdAt)
            openSinceTodo = todo
            Task { @MainActor in
                await Task.yield()
                isOpenDaysFocused = true
            }
        } label: {
            Label {
                Text(locale.localized("todo.openSince.adjust"))
            } icon: {
                Image(nsImage: OpenSinceMacMenuIcon.make(
                    text: ageBadge(todo.createdAt),
                    color: group.color
                ))
                .renderingMode(.original)
            }
        }
        Divider()
        Button(role: .destructive) { remove(todo) } label: {
            Label(locale.localized("todo.menu.delete"), systemImage: "trash")
        }
    }

    private func groupMenu(_ group: MacTodoGroup, index: Int, isEmpty: Bool) -> some View {
        Menu {
            groupAppearanceMenu(group)
            Divider()
            if index >= 2 {
                Button("Helemaal omhoog", systemImage: "chevron.up.2") { moveGroup(index, to: 0) }
            }
            if index >= 1 {
                Button("Omhoog", systemImage: "arrow.up") { moveGroup(index, by: -1) }
            }
            if index < groups.count - 1 {
                Button("Omlaag", systemImage: "arrow.down") { moveGroup(index, by: 1) }
            }
            if groups.count - 1 - index >= 2 {
                Button("Helemaal omlaag", systemImage: "chevron.down.2") { moveGroup(index, to: groups.count - 1) }
            }
            Divider()
            Button("Verwijder groep", systemImage: "trash", role: .destructive) { deleteGroup(group.id) }
                .disabled(!isEmpty || groups.count == 1)
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(group.color)
                .frame(width: 26, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(group.color)
        .padding(.trailing, 2)
        .offset(x: -7)
    }

    @ViewBuilder
    private func groupAppearanceMenu(_ group: MacTodoGroup) -> some View {
        Menu("Icoon") {
            ForEach(macTodoIcons, id: \.self) { icon in
                Button { updateGroup(group.id) { $0.icon = icon } } label: { Label(icon, systemImage: icon) }
            }
        }
        Menu("Kleur") {
            ForEach(RecurringThemeColorOption.allCases) { color in
                Button { updateGroup(group.id) { $0.colorRawValue = color.rawValue } } label: {
                    Text(color.rawValue.capitalized)
                }
            }
        }
    }

    private var newGroupRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            TextField("Nieuwe groep", text: $newGroupTitle)
                .textFieldStyle(.plain)
                .onSubmit(addGroup)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            Color.appThemeColor(lightBlue: .white, gray: Color.black.opacity(0.07)),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.appCardOutline) }
    }

    private func titleBinding(for id: String) -> Binding<String> {
        Binding(get: { groups.first(where: { $0.id == id })?.title ?? "" }, set: { value in
            updateGroup(id) { $0.title = value }
        })
    }
    private func draftBinding(for id: String) -> Binding<String> {
        Binding(get: { drafts[id, default: ""] }, set: { drafts[id] = $0 })
    }
    private func trimmedDraft(for id: String) -> String {
        drafts[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func addTodo(to groupID: String, continueEditing: Bool) {
        let text = trimmedDraft(for: groupID); guard !text.isEmpty else { return }
        let item = TodoItem(text: text); item.bucketRawValue = groupID
        modelContext.insert(item); drafts[groupID] = ""; save()
        if continueEditing {
            Task { @MainActor in focusedNewTodoGroupID = groupID }
        } else {
            focusedNewTodoGroupID = nil
        }
    }
    private func complete(_ todo: TodoItem) {
        dismissUndoTask?.cancel(); todo.isDone = true; todo.completedAt = .now
        feedback = .completed(todo); selection = nil; save(); scheduleFeedbackDismissal()
    }
    private func remove(_ todo: TodoItem) {
        let title = todo.text; todo.isDone = false; todo.isRemoved = true; todo.completedAt = .now
        feedback = .removed(todo, title); selection = nil; save(); scheduleFeedbackDismissal()
    }
    private func moveToAgenda(_ todo: TodoItem, date: Date) {
        let text = todo.text.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        let entry = DayEntry(date: date, rawText: text, source: .todo)
        let undo = MacTodoAgendaUndo(entryID: entry.id, date: AppCalendar.startOfDay(date), text: text, groupID: todo.bucketRawValue, showOnWidget: todo.showOnWidget, createdAt: todo.createdAt)
        modelContext.insert(entry); modelContext.delete(todo); agendaTodo = nil; selection = nil
        feedback = .agenda(undo); save(); scheduleFeedbackDismissal()
    }
    private func scheduleFeedbackDismissal() {
        dismissUndoTask?.cancel()
        dismissUndoTask = Task { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { await MainActor.run { feedback = nil } } }
    }
    private func undoFeedback() {
        guard let feedback else { return }
        switch feedback {
        case .completed(let todo): todo.isDone = false; todo.completedAt = nil
        case .removed(let todo, _): todo.isDone = false; todo.isRemoved = false; todo.completedAt = nil
        case .agenda(let move):
            let entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
            if let entry = entries.first(where: { $0.id == move.entryID }) { modelContext.delete(entry) }
            let todo = TodoItem(text: move.text); todo.bucketRawValue = move.groupID; todo.showOnWidget = move.showOnWidget; todo.createdAt = move.createdAt; modelContext.insert(todo)
        }
        dismissUndoTask?.cancel(); self.feedback = nil; save()
    }
    private func feedbackText(_ feedback: MacTodoFeedback) -> String {
        switch feedback {
        case .completed(let todo):
            return locale.localizedFormat("feedback.movedToFinished", todo.text)
        case .removed(_, let title):
            return locale.localizedFormat("feedback.deleted", title)
        case .agenda(let move):
            let date = move.date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            return locale.localizedFormat("feedback.movedTo", move.text, date)
        }
    }
    private func feedbackIcon(_ feedback: MacTodoFeedback) -> String {
        switch feedback { case .completed: "checkmark.circle.fill"; case .removed: "trash.fill"; case .agenda: "calendar.badge.checkmark" }
    }
    private func move(_ todo: TodoItem, to id: String) { todo.bucketRawValue = id; save() }
    private func setOpenDays(_ days: Int, for todo: TodoItem) {
        let today = AppCalendar.startOfDay(.now)
        todo.createdAt = AppCalendar.calendar.date(byAdding: .day, value: -max(0, days), to: today) ?? today
        save()
    }
    private func openDays(for date: Date) -> Int {
        max(0, AppCalendar.calendar.dateComponents(
            [.day],
            from: AppCalendar.startOfDay(date),
            to: AppCalendar.startOfDay(.now)
        ).day ?? 0)
    }
    private func addGroup() {
        let title = newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var value = groups; value.append(MacTodoGroup(id: UUID().uuidString, title: title, icon: "list.bullet", colorRawValue: RecurringThemeColorOption.blue.rawValue))
        groups = value; newGroupTitle = ""
    }
    private func updateGroup(_ id: String, mutate: (inout MacTodoGroup) -> Void) {
        var value = groups; guard let index = value.firstIndex(where: { $0.id == id }) else { return }
        mutate(&value[index]); groups = value
    }
    private func moveGroup(_ index: Int, by offset: Int) {
        moveGroup(index, to: index + offset)
    }
    private func moveGroup(_ index: Int, to target: Int) {
        var value = groups
        guard value.indices.contains(index), value.indices.contains(target), index != target else { return }
        let group = value.remove(at: index)
        value.insert(group, at: target)
        groups = value
    }
    private func deleteGroup(_ id: String) {
        guard !todos.contains(where: { $0.bucketRawValue == id }) else { return }
        var value = groups; guard value.count > 1 else { return }; value.removeAll { $0.id == id }; groups = value
    }
    private func repairUnknownGroups() {
        guard let first = groups.first?.id else { return }; let valid = Set(groups.map(\.id)); var changed = false
        for todo in todos where !valid.contains(todo.bucketRawValue) { todo.bucketRawValue = first; changed = true }
        if changed { save() }
    }
    private func openDuration(_ date: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0)
        if days == 0 { return "Sinds vandaag open" }; if days == 1 { return "1 dag open" }; return "\(days) dagen open"
    }
    private func ageBadge(_ date: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0)
        if days == 0 { return "nu" }
        if days < 14 { return "\(days)d" }
        if days < 70 { return "\(days / 7)w" }
        return "\(days / 30)m"
    }

    private func save() { PersistenceSafety.save(modelContext) }
}

private let macTodoIcons = ["checklist", "list.bullet", "flag.fill", "bolt.fill", "mountain.2.fill", "star.fill", "heart.fill", "house.fill", "briefcase.fill", "book.fill", "bell.fill", "clock.fill", "cart.fill", "cross.case.fill", "dumbbell.fill", "wrench.and.screwdriver.fill"]

private struct MacAgendaRow: View {
    let entry: DayEntry
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : "calendar")
                .foregroundStyle(entry.isDone ? .green : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.rawText.isEmpty ? "Nieuw agenda-item" : entry.rawText)
                    .lineLimit(2)
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MacTodoRow: View {
    let todo: TodoItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(todo.isDone ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text.isEmpty ? "Nieuwe taak" : todo.text).lineLimit(2)
                Text(todo.bucketRawValue).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MacRecurringRow: View {
    let item: RecurringItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Nieuw terugkerend item" : item.title).lineLimit(2)
                Text("Volgende: \(item.nextDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MacRecurringCategory: Codable, Identifiable {
    var id: String
    var title: String
    var isFixed: Bool
    var colorRawValue: String
    var iconName: String?

    var color: Color { RecurringThemeColorOption(rawValue: colorRawValue)?.color ?? .gray }
    var backgroundColor: Color { RecurringThemeColorOption(rawValue: colorRawValue)?.backgroundColor ?? .gray.opacity(0.18) }
}

private struct MacRecurringLink: Codable, Identifiable {
    var id: String { url + name }
    var url = ""
    var name = ""
    var destination: URL? {
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let result = URL(string: value), result.scheme != nil { return result }
        return URL(string: "https://\(value)")
    }
    static func decode(_ value: String) -> [MacRecurringLink] {
        guard let data = value.data(using: .utf8) else { return [] }
        if let links = try? JSONDecoder().decode([MacRecurringLink].self, from: data) { return Array(links.prefix(5)) }
        if let links = try? JSONDecoder().decode([String].self, from: data) { return links.prefix(5).map { .init(url: $0) } }
        return []
    }
}

private enum MacRecurringCategoryStore {
    static let birthdayID = RecurringTheme.birthday.rawValue
    static let holidayID = "holidays"

    static var defaults: [MacRecurringCategory] {[
        .init(id: birthdayID, title: "Verjaardagen", isFixed: true, colorRawValue: "blue", iconName: "birthday.cake.fill"),
        .init(id: RecurringTheme.general.rawValue, title: "Algemeen", isFixed: false, colorRawValue: "yellow", iconName: "repeat"),
        .init(id: holidayID, title: "Feestdagen", isFixed: true, colorRawValue: "orange", iconName: "party.popper.fill")
    ] }

    static func decode(_ value: String) -> [MacRecurringCategory] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MacRecurringCategory].self, from: data),
              !decoded.isEmpty else { return defaults }
        return decoded
    }

    static func encode(_ categories: [MacRecurringCategory]) -> String {
        guard let data = try? JSONEncoder().encode(categories) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct MacRecurringDisplayItem: Identifiable {
    let item: RecurringItem
    let nextDate: Date
    var id: UUID { item.id }
}

private struct MacRecurringBoard: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<RecurringItem> { !$0.isRemoved }) private var items: [RecurringItem]
    @AppStorage(SettingsKeys.recurringCategories) private var categoriesData = ""
    @AppStorage(SettingsKeys.recurringShowNextDate) private var showNextDate = true
    @AppStorage(SettingsKeys.recurringSoonestFirst) private var soonestFirst = true
    let searchText: String
    let currentMatchID: UUID?
    @Binding var selection: UUID?
    @State private var newGroupTitle = ""
    @State private var recentlyRemovedItem: RecurringItem?
    @State private var dismissUndoTask: Task<Void, Never>?
    @State private var creatingItem: RecurringItem?
    @State private var isCreatingItem = false
    @State private var showsTitleValidation = false
    @State private var titleValidationTask: Task<Void, Never>?
    @State private var showingHolidayManager = false
    @State private var cachedDisplayItems: [String: [MacRecurringDisplayItem]] = [:]
    @State private var hasCachedDisplayItems = false

    private var categories: [MacRecurringCategory] {
        get { MacRecurringCategoryStore.decode(categoriesData) }
        nonmutating set { categoriesData = MacRecurringCategoryStore.encode(newValue) }
    }

    var body: some View {
        let visibleCategories = categories
        let displayItems = hasCachedDisplayItems ? cachedDisplayItems : makeDisplayItemsByCategory()

        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(visibleCategories.enumerated()), id: \.element.id) { index, category in
                    categoryCard(category, index: index, displayItems: displayItems[category.id] ?? [])
                        .id(category.id)
                }
                if searchText.isEmpty { newGroupRow }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: currentMatchID) { _, id in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
        }
        .onChange(of: searchText) { _, _ in
            guard let id = currentMatchID else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSearchScrollRequest)) { note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in
                if let item = items.first(where: { $0.id == id }) {
                    proxy.scrollTo(item.themeRawValue, anchor: .center)
                }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
                try? await Task.sleep(for: .milliseconds(260))
                proxy.scrollTo(id, anchor: .center)
            }
        }
        }
        .background(Color.appCanvasBackground)
        .overlay {
            if let creatingItem {
                GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.16).ignoresSafeArea()
                    VStack(spacing: 0) {
                        HStack {
                            Text(isCreatingItem ? "Nieuwe herhaling" : "Wijzig herhaling").font(.title2.bold())
                            Spacer()
                            if !isCreatingItem {
                                Button("Verwijder", systemImage: "trash", role: .destructive) {
                                    removeFromEditor(creatingItem)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                            if isCreatingItem {
                                Button("Annuleer") { cancelCreatingItem() }
                                    .buttonStyle(.bordered)
                                    .tint(.secondary)
                            }
                            Button("Gereed") { finishCreatingItem() }.buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        MacRecurringEditor(
                            item: creatingItem,
                            showsTitleValidation: showsTitleValidation,
                            titleChanged: { clearTitleValidation() }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: min(geometry.size.height + 58, 760), alignment: .top)
                    .background(editorSurfaceColor)
                    .clipShape(.rect(topLeadingRadius: 18, topTrailingRadius: 18))
                    .shadow(color: .black.opacity(0.2), radius: 18, y: -4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .frame(height: geometry.size.height + 58)
                .offset(y: -58)
                }
                .zIndex(10)
            }
        }
        .animation(.snappy(duration: 0.28), value: creatingItem?.id)
        .sheet(isPresented: $showingHolidayManager) { MacHolidayManagerView() }
        .safeAreaInset(edge: .bottom) {
            if let recentlyRemovedItem {
                HStack(spacing: 10) {
                    Label(
                        locale.localizedFormat("feedback.deleted", recentlyRemovedItem.title),
                        systemImage: "trash.fill"
                    )
                        .lineLimit(1)
                    Spacer()
                    Button("Ongedaan maken") { undoRemoval() }.buttonStyle(.borderedProminent)
                }
                .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 18).padding(.bottom, 78)
            }
        }
        .onAppear {
            if !hasCachedDisplayItems {
                cachedDisplayItems = displayItems
                hasCachedDisplayItems = true
            }
            repairUnknownCategories()
        }
        .onChange(of: displaySignature) { _, _ in refreshDisplayItems() }
        .onChange(of: soonestFirst) { _, _ in refreshDisplayItems() }
    }

    private var editorSurfaceColor: Color {
        Color.appThemeColor(
            lightBlue: .brandCanvasBlue,
            gray: Color(nsColor: .windowBackgroundColor)
        )
    }

    private func categoryCard(
        _ category: MacRecurringCategory,
        index: Int,
        displayItems: [MacRecurringDisplayItem]
    ) -> some View {
        let categoryItems = displayItems.map(\.item)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(category.backgroundColor)
                        Image(systemName: category.iconName ?? "repeat")
                            .foregroundStyle(category.color)
                    }
                    .frame(width: 32, height: 32)

                    Menu {
                        categoryAppearanceMenu(category)
                    } label: {
                        Color.clear
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(category.color)
                }
                .frame(width: 32, height: 32)
                .help("Icoon en kleur wijzigen")
                VStack(alignment: .leading, spacing: 1) {
                    if category.isFixed {
                        Text(category.title).font(.headline)
                    } else {
                        TextField("Groepsnaam", text: titleBinding(category.id)).textFieldStyle(.plain).font(.headline)
                    }
                    Text(categorySubtitle(category, items: categoryItems))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    categoryActionsMenu(category, index: index, isEmpty: categoryItems.isEmpty)
                    Button {
                        if category.id == MacRecurringCategoryStore.holidayID { showingHolidayManager = true }
                        else { createItem(in: category.id) }
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold).frame(width: 28, height: 28)
                    }.help(category.id == MacRecurringCategoryStore.holidayID ? "Feestdagen kiezen" : "Herhaling toevoegen")
                }
                .buttonStyle(.plain)
                .foregroundStyle(category.color)
            }.padding(12)

            Divider()
            if !displayItems.isEmpty {
                ForEach(displayItems) { displayItem in
                    itemRow(displayItem, category: category)
                    if displayItem.id != displayItems.last?.id { Divider().padding(.leading, 72) }
                }
            }
        }
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(
                Color.appThemeColor(
                    lightBlue: Color.appCardOutline,
                    gray: Color.primary.opacity(0.08)
                ),
                lineWidth: 1
            )
        }
    }

    private func itemRow(_ displayItem: MacRecurringDisplayItem, category: MacRecurringCategory) -> some View {
        let item = displayItem.item
        return Button { openEditor(for: item) } label: {
            HStack(spacing: 10) {
                if showNextDate {
                    Text(dateBadgeText(displayItem.nextDate))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(category.color)
                        .padding(.horizontal, 3).padding(.vertical, 3)
                        .background(category.backgroundColor, in: Capsule())
                        .frame(width: 32, alignment: .center)
                } else {
                    Circle().fill(category.color).frame(width: 7, height: 7).frame(width: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "Nieuwe herhaling" : item.title).fontWeight(.medium).lineLimit(1)
                    Text(itemDetail(item, nextDate: displayItem.nextDate))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if let link = MacRecurringLink.decode(item.linksData).first, let destination = link.destination {
                    Link(destination: destination) {
                        Image(systemName: "link").frame(width: 24, height: 24)
                    }.help(link.name.isEmpty ? "Open link" : link.name)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(category.color)
                    .frame(width: 28, height: 28, alignment: .center)
            }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
        .modifier(SearchMatchHighlight(
            isMatch: !searchText.isEmpty && (item.title + " " + item.notes).localizedCaseInsensitiveContains(searchText),
            isCurrent: currentMatchID == item.id
        ))
    }

    private func categoryActionsMenu(_ category: MacRecurringCategory, index: Int, isEmpty: Bool) -> some View {
        Menu {
            if index >= 2 {
                Button("Helemaal omhoog", systemImage: "chevron.up.2") { move(index, to: 0) }
            }
            if index >= 1 {
                Button("Omhoog", systemImage: "arrow.up") { move(index, by: -1) }
            }
            if index < categories.count - 1 {
                Button("Omlaag", systemImage: "arrow.down") { move(index, by: 1) }
            }
            if categories.count - 1 - index >= 2 {
                Button("Helemaal omlaag", systemImage: "chevron.down.2") { move(index, to: categories.count - 1) }
            }
            Divider()
            categoryAppearanceMenu(category)
            if !category.isFixed {
                Divider()
                Button("Verwijder groep", systemImage: "trash", role: .destructive) { delete(category.id) }
                    .disabled(!isEmpty || categories.count == 1)
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(category.color)
        .foregroundStyle(category.color)
        .help("Volgorde en uiterlijk")
    }

    @ViewBuilder
    private func categoryAppearanceMenu(_ category: MacRecurringCategory) -> some View {
        Menu("Icoon") {
            ForEach(macRecurringIcons, id: \.self) { icon in
                Button { update(category.id) { $0.iconName = icon } } label: { Label(icon, systemImage: icon) }
            }
        }
        Menu("Kleur") {
            ForEach(RecurringThemeColorOption.allCases) { option in
                Button { update(category.id) { $0.colorRawValue = option.rawValue } } label: { Text(option.rawValue.capitalized) }
            }
        }
    }

    private var newGroupRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.07))
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }.frame(width: 32, height: 32)
            }
            .buttonStyle(.plain).allowsHitTesting(false)

            TextField("Nieuwe categorie", text: $newGroupTitle)
                .textFieldStyle(.plain).font(.headline)
                .onSubmit(addGroup)

            Button(action: addGroup) {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30).background(Color.black.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .opacity(newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(
                Color.appThemeColor(
                    lightBlue: Color.appCardOutline,
                    gray: Color.primary.opacity(0.06)
                ),
                lineWidth: 1
            )
        }
    }

    private func makeDisplayItemsByCategory() -> [String: [MacRecurringDisplayItem]] {
        let displayItems = items.map {
            MacRecurringDisplayItem(
                item: $0,
                nextDate: RecurrenceEngine.nextDate(for: $0) ?? $0.nextDate
            )
        }
        return Dictionary(grouping: displayItems, by: { $0.item.themeRawValue })
            .mapValues { values in
                values.sorted {
                    if $0.nextDate == $1.nextDate {
                        return $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
                    }
                    return soonestFirst ? $0.nextDate < $1.nextDate : $0.nextDate > $1.nextDate
                }
            }
    }
    private var displaySignature: String {
        items.map {
            [
                $0.id.uuidString,
                $0.title,
                $0.themeRawValue,
                $0.recurrenceKindRawValue,
                String($0.nextDate.timeIntervalSinceReferenceDate),
                String($0.birthDate?.timeIntervalSinceReferenceDate ?? -1),
                String($0.intervalValue),
                $0.intervalUnitRawValue,
                String($0.monthlyDay),
                String($0.monthlyOrdinal),
                String($0.monthlyWeekday),
                String($0.annualMonth),
                $0.scheduleShiftsData,
                $0.notes
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: "\n")
    }
    private func refreshDisplayItems() {
        cachedDisplayItems = makeDisplayItemsByCategory()
        hasCachedDisplayItems = true
    }
    private func dateBadgeText(_ date: Date) -> String {
        AppCalendar.localizedDate(date, template: "ddMMM")
    }
    private func categorySubtitle(_ category: MacRecurringCategory, items: [RecurringItem]) -> String {
        if category.id == MacRecurringCategoryStore.birthdayID {
            let count = locale.localizedFormat(
                items.count == 1 ? "recurring.subtitle.birthday.one" : "recurring.subtitle.birthday.many",
                items.count
            )
            let reminders = items.filter { $0.reminderDaysBefore != nil }.count
            guard reminders > 0 else { return count }
            let reminderText = locale.localizedFormat(
                reminders == 1 ? "recurring.subtitle.reminder.one" : "recurring.subtitle.reminder.many",
                reminders
            )
            return "\(count) · \(reminderText)"
        }
        if category.id == MacRecurringCategoryStore.holidayID {
            let count = locale.localizedFormat(
                items.count == 1 ? "recurring.subtitle.holiday.one" : "recurring.subtitle.holiday.many",
                items.count
            )
            let custom = items.filter { HolidayCatalog.managedHoliday(from: $0.notes) == nil }.count
            guard custom > 0 else { return count }
            let customText = locale.localizedFormat(
                custom == 1 ? "recurring.subtitle.custom.one" : "recurring.subtitle.custom.many",
                custom
            )
            return "\(count) · \(customText)"
        }
        return locale.localizedFormat(
            items.count == 1 ? "recurring.subtitle.recurrence.one" : "recurring.subtitle.recurrence.many",
            items.count
        )
    }
    private func itemDetail(_ item: RecurringItem, nextDate date: Date) -> String {
        guard item.recurrenceKind == .birthday else { return RecurrenceEngine.description(for: item) }
        let days = max(0, AppCalendar.calendar.dateComponents([.day], from: AppCalendar.startOfDay(.now), to: date).day ?? 0)
        let timing: String
        if days == 0 {
            if item.birthdayYearUncertain {
                timing = locale.localized("birthday.status.today")
            } else if let age = RecurrenceEngine.ageTurning(for: item, on: date) {
                timing = locale.localizedFormat("birthday.status.turnedToday", age)
            } else {
                timing = locale.localized("birthday.status.today")
            }
        } else if item.birthdayYearUncertain {
            timing = locale.localizedFormat(
                days == 1 ? "birthday.status.birthdayInOneDay" : "birthday.status.birthdayInDays",
                days
            )
        } else if let age = RecurrenceEngine.ageTurning(for: item, on: date) {
            timing = locale.localizedFormat(
                days == 1 ? "birthday.status.turnsInOneDay" : "birthday.status.turnsInDays",
                age,
                days
            )
        } else { timing = RecurrenceEngine.description(for: item) }
        if let reminder = item.reminderDaysBefore { return "\(timing) · reminder \(reminder)" }
        return timing
    }
    private func titleBinding(_ id: String) -> Binding<String> { Binding(get: { categories.first { $0.id == id }?.title ?? "" }, set: { value in update(id) { $0.title = value } }) }
    private func createItem(in id: String) {
        let kind: RecurrenceKind = id == MacRecurringCategoryStore.birthdayID
            ? .birthday
            : (id == MacRecurringCategoryStore.holidayID ? .annualFixed : .interval)
        let item = RecurringItem(nextDate: .now, theme: RecurringTheme(rawValue: id) ?? .general, recurrenceKind: kind)
        item.themeRawValue = id; if kind == .birthday { item.birthDate = .now }
        showsTitleValidation = false
        isCreatingItem = true
        creatingItem = item
    }
    private func addGroup() {
        let title = newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        var value = categories; let id = UUID().uuidString
        value.append(.init(id: id, title: title, isFixed: false, colorRawValue: "green", iconName: "repeat"))
        categories = value; newGroupTitle = ""
    }
    private func update(_ id: String, mutate: (inout MacRecurringCategory) -> Void) { var value = categories; guard let i = value.firstIndex(where: { $0.id == id }) else { return }; mutate(&value[i]); categories = value }
    private func move(_ index: Int, by offset: Int) { move(index, to: index + offset) }
    private func move(_ index: Int, to target: Int) {
        var value = categories
        guard value.indices.contains(index), value.indices.contains(target), index != target else { return }
        let category = value.remove(at: index)
        value.insert(category, at: target)
        categories = value
    }
    private func delete(_ id: String) { guard !items.contains(where: { $0.themeRawValue == id }) else { return }; var value = categories; value.removeAll { $0.id == id }; categories = value }
    private func repairUnknownCategories() { let valid = Set(categories.map(\.id)); guard let fallback = categories.first(where: { $0.id == RecurringTheme.general.rawValue })?.id ?? categories.first?.id else { return }; var changed = false; for item in items where !valid.contains(item.themeRawValue) { item.themeRawValue = fallback; changed = true }; if changed { save() } }
    private func finishCreatingItem() {
        guard let item = creatingItem else { return }
        if isCreatingItem {
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showTitleValidation()
                return
            }
            modelContext.insert(item)
            item.frequencyText = RecurrenceEngine.description(for: item)
            save()
        } else if !isCreatingItem {
            save()
        }
        clearTitleValidation()
        creatingItem = nil
        isCreatingItem = false
    }
    private func cancelCreatingItem() {
        clearTitleValidation()
        creatingItem = nil
        isCreatingItem = false
    }
    private func openEditor(for item: RecurringItem) { clearTitleValidation(); isCreatingItem = false; creatingItem = item }
    private func removeFromEditor(_ item: RecurringItem) { clearTitleValidation(); creatingItem = nil; isCreatingItem = false; remove(item) }
    private func showTitleValidation() {
        titleValidationTask?.cancel()
        showsTitleValidation = true
        titleValidationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showsTitleValidation = false
        }
    }
    private func clearTitleValidation() {
        titleValidationTask?.cancel()
        showsTitleValidation = false
    }
    private func remove(_ item: RecurringItem) {
        dismissUndoTask?.cancel(); item.isRemoved = true; item.completedAt = .now; selection = nil
        recentlyRemovedItem = item; save()
        dismissUndoTask = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { await MainActor.run { recentlyRemovedItem = nil } } }
    }
    private func undoRemoval() {
        guard let item = recentlyRemovedItem else { return }; item.isRemoved = false; item.completedAt = nil
        dismissUndoTask?.cancel(); recentlyRemovedItem = nil; save()
    }
    private func save() { PersistenceSafety.save(modelContext) }
}

private let macRecurringIcons = ["repeat", "calendar", "calendar.badge.clock", "birthday.cake.fill", "party.popper.fill", "gift.fill", "star.fill", "heart.fill", "person.fill", "house.fill", "briefcase.fill", "book.fill", "bell.fill", "clock.fill", "leaf.fill", "car.fill", "airplane", "fork.knife", "cart.fill", "cross.case.fill", "dumbbell.fill", "music.note", "camera.fill", "wrench.and.screwdriver.fill"]

private struct MacDayEntryEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: DayEntry

    var body: some View {
        Form {
            Section("Agenda-item") {
                TextField("Omschrijving", text: $entry.rawText, axis: .vertical)
                DatePicker("Datum", selection: $entry.date, displayedComponents: .date)
                Toggle("Afgerond", isOn: $entry.isDone)
            }
            Section("Details") {
                LabeledContent("Aangemaakt", value: entry.createdAt.formatted())
                LabeledContent("Bron", value: entry.sourceRawValue)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.rawText.isEmpty ? "Nieuw agenda-item" : entry.rawText)
        .onChange(of: entry.rawText) { _, _ in entry.refreshParsedFields(); save() }
        .onChange(of: entry.date) { _, newValue in entry.date = AppCalendar.startOfDay(newValue); save() }
        .onChange(of: entry.isDone) { _, done in entry.completedAt = done ? .now : nil; save() }
    }
    private func save() { PersistenceSafety.save(modelContext) }
}

private struct MacTodoEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var todo: TodoItem

    var body: some View {
        Form {
            Section("Taak") {
                TextField("Omschrijving", text: $todo.text, axis: .vertical)
                Picker("Lijst", selection: $todo.bucketRawValue) {
                    Text("Vandaag").tag(TodoBucket.today.rawValue)
                    Text("Binnenkort").tag(TodoBucket.shortTerm.rawValue)
                    Text("Later").tag(TodoBucket.longTerm.rawValue)
                }
                Toggle("Afgerond", isOn: $todo.isDone)
            }
            Section("Details") {
                LabeledContent("Aangemaakt", value: todo.createdAt.formatted())
            }
        }
        .formStyle(.grouped)
        .navigationTitle(todo.text.isEmpty ? "Nieuwe taak" : todo.text)
        .onChange(of: todo.text) { _, _ in save() }
        .onChange(of: todo.bucketRawValue) { _, _ in save() }
        .onChange(of: todo.isDone) { _, done in todo.completedAt = done ? .now : nil; save() }
    }
    private func save() { PersistenceSafety.save(modelContext) }
}

private struct MacHolidayManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<RecurringItem> { !$0.isRemoved }) private var recurringItems: [RecurringItem]
    @AppStorage(SettingsKeys.recurringHolidayCountry) private var storedCountryCode = ""
    @AppStorage(SettingsKeys.recurringOnlyLocalHolidays) private var onlyLocal = true
    @State private var country = HolidayCountry.localeDefault
    @State private var selectedIDs: Set<String> = []
    @State private var customHoliday: RecurringItem?
    @State private var showingCountryPicker = false

    private var options: [HolidayOption] { HolidayCatalog.options(for: country, onlyLocal: onlyLocal) }
    private var managedItems: [RecurringItem] { recurringItems.filter { HolidayCatalog.managedHoliday(from: $0.notes) != nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Annuleer") { dismiss() }
                Spacer()
                Text("Feestdagen").font(.headline)
                Spacer()
                Button("Bewaar") { applySelection() }.buttonStyle(.borderedProminent)
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    holidayCard("Instellingen") {
                        HStack(spacing: 12) {
                            Text("Standaardland")
                            Spacer(minLength: 12)
                            holidayOptionMenu(
                                selection: $country,
                                title: country.title(for: locale),
                                options: HolidayCountry.allCases.map { ($0, $0.title(for: locale)) }
                            )
                        }
                        .recurringEditorRow(height: 38)

                        HStack(spacing: 12) {
                            Text("Laat alleen lokale feestdagen zien")
                            Spacer(minLength: 12)
                            Toggle("", isOn: $onlyLocal)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(.brandHardBlue)
                                .controlSize(.small)
                        }
                        .recurringEditorRow(height: 38, showsSeparator: false)
                    }

                    holidayCard("Selectie") {
                        HStack {
                            Button(visibleSelectionCount == options.count ? "Alles deselecteren" : "Alles selecteren") {
                                let ids = Set(options.map(\.id))
                                if visibleSelectionCount == options.count { selectedIDs.subtract(ids) }
                                else { selectedIDs.formUnion(ids) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brandHardBlue)
                            .controlSize(.small)
                            Spacer()
                            Text("\(visibleSelectionCount)/\(options.count)")
                                .foregroundStyle(.secondary)
                        }
                        .recurringEditorRow(height: 42)

                        ForEach(options) { option in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(onlyLocal ? option.definition.title : "\(option.definition.title) (\(option.country.title(for: locale)))")
                                    Text(option.definition.recurrenceDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Toggle("", isOn: selectionBinding(option.id))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .tint(.brandHardBlue)
                                    .controlSize(.small)
                            }
                            .recurringEditorRow(height: 48, showsSeparator: option.id != options.last?.id)
                        }
                    }

                    holidayCard("") {
                        Button("Eigen feestdag toevoegen", systemImage: "plus") {
                            beginCustomHoliday()
                        }
                        .buttonStyle(.plain)
                        .recurringEditorRow(height: 38, showsSeparator: false)
                    }
                    Text("Maak een eigen feestdag met een vaste datum of een weekdag van de maand.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(Color.appCanvasBackground)
        .onAppear(perform: loadSelection)
        .onChange(of: country) { _, newCountry in selectedIDs = HolidayCatalog.defaultSelectionIDs(for: newCountry, onlyLocal: onlyLocal) }
        .sheet(item: $customHoliday) { holiday in
            VStack(spacing: 0) {
                HStack {
                    Button("Annuleer") { customHoliday = nil }
                    Spacer()
                    Text("Eigen feestdag").font(.headline)
                    Spacer()
                    Button("Bewaar") { saveCustomHoliday(holiday) }
                        .buttonStyle(.borderedProminent)
                        .disabled(holiday.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
                MacRecurringEditor(item: holiday)
            }
            .frame(minWidth: 540, minHeight: 620)
            .background(Color.appCanvasBackground)
        }
    }

    private var visibleSelectionCount: Int { selectedIDs.intersection(Set(options.map(\.id))).count }

    private func holidayCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty { Text(title).font(.headline).padding(.leading, 1) }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func holidayOptionMenu<Selection: Hashable>(
        selection: Binding<Selection>,
        title: String,
        options: [(value: Selection, title: String)]
    ) -> some View {
        Button {
            showingCountryPicker = true
        } label: {
            HStack(spacing: 7) {
                Spacer(minLength: 0)
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 150, minHeight: 28)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingCountryPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection.wrappedValue = option.value
                        showingCountryPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title)
                            Spacer(minLength: 12)
                            if selection.wrappedValue == option.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(6)
            .frame(minWidth: 150)
        }
    }
    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { selectedIDs.contains(id) }, set: { isSelected in
            if isSelected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        })
    }
    private func loadSelection() {
        country = HolidayCountry(rawValue: storedCountryCode) ?? .localeDefault
        let ids = managedItems.compactMap { item -> String? in
            guard let value = HolidayCatalog.managedHoliday(from: item.notes) else { return nil }
            return "\(value.country.rawValue):\(value.definition.id)"
        }
        selectedIDs = ids.isEmpty ? HolidayCatalog.defaultSelectionIDs(for: country, onlyLocal: onlyLocal) : Set(ids)
    }
    private func beginCustomHoliday() {
        let holiday = RecurringItem(
            nextDate: .now,
            theme: .general,
            recurrenceKind: .annualFixed
        )
        holiday.themeRawValue = MacRecurringCategoryStore.holidayID
        customHoliday = holiday
    }
    private func saveCustomHoliday(_ holiday: RecurringItem) {
        guard !holiday.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        holiday.frequencyText = RecurrenceEngine.description(for: holiday)
        modelContext.insert(holiday)
        _ = PersistenceSafety.save(modelContext)
        customHoliday = nil
    }
    private func applySelection() {
        managedItems.forEach(modelContext.delete)
        for option in options where selectedIDs.contains(option.id) {
            let definition = option.definition
            let item = RecurringItem(title: definition.title, nextDate: HolidayCatalog.nextDate(for: definition), theme: .general, recurrenceKind: .annualFixed, notes: HolidayCatalog.marker(country: option.country, holidayID: definition.id))
            item.themeRawValue = MacRecurringCategoryStore.holidayID
            item.frequencyText = definition.recurrenceDescription
            modelContext.insert(item)
        }
        storedCountryCode = country.rawValue
        _ = PersistenceSafety.save(modelContext)
        dismiss()
    }
}

private struct MacRecurringEditor: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.recurringCategories) private var categoriesData = ""
    @Bindable var item: RecurringItem
    var showsTitleValidation = false
    var titleChanged: () -> Void = {}
    @FocusState private var isTitleFocused: Bool
    @FocusState private var focusedLinkIndex: Int?
    @FocusState private var focusedLinkNameIndex: Int?
    @State private var birthdayYearText = ""
    @State private var currentAgeText = ""
    @State private var editingLinkNameIndex: Int?
    @State private var showingDatePicker = false
    @State private var presentedOptionMenu: String?

    private let rowHeight: CGFloat = 38
    private let optionFill = Color.primary.opacity(0.075)

    private var categories: [MacRecurringCategory] {
        MacRecurringCategoryStore.decode(categoriesData)
    }

    var body: some View {
        editorContent
        .onAppear(perform: loadBirthdayFields)
        .onChange(of: showsTitleValidation) { _, isShowing in
            if isShowing { isTitleFocused = true }
        }
        .onChange(of: item.themeRawValue) { _, categoryID in updateCategory(categoryID) }
        .onChange(of: item.birthDate) { _, _ in saveRecurrence() }
        .onChange(of: item.birthdayYearUncertain) { _, _ in saveRecurrence() }
        .onChange(of: item.notes) { _, _ in save() }
        .onChange(of: focusedLinkNameIndex) { oldValue, newValue in
            if oldValue != nil && newValue == nil { editingLinkNameIndex = nil }
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                identityCard
                editorCard("Frequentie") { frequencyFields }
                linksCard
                notesCard
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color.clear)
    }

    private func updateCategory(_ categoryID: String) {
        if categoryID == MacRecurringCategoryStore.birthdayID {
            item.recurrenceKind = .birthday; item.birthDate = item.birthDate ?? item.nextDate; loadBirthdayFields()
        } else if categoryID == MacRecurringCategoryStore.holidayID {
            item.recurrenceKind = .annualFixed; item.birthDate = nil
        } else if item.recurrenceKind == .birthday || item.recurrenceKind == .annualFixed || item.recurrenceKind == .annualOrdinalWeekday {
            item.recurrenceKind = .interval; item.birthDate = nil
        }
        saveRecurrence()
    }

    private func editorCard<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).padding(.leading, 1)
            VStack(spacing: 0) { content() }
                .font(.body)
                .padding(.horizontal, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func optionMenu<Selection: Hashable>(
        selection: Binding<Selection>,
        title: String,
        minWidth: CGFloat = 128,
        id: String? = nil,
        options: [(value: Selection, title: String)]
    ) -> some View {
        let menuID = id ?? title
        return Button {
            presentedOptionMenu = menuID
        } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(title)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 9)
            .frame(minWidth: minWidth, minHeight: 28)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { presentedOptionMenu == menuID },
                set: { if !$0 { presentedOptionMenu = nil } }
            ),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection.wrappedValue = option.value
                        presentedOptionMenu = nil
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title)
                            Spacer(minLength: 12)
                            if selection.wrappedValue == option.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(6)
            .frame(minWidth: minWidth)
        }
    }

    private func optionField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 9)
            .frame(minHeight: 27)
            .background(optionFill, in: RoundedRectangle(cornerRadius: 7))
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func recurrenceKindTitle(_ kind: RecurrenceKind) -> String {
        switch kind {
        case .interval: "Vaste regelmaat"
        case .monthlyDay: "Maandelijks op datum"
        case .monthlyOrdinalWeekday: "Maandelijks op weekdag"
        case .quarterly: "Elk kwartaal"
        case .yearly: "Jaarlijks (jubileum)"
        case .approximateInterval: "Flexibel (ongeveer)"
        case .birthday: "Verjaardag"
        case .annualFixed: "Feestdag op vaste dag"
        case .annualOrdinalWeekday: "Weekdag van een maand"
        }
    }

    private func intervalUnitTitle(_ unit: RecurrenceUnit) -> String {
        switch unit {
        case .day: "Dagen"
        case .week: "Weken"
        case .month: "Maanden"
        case .year: "Jaren"
        }
    }

    private func ordinalTitle(_ ordinal: Int) -> String {
        [1: "Eerste", 2: "Tweede", 3: "Derde", 4: "Vierde", 5: "Laatste"][ordinal] ?? "Eerste"
    }

    private var identityCard: some View {
        editorCard(item.recurrenceKind == .birthday ? LocalizedStringKey("Wie") : LocalizedStringKey("Wat")) {
            TextField(
                "",
                text: $item.title,
                prompt: Text(showsTitleValidation
                    ? "Verplicht veld"
                    : (item.recurrenceKind == .birthday ? "Naam" : "Titel")
                )
                .foregroundStyle(showsTitleValidation ? .blue : .secondary)
            )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .focused($isTitleFocused)
                .onChange(of: item.title) { _, _ in titleChanged() }
            .recurringEditorRow(height: rowHeight)
            HStack(spacing: 12) {
                Text("Categorie")
                Spacer(minLength: 12)
                optionMenu(
                    selection: $item.themeRawValue,
                    title: categories.first(where: { $0.id == item.themeRawValue })?.title ?? "Categorie",
                    minWidth: 160,
                    options: categories.map { ($0.id, $0.title) }
                )
            }
            .recurringEditorRow(height: rowHeight, showsSeparator: false)
        }
    }

    private var linksCard: some View {
        editorCard("Links") {
            ForEach(0..<visibleLinkFieldCount, id: \.self) { index in
                linkRow(index, showsSeparator: index < visibleLinkFieldCount - 1)
            }
        }
    }

    private func linkRow(_ index: Int, showsSeparator: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                TextField("", text: linkURLBinding(index), prompt: Text("Plak link"))
                    .textFieldStyle(.plain)
                    .focused($focusedLinkIndex, equals: index)
                    .onSubmit { focusedLinkIndex = nil }

                Group {
                    if linkIsEmpty(index) {
                        Color.clear
                    } else {
                        Button { removeLink(index) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Link verwijderen")
                    }
                }
                .frame(width: 22, height: 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)

            Divider().frame(height: 24)

            HStack(spacing: 6) {
                if editingLinkNameIndex == index {
                    TextField("", text: linkNameBinding(index), prompt: Text("Link \(index + 1)"))
                        .textFieldStyle(.plain)
                        .focused($focusedLinkNameIndex, equals: index)
                        .onSubmit { finishEditingLinkName(index) }
                } else if let destination = links[safe: index]?.destination {
                    Link(linkDisplayName(index), destination: destination)
                        .lineLimit(1)
                } else {
                    Text(linkDisplayName(index))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Group {
                    if linkIsEmpty(index) {
                        Color.clear
                    } else {
                        Button { beginEditingLinkName(index) } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Linknaam aanpassen")
                    }
                }
                .frame(width: 22, height: 24)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
        }
        .recurringEditorRow(height: rowHeight, showsSeparator: showsSeparator)
    }

    private var notesCard: some View {
        editorCard("Notitie") {
            TextEditor(text: $item.notes).frame(minHeight: 120).scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var frequencyFields: some View {
        if item.themeRawValue == MacRecurringCategoryStore.birthdayID {
            HStack {
                Text("Dag/Maand")
                Spacer()
                optionMenu(
                    selection: birthdayDayBinding,
                    title: "\(AppCalendar.calendar.component(.day, from: birthDateBinding.wrappedValue))",
                    minWidth: 66,
                    options: (1...daysInBirthdayMonth).map { ($0, "\($0)") }
                )
                optionMenu(
                    selection: birthdayMonthBinding,
                    title: AppCalendar.monthName(AppCalendar.calendar.component(.month, from: birthDateBinding.wrappedValue)),
                    minWidth: 118,
                    options: (1...12).map { ($0, AppCalendar.monthName($0)) }
                )
            }
            .recurringEditorRow(height: rowHeight)
            HStack {
                Text("Leeftijd/jaar")
                Spacer()
                optionField {
                    TextField("", text: currentAgeBinding, prompt: Text("Leeftijd"))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                .frame(width: 72)
                optionField {
                    TextField("", text: birthdayYearBinding, prompt: Text("Jaar"))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                .frame(width: 80)
            }
            .recurringEditorRow(height: rowHeight)
            trailingToggle("Leeftijd/jaar onzeker", isOn: $item.birthdayYearUncertain)
            trailingToggle(
                "Reminder vooraf",
                isOn: reminderEnabledBinding,
                showsSeparator: item.reminderDaysBefore != nil
            )
            if item.reminderDaysBefore != nil {
                HStack(spacing: 12) {
                    Text("Dagen vooraf")
                    Spacer(minLength: 12)
                    Stepper("\(item.reminderDaysBefore ?? 7) dagen", value: reminderDaysBinding, in: 1...365)
                        .fixedSize()
                }
                .recurringEditorRow(height: rowHeight, showsSeparator: false)
            }
        } else if item.themeRawValue == MacRecurringCategoryStore.holidayID {
            HStack(spacing: 12) {
                Text("Regel")
                Spacer(minLength: 12)
                optionMenu(
                    selection: $item.recurrenceKindRawValue,
                    title: item.recurrenceKind == .annualFixed ? "Feestdag op vaste dag" : "Weekdag van een maand",
                    minWidth: 210,
                    options: [
                        (RecurrenceKind.annualFixed.rawValue, "Feestdag op vaste dag"),
                        (RecurrenceKind.annualOrdinalWeekday.rawValue, "Weekdag van een maand")
                    ]
                )
            }
            .recurringEditorRow(height: rowHeight)
            if item.recurrenceKind == .annualFixed {
                compactDatePicker("Datum", selection: $item.nextDate, showsSeparator: false)
            } else {
                monthPicker
                ordinalPicker
                weekdayPicker
            }
        } else {
            compactDatePicker(
                item.recurrenceKind == .yearly
                    ? LocalizedStringKey("Startdatum")
                    : LocalizedStringKey("Eerstvolgende datum"),
                selection: $item.nextDate
            )
            HStack(spacing: 12) {
                Text("Type")
                Spacer(minLength: 12)
                optionMenu(
                    selection: $item.recurrenceKindRawValue,
                    title: recurrenceKindTitle(item.recurrenceKind),
                    minWidth: 205,
                    options: [
                        (RecurrenceKind.interval.rawValue, "Vaste regelmaat"),
                        (RecurrenceKind.monthlyDay.rawValue, "Maandelijks op datum"),
                        (RecurrenceKind.monthlyOrdinalWeekday.rawValue, "Maandelijks op weekdag"),
                        (RecurrenceKind.quarterly.rawValue, "Elk kwartaal"),
                        (RecurrenceKind.yearly.rawValue, "Jaarlijks (jubileum)"),
                        (RecurrenceKind.approximateInterval.rawValue, "Flexibel (ongeveer)")
                    ]
                )
            }
            .recurringEditorRow(height: rowHeight)
            switch item.recurrenceKind {
            case .monthlyDay:
                compactStepper(
                    "Elke \(item.monthlyDay)e van de maand",
                    value: $item.monthlyDay,
                    range: 1...31,
                    showsSeparator: false
                )
            case .monthlyOrdinalWeekday:
                ordinalPicker; weekdayPicker
            case .interval, .approximateInterval:
                compactStepper(
                    "Elke \(item.intervalValue)",
                    value: $item.intervalValue,
                    range: 1...99,
                    showsSeparator: true
                )
                HStack(spacing: 12) {
                    Text("Eenheid")
                    Spacer(minLength: 12)
                    optionMenu(
                        selection: $item.intervalUnitRawValue,
                        title: intervalUnitTitle(item.intervalUnit),
                        minWidth: 118,
                        options: [
                            (RecurrenceUnit.day.rawValue, "Dagen"),
                            (RecurrenceUnit.week.rawValue, "Weken"),
                            (RecurrenceUnit.month.rawValue, "Maanden"),
                            (RecurrenceUnit.year.rawValue, "Jaren")
                        ]
                    )
                }
                .recurringEditorRow(
                    height: rowHeight,
                    showsSeparator: item.recurrenceKind == .approximateInterval
                )
                if item.recurrenceKind == .approximateInterval {
                    Text("De datum varieert voorspelbaar rond deze periode.").font(.caption).foregroundStyle(.secondary)
                }
            case .quarterly:
                Text("Wordt iedere drie maanden herhaald vanaf de eerstvolgende datum.").font(.caption).foregroundStyle(.secondary)
            case .yearly:
                Text("Wordt ieder jaar herhaald op de datum hierboven.").font(.caption).foregroundStyle(.secondary)
            default: EmptyView()
            }
        }
    }

    private func compactStepper(
        _ title: LocalizedStringKey,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        showsSeparator: Bool
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 0) {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 26)

                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .disabled(value.wrappedValue >= range.upperBound)
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(optionFill, in: RoundedRectangle(cornerRadius: 7))
        }
        .recurringEditorRow(height: rowHeight, showsSeparator: showsSeparator)
    }

    private func trailingToggle(
        _ title: LocalizedStringKey,
        isOn: Binding<Bool>,
        showsSeparator: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.brandHardBlue)
                .controlSize(.small)
                .fixedSize()
        }
        .recurringEditorRow(height: rowHeight, showsSeparator: showsSeparator)
    }

    private func compactDatePicker(
        _ title: LocalizedStringKey,
        selection: Binding<Date>,
        showsSeparator: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Button {
                showingDatePicker.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(dateText(selection.wrappedValue))
                }
                .padding(.horizontal, 9)
                .frame(minHeight: 27)
                .background(optionFill, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePicker) {
                DatePicker("", selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .padding()
            }
        }
        .recurringEditorRow(height: rowHeight, showsSeparator: showsSeparator)
    }

    private var monthPicker: some View {
        HStack(spacing: 12) {
            Text("Maand")
            Spacer(minLength: 12)
            optionMenu(
                selection: $item.annualMonth,
                title: AppCalendar.monthName(item.annualMonth),
                minWidth: 118,
                options: (1...12).map { ($0, AppCalendar.monthName($0)) }
            )
        }
        .recurringEditorRow(height: rowHeight)
    }
    private var ordinalPicker: some View {
        HStack(spacing: 12) {
            Text("Welke")
            Spacer(minLength: 12)
            optionMenu(
                selection: $item.monthlyOrdinal,
                title: ordinalTitle(item.monthlyOrdinal),
                minWidth: 108,
                options: [(1, "Eerste"), (2, "Tweede"), (3, "Derde"), (4, "Vierde"), (5, "Laatste")]
            )
        }
        .recurringEditorRow(height: rowHeight)
    }
    private var weekdayPicker: some View {
        HStack(spacing: 12) {
            Text("Weekdag")
            Spacer(minLength: 12)
            optionMenu(
                selection: $item.monthlyWeekday,
                title: RecurrenceEngine.weekdayName(item.monthlyWeekday).capitalized,
                minWidth: 118,
                options: (1...7).map { ($0, RecurrenceEngine.weekdayName($0).capitalized) }
            )
        }
        .recurringEditorRow(height: rowHeight, showsSeparator: false)
    }
    private var birthDateBinding: Binding<Date> { Binding(get: { item.birthDate ?? item.nextDate }, set: { item.birthDate = AppCalendar.startOfDay($0); item.nextDate = AppCalendar.startOfDay($0) }) }

    private var birthdayMonthBinding: Binding<Int> {
        Binding(get: { AppCalendar.calendar.component(.month, from: birthDateBinding.wrappedValue) }, set: { updateBirthday(month: $0) })
    }
    private var birthdayDayBinding: Binding<Int> {
        Binding(get: { AppCalendar.calendar.component(.day, from: birthDateBinding.wrappedValue) }, set: { updateBirthday(day: $0) })
    }
    private var daysInBirthdayMonth: Int {
        let date = birthDateBinding.wrappedValue
        return AppCalendar.calendar.range(of: .day, in: .month, for: date)?.count ?? 31
    }
    private var currentAgeBinding: Binding<String> {
        Binding(get: { currentAgeText }, set: { value in
            currentAgeText = String(value.filter(\.isNumber).prefix(3))
            guard let age = Int(currentAgeText) else { return }
            let components = AppCalendar.calendar.dateComponents([.month, .day], from: birthDateBinding.wrappedValue)
            guard let date = RecurrenceEngine.birthDate(month: components.month ?? 1, day: components.day ?? 1, currentAge: age) else { return }
            setBirthDate(date); birthdayYearText = String(AppCalendar.calendar.component(.year, from: date)); item.birthdayYearUncertain = false
        })
    }
    private var birthdayYearBinding: Binding<String> {
        Binding(get: { birthdayYearText }, set: { value in
            birthdayYearText = String(value.filter(\.isNumber).prefix(4))
            guard birthdayYearText.count == 4, let year = Int(birthdayYearText) else { return }
            updateBirthday(year: year)
            currentAgeText = String(RecurrenceEngine.currentAge(for: birthDateBinding.wrappedValue))
            item.birthdayYearUncertain = false
        })
    }
    private func loadBirthdayFields() {
        guard item.themeRawValue == MacRecurringCategoryStore.birthdayID else { return }
        let date = birthDateBinding.wrappedValue
        birthdayYearText = String(AppCalendar.calendar.component(.year, from: date))
        currentAgeText = String(RecurrenceEngine.currentAge(for: date))
    }
    private func updateBirthday(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        let old = AppCalendar.calendar.dateComponents([.year, .month, .day], from: birthDateBinding.wrappedValue)
        let resolvedYear = year ?? old.year ?? 2000
        let resolvedMonth = month ?? old.month ?? 1
        let provisional = AppCalendar.calendar.date(from: DateComponents(year: resolvedYear, month: resolvedMonth, day: 1)) ?? birthDateBinding.wrappedValue
        let maxDay = AppCalendar.calendar.range(of: .day, in: .month, for: provisional)?.count ?? 31
        guard let date = AppCalendar.calendar.date(from: DateComponents(year: resolvedYear, month: resolvedMonth, day: min(day ?? old.day ?? 1, maxDay))) else { return }
        setBirthDate(date)
        currentAgeText = String(RecurrenceEngine.currentAge(for: date))
        birthdayYearText = String(resolvedYear)
    }
    private func setBirthDate(_ date: Date) {
        item.birthDate = AppCalendar.startOfDay(date)
        item.nextDate = AppCalendar.startOfDay(date)
        saveRecurrence()
    }
    private var reminderEnabledBinding: Binding<Bool> { Binding(get: { item.reminderDaysBefore != nil }, set: { item.reminderDaysBefore = $0 ? 7 : nil }) }
    private var reminderDaysBinding: Binding<Int> { Binding(get: { item.reminderDaysBefore ?? 7 }, set: { item.reminderDaysBefore = $0 }) }
    private var nextDate: Date { RecurrenceEngine.nextDate(for: item) ?? item.nextDate }
    private var links: [MacRecurringLink] { MacRecurringLink.decode(item.linksData) }
    private func linkDisplayName(_ index: Int) -> String {
        let name = links[safe: index]?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Link \(index + 1)" : name
    }
    private func linkIsEmpty(_ index: Int) -> Bool {
        links[safe: index]?.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
    private func beginEditingLinkName(_ index: Int) {
        editingLinkNameIndex = index
        Task { @MainActor in focusedLinkNameIndex = index }
    }
    private func finishEditingLinkName(_ index: Int) {
        guard editingLinkNameIndex == index else { return }
        editingLinkNameIndex = nil
        focusedLinkNameIndex = nil
    }
    private var visibleLinkFieldCount: Int { min(5, max(1, links.count + (links.count < 5 ? 1 : 0))) }
    private func linkURLBinding(_ index: Int) -> Binding<String> { Binding(get: { links[safe: index]?.url ?? "" }, set: { updateLink(index, url: $0) }) }
    private func linkNameBinding(_ index: Int) -> Binding<String> { Binding(get: { links[safe: index]?.name ?? "" }, set: { updateLink(index, name: $0) }) }
    private func updateLink(_ index: Int, url: String? = nil, name: String? = nil) {
        var value = links
        while value.count <= index { value.append(MacRecurringLink()) }
        if let url { value[index].url = url }
        if let name { value[index].name = name }
        encodeLinks(value)
    }
    private func removeLink(_ index: Int) {
        var value = links
        guard value.indices.contains(index) else { return }
        value.remove(at: index)
        if editingLinkNameIndex == index { editingLinkNameIndex = nil }
        focusedLinkIndex = nil
        focusedLinkNameIndex = nil
        encodeLinks(value)
    }
    private func encodeLinks(_ value: [MacRecurringLink]) {
        let cleaned = Array(value.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(5))
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        item.linksData = String(data: data, encoding: .utf8) ?? ""; save()
    }
    private func saveRecurrence() { item.recurrenceConfigurationVersion = 1; item.frequencyText = RecurrenceEngine.description(for: item); save() }
    private func save() { PersistenceSafety.save(modelContext) }
}

private struct MacRecurringEditorRowStyle: ViewModifier {
    let height: CGFloat
    let showsSeparator: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .center)
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(height: 0.5)
                }
            }
    }
}

private extension View {
    func recurringEditorRow(height: CGFloat, showsSeparator: Bool = true) -> some View {
        modifier(MacRecurringEditorRowStyle(height: height, showsSeparator: showsSeparator))
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct MacCloudSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKeys.weekdayLabelLength)
    private var weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue
    @AppStorage(SettingsKeys.defaultColorCombinationEnabled)
    private var defaultColorCombinationEnabled = true
    @State private var status: CKAccountStatus?
    @State private var appActivityState = AppActivityState.shared

    var body: some View {
        Form {
            Section("Agenda") {
                Picker(weekdayFormattingPickerTitle, selection: $weekdayLabelLength) {
                    ForEach(WeekdayLabelLengthOption.allCases) { option in
                        Text(option.title(for: locale)).tag(option.rawValue)
                    }
                }
                .onAppear(perform: normalizeWeekdayLabelLength)
            }

            Section("Weergave") {
                Picker("App Color", selection: $defaultColorCombinationEnabled) {
                    Text("Light blue").tag(true)
                    Text("Grey").tag(false)
                }
            }

            Section("iCloud") {
                LabeledContent("Synchronisatie") {
                    HStack {
                        Image(systemName: status == .available ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                            .foregroundStyle(status == .available ? .green : .orange)
                        Text(statusText)
                    }
                }
                Text("Deze Mac gebruikt dezelfde private iCloud-container als je iPhone en iPad. Wijzigingen worden automatisch op alle apparaten bijgewerkt.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
        .overlay(alignment: .topLeading) {
            AppActivityIndicator()
                .padding(10)
        }
        .onChange(of: defaultColorCombinationEnabled) { _, _ in
            appActivityState.begin(.themeChange)
            appActivityState.finish(.themeChange, after: .milliseconds(900))
        }
        .task { status = await ICloudStatusService.accountStatus() }
    }

    private var statusText: String {
        let key = switch status {
        case .available: "Actief"
        case .noAccount: "Geen iCloud-account"
        case .restricted: "Beperkt"
        case .temporarilyUnavailable: "Tijdelijk niet beschikbaar"
        case .couldNotDetermine: "Onbekend"
        case nil: "Controleren…"
        @unknown default: "Onbekend"
        }
        return locale.localized(key)
    }

    private func normalizeWeekdayLabelLength() {
        guard WeekdayLabelLengthOption(rawValue: weekdayLabelLength) == nil else { return }
        weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue
    }

    private var weekdayFormattingPickerTitle: String {
        locale.localized("settings.weekdayFormatting")
    }
}
#endif
