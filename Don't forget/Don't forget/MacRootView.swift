#if os(macOS)
import AppKit
import Charts
import CloudKit
import SwiftData
import SwiftUI

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
    var title: String {
        switch self {
        case .agenda: "Agenda"
        case .todo: "Taken"
        case .recurring: "Terugkerend"
        case .history: "Afgerond"
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
            Text(section.title)
                .font(.system(size: 22, weight: .semibold))
            HStack {
                Button(action: finishEditing) {
                    Image(systemName: "return")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(headerButtonBackground(isActive: canReturn), in: Circle())
                        .overlay { Circle().stroke(headerButtonBorder(isActive: canReturn), lineWidth: 1.5) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(canReturn ? Color.brandHardBlue : Color.secondary.opacity(0.65))
                .help("Terug")
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
        .padding(.vertical, 12)
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
            .padding(.top, 8)
            .frame(maxWidth: 936)
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
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                        section = item
                    }
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
                .accessibilityLabel(item.title)
                .help(item.title)
            }
        }
        .padding(6)
        .macInteractiveGlass(in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 14, y: 7)
    }

    @ViewBuilder
    private var itemList: some View {
        switch section {
        case .agenda:
            MacCalendarView(entries: agendaItems, searchText: searchText, currentMatchID: currentSearchMatchID, selection: $selection)
        case .todo:
            MacTodoBoard(searchText: searchText, currentMatchID: currentSearchMatchID, selection: $selection)
        case .recurring:
            MacRecurringBoard(searchText: searchText, currentMatchID: currentSearchMatchID, selection: $selection)
        case .history:
            MacHistoryBoard(searchText: searchText, currentMatchID: currentSearchMatchID)
        }
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
        case .agenda: return agendaItems.map(\.id)
        case .todo: return todoItems.map(\.id)
        case .recurring: return activeRecurringItems.map(\.id)
        case .history: return historyDayEntries.map(\.id) + historyTodos.map(\.id)
        }
    }

    private var currentSearchMatchID: UUID? {
        searchMatchIDs.indices.contains(currentSearchMatch) ? searchMatchIDs[currentSearchMatch] : nil
    }

    private var agendaItems: [DayEntry] {
        dayEntries
            .filter { !$0.isDone && !$0.isRemoved && matches($0.rawText) }
            .sorted { ($0.date, $0.manualOrder) < ($1.date, $1.manualOrder) }
    }

    private var todoItems: [TodoItem] {
        todos
            .filter { !$0.isDone && !$0.isRemoved && matches($0.text) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeRecurringItems: [RecurringItem] {
        recurringItems
            .filter { !$0.isRemoved && matches($0.title + " " + $0.notes) }
            .sorted { $0.nextDate < $1.nextDate }
    }

    private var historyDayEntries: [DayEntry] {
        dayEntries
            .filter { ($0.isDone || $0.isRemoved) && matches($0.rawText) }
            .sorted { ($0.completedAt ?? $0.date) > ($1.completedAt ?? $1.date) }
    }

    private var historyTodos: [TodoItem] {
        todos
            .filter { ($0.isDone || $0.isRemoved) && matches($0.text) }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private func matches(_ value: String) -> Bool {
        normalizedSearch.isEmpty || value.localizedCaseInsensitiveContains(normalizedSearch)
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

private struct MacHistoryBoard: View {
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
                category: group?.title ?? (recurring ? "Herhalingen" : "Agenda"), completedAt: entry.completedAt ?? entry.date,
                isDone: entry.isDone, isRemoved: entry.isRemoved, color: group?.color ?? (recurring ? .orange : .blue), entry: entry, todo: nil, recurring: nil)
        }
        let todoItems = todos.map { todo in
            let group = todoMap[todo.bucketRawValue]
            return MacHistoryItem(id: todo.id, title: todo.text, source: .todo, category: group?.title ?? "Taken",
                completedAt: todo.completedAt ?? todo.createdAt, isDone: todo.isDone, isRemoved: todo.isRemoved, color: group?.color ?? .green,
                entry: nil, todo: todo, recurring: nil)
        }
        let removedRecurring = recurringItems.map { item in
            let group = recurringMap[item.themeRawValue]
            return MacHistoryItem(id: item.id, title: item.title, source: .recurring, category: group?.title ?? "Herhalingen",
                completedAt: item.completedAt ?? item.createdAt, isDone: false, isRemoved: true, color: group?.color ?? .orange,
                entry: nil, todo: nil, recurring: item)
        }
        return (dayItems + todoItems + removedRecurring).sorted { $0.completedAt > $1.completedAt }
    }
    private var visibleItems: [MacHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { $0.id != pendingDeletion?.id && (showsDeletedItems || !$0.isRemoved) && (filter == .all || $0.filter == filter) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)) }
    }
    private var sections: [(Date, [MacHistoryItem])] {
        Dictionary(grouping: visibleItems) { AppCalendar.startOfDay($0.completedAt) }.sorted { $0.key > $1.key }
    }
    private var filteredItems: [MacHistoryItem] { items.filter { filter == .all || $0.filter == filter } }
    private var completedItems: [MacHistoryItem] { filteredItems.filter { !$0.isRemoved } }
    private var chartDays: [(date: Date, count: Int)] {
        let today = AppCalendar.startOfDay(.now)
        return (-6...0).map { offset in
            let date = AppCalendar.calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return (date, completedItems.count { AppCalendar.calendar.isDate($0.completedAt, inSameDayAs: date) })
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 14) {
                controls
                summary
                if visibleItems.isEmpty { ContentUnavailableView(searchText.isEmpty ? "Nog niets afgerond" : "Geen zoekresultaten", systemImage: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass") }
                ForEach(sections, id: \.0) { date, rows in dayCard(date: date, rows: rows) }
            }
            .padding(18).frame(maxWidth: 900).frame(maxWidth: .infinity)
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
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
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
                        Text(item.rawValue)
                    }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(filter == item ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(
                            filter == item
                                ? Color.brandHardBlue
                                : (DefaultColorCombination.isEnabled ? Color.white : Color.primary.opacity(0.055)),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    filter == item
                                        ? Color.clear
                                        : (DefaultColorCombination.isEnabled
                                            ? Color.appCardOutline
                                            : Color.primary.opacity(0.12))
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .help(item.rawValue)
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
                            DefaultColorCombination.isEnabled
                                ? Color.brandCanvasBlue
                                : Color.brandHardBlue.opacity(0.12),
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
            if isChartExpanded {
                Divider().padding(.horizontal, 14)
                weekChart
                    .frame(maxWidth: .infinity)
                    .frame(height: 225)
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.appCardOutline) }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Afgelopen 7 dagen")
                .font(.system(size: 14, weight: .semibold))
            Chart(chartDays, id: \.date) { day in
                BarMark(x: .value("Dag", day.date, unit: .day), y: .value("Aantal", day.count))
                    .foregroundStyle(filter.color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 2) {
                        if day.count > 0 { Text("\(day.count)").font(.caption2).foregroundStyle(.secondary) }
                    }
            }
            .chartYScale(domain: 0...max(1, (chartDays.map(\.count).max() ?? 0) + 1))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) { if let date = value.as(Date.self) { Text(shortWeekday(date)) } }
                    AxisTick().foregroundStyle(Color.secondary.opacity(0.35))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.18))
                    AxisTick().foregroundStyle(Color.secondary.opacity(0.35))
                    AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)") } }
                }
            }
        }
        .padding(12)
        .background(
            DefaultColorCombination.isEnabled ? Color.brandCanvasBlue : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityLabel("Afgeronde items per dag over de afgelopen zeven dagen")
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
                .help("Terugzetten naar \(item.filter.rawValue)")
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
        if Calendar.current.isDateInToday(date) { return "Vandaag" }
        if Calendar.current.isDateInYesterday(date) { return "Gisteren" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
    private func shortWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EE"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
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
    static let maxCount = 10
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
    @FocusState private var focusedNewTodoGroupID: String?

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
                }
                if searchText.isEmpty && groups.count < MacTodoGroupStore.maxCount { newGroupRow }
            }
            .padding(18)
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
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
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
                Text("Naar agenda verplaatsen").font(.title2.bold())
                Text(todo.text).foregroundStyle(.secondary).lineLimit(2)
                DatePicker("Datum", selection: $agendaDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                HStack {
                    Button("Annuleer", role: .cancel) { agendaTodo = nil }
                    Spacer()
                    Button("Verplaats") { moveToAgenda(todo, date: agendaDate) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 390)
        }
    }

    private var visibleGroupEntries: [(offset: Int, element: MacTodoGroup)] {
        let entries = Array(groups.enumerated())
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return entries }
        return entries.filter { _, group in
            todos.contains { $0.bucketRawValue == group.id && $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func groupCard(_ group: MacTodoGroup, index: Int) -> some View {
        let items = todos.filter {
            $0.bucketRawValue == group.id && (searchText.isEmpty || $0.text.localizedCaseInsensitiveContains(searchText))
        }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: group.icon)
                    .foregroundStyle(group.color)
                    .frame(width: 32, height: 32)
                    .background(group.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
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

            if items.isEmpty && !searchText.isEmpty {
                Text("Geen overeenkomende taken")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
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
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.appCardOutline) }
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
            }
            .buttonStyle(.plain)
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
        if groups.count == 1 { Text("Geen andere categorieën") }
        Divider()
        Button { moveToAgenda(todo, date: .now) } label: {
            Label("Naar vandaag", systemImage: "calendar.badge.checkmark")
        }
        Button {
            agendaDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            agendaTodo = todo
        } label: { Label("Andere datum in agenda…", systemImage: "calendar.badge.plus") }
        Divider()
        Button(role: .destructive) { remove(todo) } label: {
            Label("Verwijderen", systemImage: "trash")
        }
    }

    private func groupMenu(_ group: MacTodoGroup, index: Int, isEmpty: Bool) -> some View {
        Menu {
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
            Divider()
            Button("Omhoog", systemImage: "arrow.up") { moveGroup(index, by: -1) }
                .disabled(index == 0)
            Button("Omlaag", systemImage: "arrow.down") { moveGroup(index, by: 1) }
                .disabled(index == groups.count - 1)
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
        .padding(.trailing, 20)
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
            DefaultColorCombination.isEnabled ? Color.white : Color.black.opacity(0.07),
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
        case .completed(let todo): return "‘\(todo.text)’ naar Afgerond verplaatst"
        case .removed(_, let title): return "‘\(title)’ verwijderd"
        case .agenda(let move): return "‘\(move.text)’ naar \(move.date.formatted(date: .abbreviated, time: .omitted)) verplaatst"
        }
    }
    private func feedbackIcon(_ feedback: MacTodoFeedback) -> String {
        switch feedback { case .completed: "checkmark.circle.fill"; case .removed: "trash.fill"; case .agenda: "calendar.badge.checkmark" }
    }
    private func move(_ todo: TodoItem, to id: String) { todo.bucketRawValue = id; save() }
    private func addGroup() {
        let title = newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, groups.count < MacTodoGroupStore.maxCount else { return }
        var value = groups; value.append(MacTodoGroup(id: UUID().uuidString, title: title, icon: "list.bullet", colorRawValue: RecurringThemeColorOption.blue.rawValue))
        groups = value; newGroupTitle = ""
    }
    private func updateGroup(_ id: String, mutate: (inout MacTodoGroup) -> Void) {
        var value = groups; guard let index = value.firstIndex(where: { $0.id == id }) else { return }
        mutate(&value[index]); groups = value
    }
    private func moveGroup(_ index: Int, by offset: Int) {
        var value = groups; let target = index + offset
        guard value.indices.contains(index), value.indices.contains(target) else { return }
        value.swapAt(index, target); groups = value
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
    static let maxCount = 10

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

private struct MacRecurringBoard: View {
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

    private var categories: [MacRecurringCategory] {
        get { MacRecurringCategoryStore.decode(categoriesData) }
        nonmutating set { categoriesData = MacRecurringCategoryStore.encode(newValue) }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(visibleCategoryEntries, id: \.element.id) { index, category in
                    categoryCard(category, index: index)
                }
                if searchText.isEmpty && categories.count < MacRecurringCategoryStore.maxCount { newGroupRow }
            }
            .padding(18)
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
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        }
        .background(Color.appCanvasBackground)
        .overlay {
            if let creatingItem {
                ZStack {
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
                            Button("Gereed") { finishCreatingItem() }.buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14).background(.bar)
                        Divider()
                        MacRecurringEditor(item: creatingItem)
                    }
        .background(Color.appCanvasBackground)
                    .shadow(color: .black.opacity(0.2), radius: 18, y: -4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(10)
            }
        }
        .animation(.snappy(duration: 0.28), value: creatingItem?.id)
        .safeAreaInset(edge: .bottom) {
            if let recentlyRemovedItem {
                HStack(spacing: 10) {
                    Label("‘\(recentlyRemovedItem.title)’ verwijderd", systemImage: "trash.fill")
                        .lineLimit(1)
                    Spacer()
                    Button("Ongedaan maken") { undoRemoval() }.buttonStyle(.borderedProminent)
                }
                .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
        }
        .onAppear {
            repairUnknownCategories()
        }
    }

    private var visibleCategoryEntries: [(offset: Int, element: MacRecurringCategory)] {
        let entries = Array(categories.enumerated())
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return entries }
        return entries.filter { !visibleItems(in: $0.element.id).isEmpty }
    }

    private func categoryCard(_ category: MacRecurringCategory, index: Int) -> some View {
        let categoryItems = visibleItems(in: category.id)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: category.iconName ?? "repeat")
                    .foregroundStyle(category.color).frame(width: 32, height: 32)
                    .background(category.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
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
                    Button { createItem(in: category.id) } label: {
                        Image(systemName: "plus").fontWeight(.semibold).frame(width: 28, height: 28)
                    }.help("Herhaling toevoegen")
                }
                .buttonStyle(.plain)
                .foregroundStyle(category.color)
            }.padding(12)

            Divider()
            if categoryItems.isEmpty && !searchText.isEmpty {
                Text("Geen overeenkomende herhalingen").foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(categoryItems) { item in
                    itemRow(item, category: category)
                    if item.id != categoryItems.last?.id { Divider().padding(.leading, 72) }
                }
            }
        }
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(
                DefaultColorCombination.isEnabled
                    ? Color.appCardOutline
                    : Color.primary.opacity(0.08),
                lineWidth: 1
            )
        }
    }

    private func itemRow(_ item: RecurringItem, category: MacRecurringCategory) -> some View {
        Button { openEditor(for: item) } label: {
            HStack(spacing: 10) {
                if showNextDate {
                    Text(dateBadgeText(nextDate(for: item)))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(category.color)
                        .padding(.horizontal, 3).padding(.vertical, 3)
                        .background(category.backgroundColor, in: Capsule())
                        .frame(width: 32, alignment: .center)
                } else {
                    Circle().fill(category.color).frame(width: 7, height: 7).frame(width: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "Nieuwe herhaling" : item.title).fontWeight(.medium).lineLimit(1)
                    Text(itemDetail(item))
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
            Button("Omhoog verplaatsen", systemImage: "arrow.up") { move(index, by: -1) }.disabled(index == 0)
            Button("Omlaag verplaatsen", systemImage: "arrow.down") { move(index, by: 1) }.disabled(index == categories.count - 1)
            Divider()
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
                DefaultColorCombination.isEnabled
                    ? Color.appCardOutline
                    : Color.primary.opacity(0.06),
                lineWidth: 1
            )
        }
    }

    private func visibleItems(in id: String) -> [RecurringItem] {
        items.filter { $0.themeRawValue == id && (searchText.isEmpty || ($0.title + " " + $0.notes).localizedCaseInsensitiveContains(searchText)) }
            .sorted {
                let lhs = nextDate(for: $0), rhs = nextDate(for: $1)
                if lhs == rhs { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return soonestFirst ? lhs < rhs : lhs > rhs
            }
    }
    private func dateBadgeText(_ date: Date) -> String {
        AppCalendar.localizedDate(date, template: "ddMMM")
    }
    private func nextDate(for item: RecurringItem) -> Date { RecurrenceEngine.nextDate(for: item) ?? item.nextDate }
    private func categorySubtitle(_ category: MacRecurringCategory, items: [RecurringItem]) -> String {
        if category.id == MacRecurringCategoryStore.birthdayID {
            let count = items.count == 1 ? "1 verjaardag" : "\(items.count) verjaardagen"
            let reminders = items.filter { $0.reminderDaysBefore != nil }.count
            return reminders == 0 ? count : "\(count) · \(reminders) reminder\(reminders == 1 ? "" : "s")"
        }
        if category.id == MacRecurringCategoryStore.holidayID {
            let count = items.count == 1 ? "1 feestdag" : "\(items.count) feestdagen"
            let custom = items.filter { HolidayCatalog.managedHoliday(from: $0.notes) == nil }.count
            return custom == 0 ? count : "\(count) · \(custom) zelf toegevoegd"
        }
        return items.count == 1 ? "1 herhaling" : "\(items.count) herhalingen"
    }
    private func itemDetail(_ item: RecurringItem) -> String {
        guard item.recurrenceKind == .birthday else { return RecurrenceEngine.description(for: item) }
        let date = nextDate(for: item)
        let days = max(0, AppCalendar.calendar.dateComponents([.day], from: AppCalendar.startOfDay(.now), to: date).day ?? 0)
        let timing: String
        if days == 0 {
            if item.birthdayYearUncertain { timing = "Is vandaag jarig" }
            else if let age = RecurrenceEngine.ageTurning(for: item, on: date) { timing = "Is vandaag \(age) geworden" }
            else { timing = "Is vandaag jarig" }
        } else if item.birthdayYearUncertain {
            timing = "Is over \(days) \(days == 1 ? "dag" : "dagen") jarig"
        } else if let age = RecurrenceEngine.ageTurning(for: item, on: date) {
            timing = "Wordt over \(days) \(days == 1 ? "dag" : "dagen") \(age)"
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
    private func move(_ index: Int, by offset: Int) { var value = categories; let target = index + offset; guard value.indices.contains(index), value.indices.contains(target) else { return }; value.swapAt(index, target); categories = value }
    private func delete(_ id: String) { guard !items.contains(where: { $0.themeRawValue == id }) else { return }; var value = categories; value.removeAll { $0.id == id }; categories = value }
    private func repairUnknownCategories() { let valid = Set(categories.map(\.id)); guard let fallback = categories.first(where: { $0.id == RecurringTheme.general.rawValue })?.id ?? categories.first?.id else { return }; var changed = false; for item in items where !valid.contains(item.themeRawValue) { item.themeRawValue = fallback; changed = true }; if changed { save() } }
    private func finishCreatingItem() {
        guard let item = creatingItem else { return }
        if isCreatingItem, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelContext.insert(item)
            item.frequencyText = RecurrenceEngine.description(for: item)
            save()
        } else if !isCreatingItem {
            save()
        }
        creatingItem = nil
        isCreatingItem = false
    }
    private func openEditor(for item: RecurringItem) { isCreatingItem = false; creatingItem = item }
    private func removeFromEditor(_ item: RecurringItem) { creatingItem = nil; isCreatingItem = false; remove(item) }
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

private struct MacRecurringEditor: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.recurringCategories) private var categoriesData = ""
    @Bindable var item: RecurringItem
    @FocusState private var focusedLinkIndex: Int?

    private var categories: [MacRecurringCategory] {
        MacRecurringCategoryStore.decode(categoriesData)
    }

    var body: some View {
        Form {
            Section(item.recurrenceKind == .birthday ? "Wie" : "Wat") {
                TextField(item.recurrenceKind == .birthday ? "Naam" : "Titel", text: $item.title)
                Picker("Categorie", selection: $item.themeRawValue) {
                    ForEach(categories) { category in
                        Label(category.title, systemImage: category.iconName ?? "repeat").tag(category.id)
                    }
                }
            }

            Section("Frequentie") { frequencyFields }

            Section("Overzicht") {
                LabeledContent("Volgende", value: nextDate.formatted(date: .long, time: .omitted))
                LabeledContent("Herhaling", value: RecurrenceEngine.description(for: item))
            }

            Section("Links") {
                ForEach(0..<visibleLinkFieldCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("URL").foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                            TextField("", text: linkURLBinding(index), prompt: Text("Plak link"))
                                .textFieldStyle(.plain)
                                .focused($focusedLinkIndex, equals: index)
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Naam").foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                            TextField("", text: linkNameBinding(index), prompt: Text("Link \(index + 1)"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                            if let destination = links[safe: index]?.destination {
                                Link(destination: destination) {
                                    HStack(spacing: 4) {
                                        Text(linkDisplayName(index)).lineLimit(1)
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                }.help("Open \(linkDisplayName(index))")
                            }
                            Button { removeLink(index) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .disabled(index >= links.count).help("Verwijder link")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("Notities") {
                TextEditor(text: $item.notes).frame(minHeight: 120)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.title.isEmpty ? "Nieuw terugkerend item" : item.title)
        .onChange(of: item.title) { _, _ in save() }
        .onChange(of: item.nextDate) { _, value in item.nextDate = AppCalendar.startOfDay(value); saveRecurrence() }
        .onChange(of: item.themeRawValue) { _, categoryID in
            if categoryID == MacRecurringCategoryStore.birthdayID {
                item.recurrenceKind = .birthday
                item.birthDate = item.birthDate ?? item.nextDate
            } else if categoryID == MacRecurringCategoryStore.holidayID {
                item.recurrenceKind = .annualFixed
                item.birthDate = nil
            } else if item.recurrenceKind == .birthday || item.recurrenceKind == .annualFixed || item.recurrenceKind == .annualOrdinalWeekday {
                item.recurrenceKind = .interval
                item.birthDate = nil
            }
            saveRecurrence()
        }
        .onChange(of: item.recurrenceKindRawValue) { _, _ in saveRecurrence() }
        .onChange(of: item.intervalValue) { _, _ in saveRecurrence() }
        .onChange(of: item.intervalUnitRawValue) { _, _ in saveRecurrence() }
        .onChange(of: item.monthlyDay) { _, _ in saveRecurrence() }
        .onChange(of: item.monthlyOrdinal) { _, _ in saveRecurrence() }
        .onChange(of: item.monthlyWeekday) { _, _ in saveRecurrence() }
        .onChange(of: item.annualMonth) { _, _ in saveRecurrence() }
        .onChange(of: item.birthDate) { _, value in
            if let value { item.birthDate = AppCalendar.startOfDay(value); item.nextDate = AppCalendar.startOfDay(value) }
            saveRecurrence()
        }
        .onChange(of: item.birthdayYearUncertain) { _, _ in saveRecurrence() }
        .onChange(of: item.reminderDaysBefore) { _, _ in saveRecurrence() }
        .onChange(of: item.notes) { _, _ in save() }
    }

    @ViewBuilder private var frequencyFields: some View {
        if item.themeRawValue == MacRecurringCategoryStore.birthdayID {
            DatePicker("Geboortedatum", selection: birthDateBinding, displayedComponents: .date)
            Toggle("Geboortejaar onzeker", isOn: $item.birthdayYearUncertain)
            Toggle("Reminder vooraf", isOn: reminderEnabledBinding)
            if item.reminderDaysBefore != nil {
                Stepper("\(item.reminderDaysBefore ?? 7) dagen vooraf", value: reminderDaysBinding, in: 1...365)
            }
            if let birthDate = item.birthDate {
                LabeledContent("Huidige leeftijd", value: "\(RecurrenceEngine.currentAge(for: birthDate))")
            }
        } else if item.themeRawValue == MacRecurringCategoryStore.holidayID {
            Picker("Regel", selection: $item.recurrenceKindRawValue) {
                Text("Feestdag op vaste dag").tag(RecurrenceKind.annualFixed.rawValue)
                Text("Weekdag van een maand").tag(RecurrenceKind.annualOrdinalWeekday.rawValue)
            }
            if item.recurrenceKind == .annualFixed {
                DatePicker("Datum", selection: $item.nextDate, displayedComponents: .date)
            } else {
                monthPicker
                ordinalPicker
                weekdayPicker
            }
        } else {
            DatePicker(item.recurrenceKind == .yearly ? "Startdatum" : "Eerstvolgende datum", selection: $item.nextDate, displayedComponents: .date)
            Picker("Type", selection: $item.recurrenceKindRawValue) {
                Text("Vaste regelmaat").tag(RecurrenceKind.interval.rawValue)
                Text("Maandelijks op datum").tag(RecurrenceKind.monthlyDay.rawValue)
                Text("Maandelijks op weekdag").tag(RecurrenceKind.monthlyOrdinalWeekday.rawValue)
                Text("Elk kwartaal").tag(RecurrenceKind.quarterly.rawValue)
                Text("Jaarlijks (jubileum)").tag(RecurrenceKind.yearly.rawValue)
                Text("Flexibel (ongeveer)").tag(RecurrenceKind.approximateInterval.rawValue)
            }
            switch item.recurrenceKind {
            case .monthlyDay:
                Stepper("Elke \(item.monthlyDay)e van de maand", value: $item.monthlyDay, in: 1...31)
            case .monthlyOrdinalWeekday:
                ordinalPicker; weekdayPicker
            case .interval, .approximateInterval:
                Stepper("Elke \(item.intervalValue)", value: $item.intervalValue, in: 1...99)
                Picker("Eenheid", selection: $item.intervalUnitRawValue) {
                    Text("Dagen").tag(RecurrenceUnit.day.rawValue)
                    Text("Weken").tag(RecurrenceUnit.week.rawValue)
                    Text("Maanden").tag(RecurrenceUnit.month.rawValue)
                    Text("Jaren").tag(RecurrenceUnit.year.rawValue)
                }
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

    private var monthPicker: some View {
        Picker("Maand", selection: $item.annualMonth) {
            ForEach(1...12, id: \.self) { Text(AppCalendar.monthName($0)).tag($0) }
        }
    }
    private var ordinalPicker: some View {
        Picker("Welke", selection: $item.monthlyOrdinal) {
            Text("Eerste").tag(1); Text("Tweede").tag(2); Text("Derde").tag(3); Text("Vierde").tag(4); Text("Laatste").tag(5)
        }
    }
    private var weekdayPicker: some View {
        Picker("Weekdag", selection: $item.monthlyWeekday) {
            ForEach(1...7, id: \.self) { Text(RecurrenceEngine.weekdayName($0).capitalized).tag($0) }
        }
    }
    private var birthDateBinding: Binding<Date> { Binding(get: { item.birthDate ?? item.nextDate }, set: { item.birthDate = AppCalendar.startOfDay($0); item.nextDate = AppCalendar.startOfDay($0) }) }
    private var reminderEnabledBinding: Binding<Bool> { Binding(get: { item.reminderDaysBefore != nil }, set: { item.reminderDaysBefore = $0 ? 7 : nil }) }
    private var reminderDaysBinding: Binding<Int> { Binding(get: { item.reminderDaysBefore ?? 7 }, set: { item.reminderDaysBefore = $0 }) }
    private var nextDate: Date { RecurrenceEngine.nextDate(for: item) ?? item.nextDate }
    private var links: [MacRecurringLink] { MacRecurringLink.decode(item.linksData) }
    private func linkDisplayName(_ index: Int) -> String {
        let name = links[safe: index]?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Link \(index + 1)" : name
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
    private func removeLink(_ index: Int) { var value = links; guard value.indices.contains(index) else { return }; value.remove(at: index); encodeLinks(value) }
    private func encodeLinks(_ value: [MacRecurringLink]) {
        let cleaned = Array(value.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(5))
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        item.linksData = String(data: data, encoding: .utf8) ?? ""; save()
    }
    private func saveRecurrence() { item.recurrenceConfigurationVersion = 1; item.frequencyText = RecurrenceEngine.description(for: item); save() }
    private func save() { PersistenceSafety.save(modelContext) }
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
        .task { status = await ICloudStatusService.accountStatus() }
    }

    private var statusText: String {
        switch status {
        case .available: "Actief"
        case .noAccount: "Geen iCloud-account"
        case .restricted: "Beperkt"
        case .temporarilyUnavailable: "Tijdelijk niet beschikbaar"
        case .couldNotDetermine: "Onbekend"
        case nil: "Controleren…"
        @unknown default: "Onbekend"
        }
    }

    private func normalizeWeekdayLabelLength() {
        guard WeekdayLabelLengthOption(rawValue: weekdayLabelLength) == nil else { return }
        weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue
    }

    private var weekdayFormattingPickerTitle: String {
        locale.language.languageCode?.identifier == "nl" ? "Weekdagnotatie" : "Weekday formatting"
    }
}
#endif
