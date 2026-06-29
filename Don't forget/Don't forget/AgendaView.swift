import SwiftUI
import SwiftData

private struct AgendaRecurringCategoryAppearance: Decodable {
    let id: String
    let colorRawValue: String
}

struct AgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    @Query(sort: \DayEntry.date, order: .forward)
    private var entries: [DayEntry]

    @FocusState private var focusedField: AgendaField?
    @State private var isScrolled = false
    @State private var activeMoveEntryID: UUID?
    @State private var moveDraftDate = AppCalendar.startOfDay(.now)
    @State private var scrollTargetDate: Date?
    @State private var loadedFutureWeeks = 26

    @AppStorage(SettingsKeys.weekStart) private var weekStartSetting = WeekStartOption.monday.rawValue
    @AppStorage(SettingsKeys.weekNumberRule) private var weekNumberSetting = WeekNumberRule.iso8601.rawValue
    @AppStorage(SettingsKeys.language) private var languageSetting = AppLanguage.system.rawValue
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""

    private var todoGroups: [TodoGroup] {
        TodoGroupStore.decode(todoGroupsData)
    }

    private var openPastDates: Set<Date> {
        let today = AppCalendar.startOfDay(.now)
        return Set(entries.compactMap { entry in
            guard !entry.isDone, entry.date < today else { return nil }
            return AppCalendar.startOfDay(entry.date)
        })
    }

    private var entriesByDay: [Date: [DayEntry]] {
        Dictionary(grouping: entries) { AppCalendar.startOfDay($0.date) }
    }

    private var activeMoveEntryHasTime: Bool {
        guard let activeMoveEntryID else { return false }
        return entries.first(where: { $0.id == activeMoveEntryID })?.hasTime == true
    }

    private var weeks: [WeekSection] {
        let today = AppCalendar.startOfDay(.now)
        let oldestOpenDate = entries
            .filter { !$0.isDone && $0.date < today }
            .map(\.date)
            .min()
        let startDate = oldestOpenDate ?? today
        let defaultEndDate = AppCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: loadedFutureWeeks,
            to: today
        ) ?? today
        let endDate = max(defaultEndDate, AppCalendar.startOfDay(moveDraftDate))
        let startOfFirstWeek = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        let startOfLastWeek = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: endDate)?.start ?? endDate
        let weekCount = (AppCalendar.calendar.dateComponents(
            [.weekOfYear],
            from: startOfFirstWeek,
            to: startOfLastWeek
        ).weekOfYear ?? 104) + 1

        let openDates = openPastDates
        return AppCalendar.weekSections(
            startingFrom: startDate,
            numberOfWeeks: weekCount
        )
        .filter { week in
            week.days.contains { day in
                day.date >= today
                    || openDates.contains(day.date)
            }
        }
    }

    var body: some View {
        let groupedEntries = entriesByDay
        let visibleWeeks = weeks
        let loadedWeekLimit = loadedFutureWeeks

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(visibleWeeks.enumerated()), id: \.element.id) { index, week in
                            WeekCard(
                                week: week,
                                entriesByDay: groupedEntries,
                                focusedField: $focusedField,
                                moveEntry: moveEntry,
                                moveEntryOneStep: moveEntryOneStep,
                                moveEntryToTodo: moveEntryToTodo,
                                todoGroups: todoGroups,
                                activeMoveEntryID: $activeMoveEntryID,
                                activeMoveEntryHasTime: activeMoveEntryHasTime,
                                moveDraftDate: $moveDraftDate,
                                toggleMoveControls: toggleMoveControls,
                                scrollToDate: { date in
                                    scrollTargetDate = AppCalendar.startOfDay(date)
                                }
                            )
                            .id(AgendaScrollTarget.week(week.startDate))
                            .onAppear {
                                if index >= visibleWeeks.count - 5 {
                                    loadMoreFutureWeeks(ifCurrentLimitIs: loadedWeekLimit)
                                }
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
                .onChange(of: scrollTargetDate) { _, targetDate in
                    guard let targetDate else { return }

                    Task { @MainActor in
                        await Task.yield()
                        guard let weekStart = AppCalendar.calendar.dateInterval(
                            of: .weekOfYear,
                            for: targetDate
                        )?.start else {
                            scrollTargetDate = nil
                            return
                        }

                        proxy.scrollTo(
                            AgendaScrollTarget.week(weekStart),
                            anchor: .center
                        )
                        await Task.yield()
                        await Task.yield()
                        withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                            proxy.scrollTo(
                                AgendaScrollTarget.day(targetDate),
                                anchor: .center
                            )
                        }
                        scrollTargetDate = nil
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("Kalender")
                        .font(.system(size: 26, weight: .bold))
                        .opacity(isScrolled ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: isScrolled)

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            undoManager?.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(!(undoManager?.canUndo ?? false))
                        .accessibilityLabel("Laatste wijziging terugdraaien")

                        Button {
                            focusedField = nil
                            activeMoveEntryID = nil
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(focusedField == nil && activeMoveEntryID == nil)
                        .accessibilityLabel("Bewerken afsluiten")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .onAppear {
                modelContext.undoManager = undoManager
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue == nil {
                    try? modelContext.save()
                }
            }
        }
    }

    private func moveEntry(_ entryID: UUID, to targetDate: Date, insertionIndex: Int? = nil) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }

        let day = AppCalendar.startOfDay(targetDate)
        let targetEntries = entries
            .filter { AppCalendar.isSameDay($0.date, day) && $0.id != entryID }
            .sorted(by: sortEntries)
        let targetIndex = min(max(insertionIndex ?? targetEntries.count, 0), targetEntries.count)

        focusedField = nil
        entry.date = day
        moveDraftDate = day
        if entry.recurringItemIdentifier != nil {
            entry.recurringDateOverride = day
        }
        entry.refreshParsedFields()
        renumber(entries: targetEntries, inserting: entry, at: targetIndex)
        try? modelContext.save()
    }

    private func loadMoreFutureWeeks(ifCurrentLimitIs expectedLimit: Int) {
        guard loadedFutureWeeks == expectedLimit, loadedFutureWeeks < 105 else { return }
        loadedFutureWeeks = min(loadedFutureWeeks + 13, 105)
    }

    private func moveEntryToStartOfUntimedEntries(_ entryID: UUID, on targetDate: Date) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }

        let day = AppCalendar.startOfDay(targetDate)
        let targetEntries = entries
            .filter {
                AppCalendar.isSameDay($0.date, day)
                    && !$0.hasTime
                    && $0.id != entryID
            }
            .sorted(by: sortEntries)

        focusedField = nil
        entry.date = day
        moveDraftDate = day
        if entry.recurringItemIdentifier != nil {
            entry.recurringDateOverride = day
        }
        entry.refreshParsedFields()
        entry.manualOrder = (targetEntries.map(\.manualOrder).min() ?? 0) - 1
        try? modelContext.save()
    }

    private func toggleMoveControls(for entry: DayEntry) {
        focusedField = nil
        if activeMoveEntryID == entry.id {
            activeMoveEntryID = nil
        } else {
            activeMoveEntryID = entry.id
            moveDraftDate = AppCalendar.startOfDay(entry.date)
        }
    }

    private func moveEntryOneStep(_ entryID: UUID, direction: Int) {
        guard let entry = entries.first(where: { $0.id == entryID }),
              direction != 0 else {
            return
        }

        let day = AppCalendar.startOfDay(entry.date)

        // A parsed time determines an item's position within its day. The arrows
        // therefore move timed items by a day instead of pretending that their
        // manual order can override that time.
        if entry.hasTime {
            guard let targetDay = AppCalendar.calendar.date(
                byAdding: .day,
                value: direction < 0 ? -1 : 1,
                to: day
            ) else {
                return
            }
            moveEntry(entryID, to: targetDay)
            return
        }

        let movableEntries = entries
            .filter { AppCalendar.isSameDay($0.date, day) && !$0.hasTime && $0.id != entryID }
            .sorted(by: sortEntries)
        let currentEntries = entries
            .filter { AppCalendar.isSameDay($0.date, day) && !$0.hasTime }
            .sorted(by: sortEntries)

        guard let currentIndex = currentEntries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        let targetIndex = currentIndex + direction
        if currentEntries.indices.contains(targetIndex) {
            focusedField = nil
            renumber(entries: movableEntries, inserting: entry, at: targetIndex)
            try? modelContext.save()
            return
        }

        let dayOffset = direction < 0 ? -1 : 1
        guard let targetDay = AppCalendar.calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: day
        ) else {
            return
        }

        if direction < 0 {
            moveEntry(entryID, to: targetDay)
        } else {
            moveEntryToStartOfUntimedEntries(entryID, on: targetDay)
        }
    }

    private func moveEntryToTodo(_ entryID: UUID, groupID: String) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return
        }

        let cleanText = entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return
        }

        let allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? entries
        CalendarSyncService.deleteEventIfUnshared(for: entry, among: allEntries)

        let todo = TodoItem(text: cleanText, bucket: .today)
        todo.bucketRawValue = groupID
        modelContext.insert(todo)
        modelContext.delete(entry)
        activeMoveEntryID = nil
        try? modelContext.save()
    }

    private func sortEntries(_ first: DayEntry, _ second: DayEntry) -> Bool {
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

    private func renumber(entries targetEntries: [DayEntry], inserting entry: DayEntry, at targetIndex: Int) {
        var reordered = targetEntries
        reordered.insert(entry, at: targetIndex)

        for (index, entry) in reordered.enumerated() {
            entry.manualOrder = Double(index)
        }
    }

}

enum AgendaField: Hashable {
    case entry(UUID)
    case newEntry(Date)
}

private enum AgendaScrollTarget: Hashable {
    case week(Date)
    case day(Date)
}

private enum AgendaLayout {
    static let dateWidth: CGFloat = 47
    static let weekdayWidth: CGFloat = 19
    static let dateWeekdaySpacing: CGFloat = 2
    static let lineSpacing: CGFloat = 6
    static let lineWidth: CGFloat = 1
    static let rowSpacing: CGFloat = 8

    static var lineX: CGFloat {
        dateWidth + dateWeekdaySpacing + weekdayWidth + lineSpacing
    }

    static var prefixWidth: CGFloat {
        lineX + lineWidth
    }

    static var contentLeadingOffset: CGFloat {
        prefixWidth + rowSpacing
    }
}

struct WeekCard: View {
    let week: WeekSection
    let entriesByDay: [Date: [DayEntry]]
    let focusedField: FocusState<AgendaField?>.Binding
    let moveEntry: (UUID, Date, Int?) -> Void
    let moveEntryOneStep: (UUID, Int) -> Void
    let moveEntryToTodo: (UUID, String) -> Void
    let todoGroups: [TodoGroup]
    @Binding var activeMoveEntryID: UUID?
    let activeMoveEntryHasTime: Bool
    @Binding var moveDraftDate: Date
    let toggleMoveControls: (DayEntry) -> Void
    let scrollToDate: (Date) -> Void

    private var visibleDays: [DayInfo] {
        let today = AppCalendar.startOfDay(.now)

        return week.days.filter { day in
            if day.date >= today {
                return true
            }

            return entriesByDay[day.date]?.contains { !$0.isDone } == true
        }
    }

    private var startDateLabel: String {
        week.startDateLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("week #\(week.weekNumber) - start \(startDateLabel)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleDays) { day in
                    DayBlock(
                        day: day,
                        entries: entriesByDay[day.date] ?? [],
                        focusedField: focusedField,
                        moveEntry: moveEntry,
                        moveEntryOneStep: moveEntryOneStep,
                        moveEntryToTodo: moveEntryToTodo,
                        todoGroups: todoGroups,
                        activeMoveEntryID: $activeMoveEntryID,
                        activeMoveEntryHasTime: activeMoveEntryHasTime,
                        moveDraftDate: $moveDraftDate,
                        toggleMoveControls: toggleMoveControls,
                        scrollToDate: scrollToDate
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
            }
        }
    }
}

struct DayBlock: View {
    let day: DayInfo
    let entries: [DayEntry]
    let focusedField: FocusState<AgendaField?>.Binding
    let moveEntry: (UUID, Date, Int?) -> Void
    let moveEntryOneStep: (UUID, Int) -> Void
    let moveEntryToTodo: (UUID, String) -> Void
    let todoGroups: [TodoGroup]
    @Binding var activeMoveEntryID: UUID?
    let activeMoveEntryHasTime: Bool
    @Binding var moveDraftDate: Date
    let toggleMoveControls: (DayEntry) -> Void
    let scrollToDate: (Date) -> Void

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
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    if sortedEntries.isEmpty {
                        AgendaInputLine(
                            dateLabel: day.dateLabel,
                            weekdayLetter: day.weekdayLetter,
                            date: day.date,
                            nextOrder: 0,
                            focusedField: focusedField,
                            isMoveModeActive: activeMoveEntryID != nil,
                            isMoveTargetHighlighted: activeMoveEntryHasTime,
                            moveActiveEntryHere: moveActiveEntryHere
                        )
                    } else {
                        ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                            AgendaEntryLine(
                                dateLabel: index == 0 ? day.dateLabel : "",
                                weekdayLetter: day.weekdayLetter,
                                entry: entry,
                                focusedField: focusedField,
                                isMoveActive: activeMoveEntryID == entry.id,
                                isMoveTargetHighlighted: activeMoveEntryID != nil
                                    && activeMoveEntryID != entry.id
                                    && (activeMoveEntryHasTime || entry.hasTime),
                                moveDraftDate: $moveDraftDate,
                                handlePrefixTap: {
                                    if activeMoveEntryID == nil || activeMoveEntryID == entry.id {
                                        toggleMoveControls(entry)
                                    } else {
                                        moveActiveEntryHere()
                                    }
                                },
                                moveUp: {
                                    moveEntryOneStep(entry.id, -1)
                                },
                                moveDown: {
                                    moveEntryOneStep(entry.id, 1)
                                },
                                moveToDate: {
                                    let targetDate = AppCalendar.startOfDay(moveDraftDate)
                                    moveEntry(entry.id, targetDate, nil)
                                    scrollToDate(targetDate)
                                },
                                moveToTodo: { groupID in
                                    moveEntryToTodo(entry.id, groupID)
                                },
                                todoGroups: todoGroups,
                                finishMove: {
                                    activeMoveEntryID = nil
                                }
                            )
                        }

                        AgendaInputLine(
                            dateLabel: "",
                            weekdayLetter: day.weekdayLetter,
                            date: day.date,
                            nextOrder: Double(sortedEntries.count + 1),
                            focusedField: focusedField,
                            isMoveModeActive: activeMoveEntryID != nil,
                            isMoveTargetHighlighted: activeMoveEntryHasTime,
                            moveActiveEntryHere: moveActiveEntryHere
                        )
                    }
                }

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 17)
                    .overlay {
                        Rectangle()
                            .fill(Color.primary.opacity(0.32))
                            .frame(width: AgendaLayout.lineWidth)
                    }
                    .contentShape(Rectangle())
                    .padding(.leading, AgendaLayout.lineX - 8)
                    .padding(.vertical, 3)
                    .onTapGesture(perform: handleDayLineTap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(AgendaScrollTarget.day(day.date))
    }

    private func moveActiveEntryHere() {
        guard let activeMoveEntryID else { return }
        moveEntry(activeMoveEntryID, day.date, nil)
    }

    private func handleDayLineTap() {
        if activeMoveEntryID != nil {
            moveActiveEntryHere()
        } else {
            focusedField.wrappedValue = .newEntry(day.date)
        }
    }

}

struct AgendaEntryLine: View {
    let dateLabel: String
    let weekdayLetter: String

    @Bindable var entry: DayEntry
    let focusedField: FocusState<AgendaField?>.Binding
    let isMoveActive: Bool
    let isMoveTargetHighlighted: Bool
    @Binding var moveDraftDate: Date
    let handlePrefixTap: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveToDate: () -> Void
    let moveToTodo: (String) -> Void
    let todoGroups: [TodoGroup]
    let finishMove: () -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var isDeleting = false
    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""

    var body: some View {
        VStack(alignment: .leading, spacing: isMoveActive ? 5 : 0) {
            HStack(alignment: .top, spacing: AgendaLayout.rowSpacing) {
                AgendaLinePrefix(
                    dateLabel: dateLabel,
                    weekdayLetter: weekdayLetter,
                    isMoveActive: isMoveActive,
                    isMoveTargetHighlighted: isMoveTargetHighlighted
                )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handlePrefixTap()
                    }
                    .accessibilityLabel("Verplaatsopties")

                entryContent

                if entry.isUncertain {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                Spacer(minLength: 2)

                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(entryAccentColor)
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)
                    .contentShape(Circle())
                    .onTapGesture {
                        toggleDone()
                    }
                    .accessibilityLabel("Afvinken")
            }

            if isMoveActive {
                AgendaMoveControls(
                    date: $moveDraftDate,
                    moveUp: moveUp,
                    moveDown: moveDown,
                    moveToDate: moveToDate,
                    moveToTodo: moveToTodo,
                    todoGroups: todoGroups,
                    finishMove: finishMove
                )
            }
        }
        .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
            if !isDeleting, oldValue == .entry(entry.id), newValue != oldValue {
                entry.refreshParsedFields()
            }
        }
    }

    @ViewBuilder private var entryContent: some View {
        TextField("", text: $entry.rawText, axis: .vertical)
            .textFieldStyle(.plain)
            .focused(focusedField, equals: .entry(entry.id))
            .onChange(of: entry.rawText) { _, _ in
                handleTextChange()
            }
        .font(.system(size: 16, weight: .regular))
        .lineLimit(1...)
        .strikethrough(entry.isDone)
        .foregroundStyle(entry.isDone ? Color.secondary : entryAccentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleTextChange() {
        if entry.rawText.contains("\n") {
            entry.rawText = entry.rawText
                .replacingOccurrences(of: "\n", with: "")
            entry.refreshParsedFields()
            focusedField.wrappedValue = nil
            return
        }

        if entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteEntry()
        }
    }

    private func deleteEntry() {
        guard !isDeleting else { return }
        isDeleting = true
        focusedField.wrappedValue = nil
        AppKeyboard.dismiss()

        let eventIdentifier = entry.calendarEventIdentifier
        let allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        let eventIsShared = eventIdentifier.map { identifier in
            allEntries.contains {
                $0.id != entry.id && $0.calendarEventIdentifier == identifier
            }
        } ?? false

        Task { @MainActor in
            await Task.yield()
            modelContext.delete(entry)
            try? modelContext.save()

            if !eventIsShared, let eventIdentifier {
                CalendarSyncService.enqueueEventDeletion(withIdentifier: eventIdentifier)
            }
        }
    }

    private func toggleDone() {
        entry.toggleDone()
    }

    private var entryAccentColor: Color {
        let categoryID = entry.accentRawValue == "birthdayReminder"
            ? RecurringTheme.birthday.rawValue
            : entry.accentRawValue

        if let data = recurringCategoriesData.data(using: .utf8),
           let categories = try? JSONDecoder().decode([AgendaRecurringCategoryAppearance].self, from: data),
           let colorRawValue = categories.first(where: { $0.id == categoryID })?.colorRawValue {
            return recurringColor(colorRawValue)
        }

        switch categoryID {
        case RecurringTheme.birthday.rawValue: return .blue
        case RecurringTheme.general.rawValue: return .yellow
        case RecurringTheme.personal.rawValue: return .green
        case "holidays": return .orange
        default: return .primary
        }
    }

    private func recurringColor(_ rawValue: String) -> Color {
        switch RecurringThemeColorOption(rawValue: rawValue) {
        case .blue: .blue
        case .yellow: .yellow
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .teal: .teal
        case .gray: .gray
        case nil: .primary
        }
    }
}

struct AgendaInputLine: View {
    let dateLabel: String
    let weekdayLetter: String
    let date: Date
    let nextOrder: Double
    let focusedField: FocusState<AgendaField?>.Binding
    let isMoveModeActive: Bool
    let isMoveTargetHighlighted: Bool
    let moveActiveEntryHere: () -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""

    @AppStorage(SettingsKeys.agendaPlaceholder)
    private var agendaPlaceholder = "x"

    var body: some View {
        HStack(alignment: .top, spacing: AgendaLayout.rowSpacing) {
            AgendaLinePrefix(
                dateLabel: dateLabel,
                weekdayLetter: weekdayLetter,
                isMoveTargetHighlighted: isMoveTargetHighlighted
            )
                .contentShape(Rectangle())
                .onTapGesture {
                    if isMoveModeActive {
                        moveActiveEntryHere()
                    } else {
                        focusedField.wrappedValue = .newEntry(date)
                    }
                }

            ZStack(alignment: .leading) {
                if text.isEmpty && !placeholderText.isEmpty {
                    Text(placeholderText)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused(focusedField, equals: .newEntry(date))
                    .submitLabel(.return)
                    .onChange(of: text) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        text = newValue.replacingOccurrences(of: "\n", with: "")
                        finishEntry()
                    }
                    .onSubmit {
                        finishEntry()
                    }
            }
            .font(.system(size: 16, weight: .regular))
            .lineLimit(1...)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
        .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
            if oldValue == .newEntry(date), newValue != oldValue {
                addEntry(continueEditing: false)
            }
        }
        .onDisappear {
            addEntry(continueEditing: false)
        }
    }

    private var placeholderText: String {
        agendaPlaceholder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addEntry(continueEditing: Bool = true) {
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

        if continueEditing {
            // Enter and the plus button continue on a fresh entry for this day.
            Task { @MainActor in
                focusedField.wrappedValue = .newEntry(date)
            }
        }
    }

    private func finishEntry() {
        addEntry(continueEditing: false)
        focusedField.wrappedValue = nil
    }
}

private struct AgendaMoveControls: View {
    @Binding var date: Date
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveToDate: () -> Void
    let moveToTodo: (String) -> Void
    let todoGroups: [TodoGroup]
    let finishMove: () -> Void

    var body: some View {
        HStack(spacing: AgendaLayout.rowSpacing) {
            Color.clear
                .frame(width: AgendaLayout.prefixWidth, height: 24)

            HStack(spacing: 8) {
                Menu {
                    ForEach(todoGroups) { group in
                        Button {
                            moveToTodo(group.id)
                        } label: {
                            Label(group.title, systemImage: group.icon)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 24)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Verplaatsopties")

                DatePicker("", selection: dateSelection, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(width: 84, alignment: .leading)
                    .scaleEffect(0.82, anchor: .leading)

                Button {
                    performStep(moveUp)
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Een positie omhoog")

                Button {
                    performStep(moveDown)
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Een positie omlaag")

                Spacer(minLength: 2)

                Button(action: finishMove) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.green)
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Klaar met verplaatsen")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var dateSelection: Binding<Date> {
        Binding(
            get: { date },
            set: { newDate in
                date = newDate
                moveToDate()
            }
        )
    }

    private func performStep(_ action: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            action()
        }
    }
}

private struct AgendaLinePrefix: View {
    let dateLabel: String
    let weekdayLetter: String
    var isMoveActive = false
    var isMoveTargetHighlighted = false

    var body: some View {
        HStack(spacing: AgendaLayout.dateWeekdaySpacing) {
            Text(dateLabel.isEmpty ? "     " : dateLabel)
                .foregroundStyle(dateLabel.isEmpty ? Color.clear : Color.secondary)
                .monospacedDigit()
                .frame(width: AgendaLayout.dateWidth, alignment: .leading)

            Text(weekdayLetter)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: AgendaLayout.weekdayWidth, height: 22, alignment: .center)
                .background {
                    if isMoveActive {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.green.opacity(0.18))
                    } else if isMoveTargetHighlighted {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.yellow.opacity(0.28))
                    }
                }
        }
        .font(.system(size: 15, weight: .medium))
        .frame(width: AgendaLayout.prefixWidth, alignment: .leading)
    }
}
