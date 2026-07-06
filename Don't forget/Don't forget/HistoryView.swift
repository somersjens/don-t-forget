import SwiftUI
import SwiftData
import Charts
import StoreKit

private extension View {
    @ViewBuilder
    func historyScrollCompatibility(isScrolled: Binding<Bool>) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 12
                } action: { _, newValue in
                    isScrolled.wrappedValue = newValue
                }
        } else if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 12
            } action: { _, newValue in
                isScrolled.wrappedValue = newValue
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleHistoryGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

private struct HistoryRecurringCategoryAppearance: Decodable {
    let id: String
    let title: String?
    let colorRawValue: String

    init(id: String, title: String? = nil, colorRawValue: String) {
        self.id = id
        self.title = title
        self.colorRawValue = colorRawValue
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "Alles"
    case agenda = "Agenda"
    case recurring = "Recurring"
    case todo = "Taken"

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .all: locale.localized("Alles")
        case .agenda: locale.localized("Agenda")
        case .recurring: locale.localized("Herhalingen")
        case .todo: locale.localized("Taken")
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

    @Query(
        filter: #Predicate<RecurringItem> { item in
            item.isRemoved
        },
        sort: \RecurringItem.completedAt,
        order: .reverse
    )
    private var removedRecurringItems: [RecurringItem]

    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.recurringBirthdayCategoryDeleted) private var birthdayCategoryDeleted = false
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""
    @AppStorage(SettingsKeys.historyShowsDeletedItems) private var showsDeletedItems = true
    @AppStorage(SettingsKeys.hasOpenedHistoryHelp) private var hasOpenedHistoryHelp = false
    @AppStorage(SettingsKeys.historyTutorialStep) private var historyTutorialStep = 0
    @AppStorage(SettingsKeys.hasCompletedHistoryTutorial) private var hasCompletedHistoryTutorial = false
    @AppStorage(SettingsKeys.historyTutorialExampleID) private var historyTutorialExampleID = ""

    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var isScrolled = false
    @State private var isHelpExpanded = false
    @State private var isShowingSettings = false
    @State private var recentlyRestoredRow: HistoryRow?
    @State private var dismissRestoreTask: Task<Void, Never>?
    @State private var selectedDeletionRowID: UUID?
    @State private var pendingPermanentDeletion: HistoryRow?
    @State private var permanentDeletionTask: Task<Void, Never>?
    @State private var visibleHistoryLimit = Self.pageSize
    @State private var didConfigureUITestOnboarding = false
    @FocusState private var isSearchFocused: Bool

    private var visibleOnboardingStep: Int? {
        isHelpExpanded && !hasCompletedHistoryTutorial ? historyTutorialStep : nil
    }

    private var tutorialExampleID: UUID? {
        UUID(uuidString: historyTutorialExampleID)
    }

    private var historyTutorialExampleText: String {
        locale.localized("onboarding.history.example")
    }

    private var historyTutorialSearchTerm: String {
        locale.localized("onboarding.history.searchTerm")
    }

    private var allRows: [HistoryRow] {
        let recurringColors = recurringCategoryColors
        let recurringBackgroundColors = recurringCategoryBackgroundColors
        let recurringTitles = recurringCategoryTitles
        let todoColors = todoCategoryColors
        let todoBackgroundColors = todoCategoryBackgroundColors
        let todoTitles = todoCategoryTitles
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
                    categoryTitle: recurringTitles[categoryID]
                        ?? HistoryCSVDocument.fallbackRecurringCategoryName(for: categoryID, locale: locale),
                    color: recurringColors[categoryID] ?? RecurringThemeColorOption.gray.color,
                    backgroundColor: recurringBackgroundColors[categoryID]
                        ?? RecurringThemeColorOption.gray.backgroundColor
                )
            }
        let removedRecurringRows = removedRecurringItems.map { item in
            HistoryRow(
                recurringItem: item,
                categoryTitle: recurringTitles[item.themeRawValue]
                    ?? HistoryCSVDocument.fallbackRecurringCategoryName(for: item.themeRawValue, locale: locale),
                color: recurringColors[item.themeRawValue] ?? RecurringThemeColorOption.gray.color,
                backgroundColor: recurringBackgroundColors[item.themeRawValue]
                    ?? RecurringThemeColorOption.gray.backgroundColor
            )
        }
        let todoRows = todos
            .map { todo in
                HistoryRow(
                    todo: todo,
                    categoryTitle: todoTitles[todo.bucketRawValue] ?? todo.bucketRawValue,
                    color: todoColors[todo.bucketRawValue] ?? RecurringThemeColorOption.gray.color,
                    backgroundColor: todoBackgroundColors[todo.bucketRawValue]
                        ?? RecurringThemeColorOption.gray.backgroundColor
                )
            }

        return (agendaRows + recurringRows + removedRecurringRows + todoRows).sorted {
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

    private var recurringCategoryTitles: [String: String] {
        Dictionary(uniqueKeysWithValues: recurringCategoryAppearances.compactMap { appearance in
            guard let title = appearance.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            return (appearance.id, title)
        })
    }

    private var todoCategoryTitles: [String: String] {
        Dictionary(uniqueKeysWithValues: TodoGroupStore.decode(todoGroupsData).map {
            ($0.id, $0.title)
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
                    if isHelpExpanded {
                        HistoryHelpCard(
                            locale: locale,
                            step: historyTutorialStep,
                            isDeleteRevealed: selectedDeletionRowID == tutorialExampleID,
                            isCompleted: hasCompletedHistoryTutorial,
                            previous: showPreviousHistoryTutorialStep,
                            next: showNextHistoryTutorialStep,
                            replay: replayHistoryTutorial,
                            close: { isHelpExpanded = false }
                        )
                        .padding(.bottom, 2)
                    }

                    HistoryFilterBar(
                        selection: $filter,
                        count: { count(for: $0, among: historyRows) },
                        isOnboardingHighlighted: visibleOnboardingStep == 0,
                        selected: {
                            dismissPermanentDeleteMode()
                            completeHistoryTutorialAction(for: 0)
                        }
                    )

                    HistorySummaryCard(
                        total: chartRows.count,
                        lastSevenDays: completedLastSevenDays(in: chartRows),
                        completionDates: chartRows.map(\.completedAt),
                        isDemoActive: isHistoryDemoActive,
                        activateDemoData: activateHistoryDemoData,
                        deactivateDemoData: deactivateHistoryDemoData
                    )
                    .simultaneousGesture(TapGesture().onEnded(dismissPermanentDeleteMode))

                    HistorySearchBar(
                        text: $searchText,
                        isFocused: $isSearchFocused,
                        isOnboardingHighlighted: visibleOnboardingStep == 1,
                        tapped: dismissPermanentDeleteMode
                    )

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
                                tutorialExampleID: tutorialExampleID,
                                onboardingStep: visibleOnboardingStep,
                                hasActivePermanentDeleteMode: selectedDeletionRowID != nil,
                                revealPermanentDelete: revealPermanentDelete,
                                permanentlyDelete: beginPermanentDeletion,
                                dismissPermanentDelete: dismissPermanentDeleteMode,
                                restore: restore
                            )
                        }
                        if remainingRowCount > 0 {
                            Button {
                                visibleHistoryLimit += Self.pageSize
                            } label: {
                                Label(
                                    locale.localizedFormat(
                                        "history.loadOlder",
                                        min(Self.pageSize, remainingRowCount)
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
                .adaptiveReadableWidth()
            }
            .historyScrollCompatibility(isScrolled: $isScrolled)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    HistoryTopTitle(
                        locale: locale,
                        showsInfoHint: !hasOpenedHistoryHelp,
                        isHelpExpanded: isHelpExpanded,
                        toggleHelp: toggleHelp
                    )
                        .opacity(isScrolled ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: isScrolled)

                    HStack {
                        Spacer()

                        Button {
                            dismissPermanentDeleteMode()
                            if visibleOnboardingStep == 5 {
                                finishHistoryTutorial()
                            }
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .compatibleHistoryGlassEffect()
                        .background(
                            visibleOnboardingStep == 5 ? Color.brandLightBlue : Color.clear,
                            in: Circle()
                        )
                        .accessibilityLabel("Instellingen")
                        .overlay {
                            if visibleOnboardingStep == 5 {
                                Circle()
                                    .stroke(Color.brandHardBlue, lineWidth: 3)
                                    .padding(-4)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .adaptiveReadableWidth()
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                Group {
                    if let pendingPermanentDeletion {
                        permanentDeletionBar(title: pendingPermanentDeletion.title)
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let recentlyRestoredRow {
                        restoreBar(title: recentlyRestoredRow.title)
                            .padding(.horizontal, 14)
                            .overlay {
                                if visibleOnboardingStep == 3 {
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.brandHardBlue, lineWidth: 3)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, -4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .adaptiveReadableWidth()
                .padding(.bottom, 4)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onAppear {
                modelContext.undoManager = undoManager
                configureUITestOnboardingIfNeeded()
                localizeHistoryTutorialExampleIfPresent()
                ensureHistoryTutorialExampleExists()
            }
            .onChange(of: locale.identifier) { _, _ in
                localizeHistoryTutorialExampleIfPresent()
            }
            .onChange(of: filter) { _, _ in
                dismissPermanentDeleteMode()
                visibleHistoryLimit = Self.pageSize
            }
            .onChange(of: showsDeletedItems) { _, _ in
                visibleHistoryLimit = Self.pageSize
            }
            .onChange(of: searchText) { _, _ in
                dismissPermanentDeleteMode()
                visibleHistoryLimit = Self.pageSize
                if visibleOnboardingStep == 1,
                   searchText.localizedStandardContains(historyTutorialSearchTerm) {
                    isSearchFocused = false
                    completeHistoryTutorialAction(for: 1)
                }
            }
            .onDisappear {
                dismissPermanentDeleteMode()
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
        _ = PersistenceSafety.save(modelContext)
    }

    private func toggleHelp() {
        dismissPermanentDeleteMode()
        hasOpenedHistoryHelp = true
        if !isHelpExpanded && !hasCompletedHistoryTutorial {
            ensureHistoryTutorialExampleExists()
        }
        isHelpExpanded.toggle()
    }

    private func configureUITestOnboardingIfNeeded() {
#if DEBUG
        guard !didConfigureUITestOnboarding,
              ProcessInfo.processInfo.environment["UI_TEST_RESET_HISTORY_ONBOARDING"] == "1" else {
            return
        }
        didConfigureUITestOnboarding = true
        hasOpenedHistoryHelp = false
        historyTutorialStep = 0
        hasCompletedHistoryTutorial = false
        historyTutorialExampleID = ""
#endif
    }

    private func ensureHistoryTutorialExampleExists(reset: Bool = false) {
        guard !hasCompletedHistoryTutorial || reset else { return }

        if let entry = tutorialExampleEntry() {
            if entry.rawText != historyTutorialExampleText {
                entry.rawText = historyTutorialExampleText
                entry.refreshParsedFields()
                _ = PersistenceSafety.save(modelContext)
            }
            if reset {
                normalizeTutorialExampleToHistory(entry)
            }
            return
        }

        let entry = DayEntry(date: .now, rawText: historyTutorialExampleText)
        entry.isDone = true
        entry.completedAt = .now
        modelContext.insert(entry)
        historyTutorialExampleID = entry.id.uuidString
        _ = PersistenceSafety.save(modelContext)
    }

    private func localizeHistoryTutorialExampleIfPresent() {
        guard let entry = tutorialExampleEntry(), entry.rawText != historyTutorialExampleText else {
            return
        }
        entry.rawText = historyTutorialExampleText
        entry.refreshParsedFields()
        _ = PersistenceSafety.save(modelContext)
    }

    private func tutorialExampleEntry() -> DayEntry? {
        guard let id = tutorialExampleID else { return nil }
        let allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        return allEntries.first { $0.id == id }
    }

    private func tutorialExampleRow() -> HistoryRow? {
        guard let entry = tutorialExampleEntry() else { return nil }
        return HistoryRow(
            entry: entry,
            source: .agenda,
            color: RecurringThemeColorOption.gray.color,
            backgroundColor: RecurringThemeColorOption.gray.backgroundColor
        )
    }

    private func normalizeTutorialExampleToHistory(_ entry: DayEntry) {
        permanentDeletionTask?.cancel()
        permanentDeletionTask = nil
        dismissRestoreTask?.cancel()
        dismissRestoreTask = nil
        pendingPermanentDeletion = nil
        recentlyRestoredRow = nil
        selectedDeletionRowID = nil
        entry.isDone = true
        entry.isRemoved = false
        entry.completedAt = .now
        _ = PersistenceSafety.save(modelContext)
    }

    private func showPreviousHistoryTutorialStep() {
        if hasCompletedHistoryTutorial {
            hasCompletedHistoryTutorial = false
            showHistoryTutorialStep(HistoryHelpCard.stepCount - 1)
            return
        }
        guard historyTutorialStep > 0 else { return }
        showHistoryTutorialStep(historyTutorialStep - 1)
    }

    private func showNextHistoryTutorialStep() {
        switch historyTutorialStep {
        case 1:
            searchText = historyTutorialSearchTerm
            showHistoryTutorialStep(2)
        case 2:
            if let row = tutorialExampleRow() {
                restore(row)
            } else {
                ensureHistoryTutorialExampleExists(reset: true)
                showHistoryTutorialStep(3)
            }
        case 3:
            undoRestore()
        case 4:
            guard let row = tutorialExampleRow() else {
                ensureHistoryTutorialExampleExists(reset: true)
                return
            }
            if selectedDeletionRowID == row.id {
                beginPermanentDeletion(row)
            } else {
                revealPermanentDelete(row)
            }
        case HistoryHelpCard.stepCount - 1:
            finishHistoryTutorial()
        default:
            showHistoryTutorialStep(historyTutorialStep + 1)
        }
    }

    private func showHistoryTutorialStep(_ requestedStep: Int) {
        let target = min(max(requestedStep, 0), HistoryHelpCard.stepCount - 1)
        ensureHistoryTutorialExampleExists()

        if target <= 2 || target == 4 {
            if let entry = tutorialExampleEntry() {
                normalizeTutorialExampleToHistory(entry)
            }
        }

        switch target {
        case 0:
            filter = .all
            searchText = ""
        case 1:
            searchText = ""
        case 2, 4:
            filter = .all
            searchText = historyTutorialSearchTerm
        case 3:
            filter = .all
            searchText = historyTutorialSearchTerm
            if let row = tutorialExampleRow() {
                restore(row)
                dismissRestoreTask?.cancel()
                dismissRestoreTask = nil
            }
        default:
            break
        }

        historyTutorialStep = target
    }

    private func completeHistoryTutorialAction(for step: Int) {
        guard visibleOnboardingStep == step else { return }
        if step == HistoryHelpCard.stepCount - 1 {
            finishHistoryTutorial()
        } else {
            showHistoryTutorialStep(step + 1)
        }
    }

    private func finishHistoryTutorial() {
        hasCompletedHistoryTutorial = true
        dismissRestoreTask?.cancel()
        recentlyRestoredRow = nil
    }

    private func replayHistoryTutorial() {
        hasCompletedHistoryTutorial = false
        historyTutorialStep = 0
        filter = .all
        searchText = ""
        ensureHistoryTutorialExampleExists(reset: true)
    }

    private func deactivateHistoryDemoData() {
        DemoData.removeHistoryData(in: modelContext)
        _ = PersistenceSafety.save(modelContext)
    }

    private func restore(_ row: HistoryRow) {
        selectedDeletionRowID = nil
        dismissRestoreTask?.cancel()
        withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
            row.restore()
            recentlyRestoredRow = row
        }
        _ = PersistenceSafety.save(modelContext)

        if visibleOnboardingStep == 2, row.id == tutorialExampleID {
            historyTutorialStep = 3
        } else {
            dismissRestoreTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                hideRestoreBar()
            }
        }
    }

    private func revealPermanentDelete(_ row: HistoryRow) {
        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
            if let selectedDeletionRowID, selectedDeletionRowID != row.id {
                self.selectedDeletionRowID = nil
            } else {
                selectedDeletionRowID = selectedDeletionRowID == row.id ? nil : row.id
            }
        }
    }

    private func dismissPermanentDeleteMode() {
        guard selectedDeletionRowID != nil else { return }
        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
            selectedDeletionRowID = nil
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

        if visibleOnboardingStep == 4, row.id == tutorialExampleID {
            historyTutorialStep = 5
            searchText = ""
            isSearchFocused = false
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
        do {
            try AppBackupService.createAutomaticSnapshot(
                from: modelContext,
                reason: "before-permanent-delete"
            )
        } catch {
            PersistenceSafety.report(error)
            pendingPermanentDeletion = nil
            return
        }
        row.permanentlyDelete(in: modelContext)
        _ = PersistenceSafety.save(modelContext)
        withAnimation(.easeOut(duration: 0.2)) {
            if pendingPermanentDeletion?.id == row.id {
                pendingPermanentDeletion = nil
            }
        }
    }

    private func permanentDeletionBar(title: String) -> some View {
        UndoFeedbackBar(
            iconSystemName: "trash.fill",
            iconColor: .red,
            message: locale.localizedFormat("feedback.permanentlyDeleted", title),
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoPermanentDeletion
        )
    }

    private func hideRestoreBar() {
        dismissRestoreTask?.cancel()
        dismissRestoreTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyRestoredRow = nil
        }
    }

    private func restoreBar(title: String) -> some View {
        UndoFeedbackBar(
            iconSystemName: "arrow.uturn.backward.circle.fill",
            iconColor: .blue,
            message: locale.localizedFormat("feedback.restored", title),
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoRestore
        )
    }

    private func undoRestore() {
        guard let row = recentlyRestoredRow else { return }
        row.undoRestore()
        _ = PersistenceSafety.save(modelContext)
        hideRestoreBar()
        if visibleOnboardingStep == 3, row.id == tutorialExampleID {
            historyTutorialStep = 4
        }
    }
}

private struct HistoryTopTitle: View {
    let locale: Locale
    let showsInfoHint: Bool
    let isHelpExpanded: Bool
    let toggleHelp: () -> Void

    var body: some View {
        Button(action: toggleHelp) {
            HStack(spacing: 6) {
                Text(AppSection.history.title(for: locale))
                    .font(.system(size: 26, weight: .bold))

                if showsInfoHint {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brandHardBlue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locale.localized("Uitleg over Afgerond"))
        .accessibilityValue(isHelpExpanded
            ? locale.localized("Uitgeklapt")
            : locale.localized("Ingeklapt"))
        .accessibilityHint(locale.localized("Tik om de uitleg in of uit te klappen"))
    }
}

private struct HistoryHelpStep: Identifiable {
    let id: Int
    let icon: String
    let key: String

    func text(for locale: Locale) -> String {
        locale.localized(key)
    }
}

private struct HistoryHelpCard: View {
    static let stepCount = 6

    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    let locale: Locale
    let step: Int
    let isDeleteRevealed: Bool
    let isCompleted: Bool
    let previous: () -> Void
    let next: () -> Void
    let replay: () -> Void
    let close: () -> Void

    private let steps = [
        HistoryHelpStep(
            id: 0,
            icon: "line.3.horizontal.decrease.circle",
            key: "Gebruik de filterknoppen om alleen afgeronde items van een bepaalde tab te zien.",
        ),
        HistoryHelpStep(
            id: 1,
            icon: "magnifyingglass",
            key: "onboarding.history.searchInstruction",
        ),
        HistoryHelpStep(
            id: 2,
            icon: "arrow.uturn.backward",
            key: "Zet een item terug naar waar het vandaan kwam met de terugzetknop.",
        ),
        HistoryHelpStep(
            id: 3,
            icon: "arrow.counterclockwise",
            key: "Toch niet? Tik onderin op Ongedaan maken. Normaal heb je hiervoor 5 seconden; tijdens deze uitleg blijft de melding staan.",
        ),
        HistoryHelpStep(
            id: 4,
            icon: "trash",
            key: "Tik eerst op het icoon van het item. Tik daarna op het prullenbakje om het definitief te verwijderen.",
        ),
        HistoryHelpStep(
            id: 5,
            icon: "gearshape",
            key: "Nog veel meer handige instellingen vind je achter het menu rechtsbovenin.",
        )
    ]

    private var currentStep: HistoryHelpStep {
        steps[min(max(step, 0), steps.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isCompleted {
                completedContent
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Image(systemName: currentStep.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.brandHardBlue)
                                .frame(width: 16, height: 16)

                            Text(locale.localizedFormat("tutorial.step", step + 1, Self.stepCount))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.brandHardBlue)
                        }

                        Text(step == 4 && isDeleteRevealed
                            ? locale.localized("Tik nu op het prullenbakje om het item definitief te verwijderen.")
                            : currentStep.text(for: locale))
                            .font(.system(size: 16, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: step == 5 ? 0 : 84, alignment: .topLeading)

                    if step == 5 {
                        supportButtons
                    }

                    navigationControls
                        .id("\(step)-\(isDeleteRevealed)")
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tutorialCardStyle(isCompleted: isCompleted, close: close)
    }

    private var navigationControls: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(step == 0)
            .opacity(step == 0 ? 0.25 : 1)
            .accessibilityLabel(locale.localized("Vorige stap"))

            Spacer()

            Button(action: next) {
                Image(systemName: "arrow.forward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.brandHardBlue)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(locale.localized("Volgende stap"))
        }
    }

    private var supportButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let url = URL(string: "mailto:hak@hakketjak.nl") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "envelope")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    supportLinkText(
                        leading: locale.localized("Hulp nodig? Stuur ons een "),
                        accent: locale.localized("onboarding.history.emailAccent")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(locale.localized("Hulp nodig? Stuur ons een email"))

            Button {
                if let appStoreID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String,
                   !appStoreID.isEmpty,
                   let url = URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review") {
                    openURL(url)
                } else {
                    requestReview()
                }
            } label: {
                let reviewLink = supportLinkText(
                    leading: locale.localized("Schrijf een "),
                    accent: "review"
                )
                let reviewSuffix = Text(locale.localized(" over de app"))
                    .foregroundStyle(.primary)

                HStack(spacing: 7) {
                    Image(systemName: "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text("\(reviewLink)\(reviewSuffix)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel(locale.localized("Schrijf een review over de app"))
        }
        .font(.system(size: 14, weight: .medium))
    }

    private func supportLinkText(leading: String, accent: String) -> Text {
        let leadingText = Text(leading).foregroundStyle(.primary)
        let accentText = Text(accent)
            .fontWeight(.semibold)
            .foregroundStyle(Color.brandHardBlue)
        return Text("\(leadingText)\(accentText)")
    }

    private var completedContent: some View {
        TutorialCompletionContent(
            message: locale.localized("Je weet nu precies hoe Afgerond werkt."),
            replayTitle: locale.localized("Opnieuw"),
            backAccessibilityLabel: locale.localized("Vorige stap"),
            closeAccessibilityLabel: locale.localized("Sluiten"),
            back: previous,
            replay: replay,
            close: close
        )
    }
}

private struct HistorySummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    let total: Int
    let lastSevenDays: Int
    let completionDates: [Date]
    let isDemoActive: Bool
    let activateDemoData: () -> Void
    let deactivateDemoData: () -> Void
    @State private var isExpanded = false
    @State private var isPressingDemoActivation = false

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
                .scaleEffect(isPressingDemoActivation ? 0.92 : 1)
                .animation(.easeInOut(duration: 0.18), value: isPressingDemoActivation)
                .contentShape(RoundedRectangle(cornerRadius: 11))
                .onTapGesture {
                    guard isDemoActive else { return }
                    deactivateDemoData()
                }
                .onLongPressGesture(minimumDuration: 3, maximumDistance: 30) {
                    guard !isDemoActive else { return }
                    activateDemoAndExpand()
                } onPressingChanged: { isPressing in
                    isPressingDemoActivation = !isDemoActive && isPressing
                }
                .accessibilityAction(named: isDemoActive ? "Demodata verwijderen" : "Demodata activeren") {
                    if isDemoActive {
                        deactivateDemoData()
                    } else {
                        activateDemoAndExpand()
                    }
                }
                .accessibilityHint(isDemoActive
                    ? locale.localized("Tik om demodata te verwijderen.")
                    : locale.localized("Houd 3 seconden ingedrukt om demodata te activeren."))

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

    private func activateDemoAndExpand() {
        activateDemoData()
        withAnimation(.snappy(duration: 0.38, extraBounce: 0)) {
            isExpanded = true
        }
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
        case .days: locale.localized("Afgelopen 7 dagen")
        case .weeks: locale.localized("Afgelopen 10 weken")
        case .months: locale.localized("Afgelopen 12 maanden")
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
    let isOnboardingHighlighted: Bool
    let selected: () -> Void

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
                    selected()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .overlay {
            if isOnboardingHighlighted {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.brandHardBlue, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
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
        .accessibilityIdentifier("history.filter.\(filter.rawValue)")
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
    @FocusState.Binding var isFocused: Bool
    let isOnboardingHighlighted: Bool
    let tapped: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                locale.localized("Zoek in Afgerond"),
                text: $text
            )
            .font(.system(size: 15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(locale.localized("Zoekopdracht wissen"))
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isOnboardingHighlighted ? Color.brandHardBlue : Color.primary.opacity(0.045),
                    lineWidth: isOnboardingHighlighted ? 3 : 1
                )
        }
        .simultaneousGesture(TapGesture().onEnded(tapped))
    }
}

private struct HistoryDayCard: View {
    @Environment(\.locale) private var locale

    let section: HistoryDaySection
    let searchText: String
    let selectedDeletionRowID: UUID?
    let tutorialExampleID: UUID?
    let onboardingStep: Int?
    let hasActivePermanentDeleteMode: Bool
    let revealPermanentDelete: (HistoryRow) -> Void
    let permanentlyDelete: (HistoryRow) -> Void
    let dismissPermanentDelete: () -> Void
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
                        highlightsRestore: onboardingStep == 2 && tutorialExampleID == row.id,
                        highlightsSourceIcon: onboardingStep == 4
                            && tutorialExampleID == row.id
                            && selectedDeletionRowID != row.id,
                        highlightsPermanentDelete: onboardingStep == 4
                            && tutorialExampleID == row.id
                            && selectedDeletionRowID == row.id,
                        hasActivePermanentDeleteMode: hasActivePermanentDeleteMode,
                        revealPermanentDelete: { revealPermanentDelete(row) },
                        permanentlyDelete: { permanentlyDelete(row) },
                        dismissPermanentDelete: dismissPermanentDelete,
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
    let highlightsRestore: Bool
    let highlightsSourceIcon: Bool
    let highlightsPermanentDelete: Bool
    let hasActivePermanentDeleteMode: Bool
    let revealPermanentDelete: () -> Void
    let permanentlyDelete: () -> Void
    let dismissPermanentDelete: () -> Void
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
            .overlay {
                if highlightsSourceIcon {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.brandHardBlue, lineWidth: 3)
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(highlightedTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .strikethrough(row.isRemoved)

                HStack(spacing: 5) {
                    Text(row.categoryTitle)
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
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(RecurringThemeColorOption.red.backgroundColor, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
                .accessibilityLabel("Definitief verwijderen")
                .overlay {
                    if highlightsPermanentDelete {
                        Circle()
                            .stroke(Color.brandHardBlue, lineWidth: 3)
                            .padding(-4)
                            .allowsHitTesting(false)
                    }
                }
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
                .accessibilityLabel(locale.localizedFormat(
                    "history.restoreTo",
                    row.source.title(for: locale)
                ))
                .overlay {
                    if highlightsRestore {
                        Circle()
                            .stroke(Color.brandHardBlue, lineWidth: 3)
                            .padding(-4)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasActivePermanentDeleteMode {
                dismissPermanentDelete()
            }
        }
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
            return locale.localized("Geen zoekresultaten")
        }
        if filter == .all {
            return locale.localized("Nog niets afgerond")
        }
        return locale.localizedFormat(
            "history.noCompletedFilter",
            filter.title(for: locale).lowercased()
        )
    }

    private var subtitle: String {
        hasSearchQuery
            ? locale.localized("Probeer een andere zoekopdracht of wis de zoekbalk.")
            : locale.localized("Afgeronde items verschijnen hier automatisch en kun je altijd weer terugzetten.")
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
        if AppCalendar.calendar.isDateInToday(date) { return locale.localized("Vandaag") }
        if AppCalendar.calendar.isDateInYesterday(date) { return locale.localized("Gisteren") }
        return AppCalendar.localizedDate(date, template: "EEEEdMMMM")
    }

}

private enum HistorySource {
    case agenda
    case recurring
    case todo

    func title(for locale: Locale) -> String {
        switch self {
        case .agenda: locale.localized("Agenda")
        case .recurring: locale.localized("Herhalingen")
        case .todo: locale.localized("Taken")
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
    let categoryTitle: String
    let completedAt: Date
    let color: Color
    let backgroundColor: Color
    let isDone: Bool
    let isRemoved: Bool
    private let originalCompletedAt: Date?
    private let entry: DayEntry?
    private let todo: TodoItem?
    private let recurringItem: RecurringItem?

    init(
        entry: DayEntry,
        source: HistorySource,
        categoryTitle: String? = nil,
        color: Color,
        backgroundColor: Color
    ) {
        id = entry.id
        title = entry.rawText
        self.source = source
        self.categoryTitle = categoryTitle ?? source.title(for: AppCalendar.locale)
        completedAt = entry.completedAt ?? entry.date
        self.color = color
        self.backgroundColor = backgroundColor
        isDone = entry.isDone
        isRemoved = entry.isRemoved
        originalCompletedAt = entry.completedAt
        self.entry = entry
        todo = nil
        recurringItem = nil
    }

    init(todo: TodoItem, categoryTitle: String, color: Color, backgroundColor: Color) {
        id = todo.id
        title = todo.text
        source = .todo
        self.categoryTitle = categoryTitle
        completedAt = todo.completedAt ?? todo.createdAt
        self.color = color
        self.backgroundColor = backgroundColor
        isDone = todo.isDone
        isRemoved = todo.isRemoved
        originalCompletedAt = todo.completedAt
        entry = nil
        self.todo = todo
        recurringItem = nil
    }

    init(recurringItem: RecurringItem, categoryTitle: String, color: Color, backgroundColor: Color) {
        id = recurringItem.id
        title = recurringItem.title
        source = .recurring
        self.categoryTitle = categoryTitle
        completedAt = recurringItem.completedAt ?? recurringItem.createdAt
        self.color = color
        self.backgroundColor = backgroundColor
        isDone = false
        isRemoved = recurringItem.isRemoved
        originalCompletedAt = recurringItem.completedAt
        entry = nil
        todo = nil
        self.recurringItem = recurringItem
    }

    func restore() {
        entry?.isDone = false
        entry?.isRemoved = false
        entry?.completedAt = nil
        todo?.isDone = false
        todo?.isRemoved = false
        todo?.completedAt = nil
        recurringItem?.isRemoved = false
        recurringItem?.completedAt = nil
    }

    func undoRestore() {
        entry?.isDone = isDone
        entry?.isRemoved = isRemoved
        entry?.completedAt = originalCompletedAt
        todo?.isDone = isDone
        todo?.isRemoved = isRemoved
        todo?.completedAt = originalCompletedAt
        recurringItem?.isRemoved = isRemoved
        recurringItem?.completedAt = originalCompletedAt
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
        if let recurringItem {
            modelContext.delete(recurringItem)
        }
    }
}
