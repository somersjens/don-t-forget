#if os(macOS)
import SwiftData
import SwiftUI

private struct MacTodoDestination: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String

    static func decode(_ data: String) -> [Self] {
        if let value = data.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Self].self, from: value),
           !decoded.isEmpty {
            return decoded
        }
        return [
            Self(id: TodoBucket.shortTerm.rawValue, title: "Binnenkort", icon: "bolt.fill"),
            Self(id: TodoBucket.longTerm.rawValue, title: "Later", icon: "mountain.2.fill"),
            Self(id: "shopping", title: "Boodschappen", icon: "cart.fill")
        ]
    }
}

struct MacCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<RecurringItem> { !$0.isRemoved }) private var recurringItems: [RecurringItem]
    let entries: [DayEntry]
    let searchText: String
    let currentMatchID: UUID?
    @Binding var selection: UUID?

    @State private var visibleWeekCount = 14
    @State private var newEntryDate: Date?
    @State private var newEntryText = ""
    @State private var movingEntry: DayEntry?
    @State private var moveDate = AppCalendar.startOfDay(.now)
    @State private var moveDateText = ""
    @State private var isMoveCalendarPresented = false
    @State private var recurringMoveOffer: MacRecurringMoveOffer?
    @State private var lastAction: MacAgendaUndoAction?
    @State private var feedbackMessage: String?
    @State private var dismissFeedbackTask: Task<Void, Never>?
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""

    private enum MacAgendaUndoAction {
        case created(DayEntry)
        case completed(DayEntry)
        case moved(DayEntry, previousDate: Date)
    }

    private struct MacRecurringMoveOffer: Identifiable {
        let id = UUID()
        let itemID: UUID
        let originalDate: Date
        let targetDate: Date
    }

    private var todoGroups: [MacTodoDestination] { MacTodoDestination.decode(todoGroupsData) }

    private var entriesByDay: [Date: [DayEntry]] {
        Dictionary(grouping: entries) { AppCalendar.startOfDay($0.date) }
    }

    private var weeks: [WeekSection] {
        AppCalendar.weekSections(startingFrom: AppCalendar.startOfDay(.now), numberOfWeeks: visibleWeekCount)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { weekIndex, week in
                    MacWeekCard(
                        week: week,
                        showsFirstAddPrompt: weekIndex == 0,
                        entriesByDay: entriesByDay,
                        searchText: searchText,
                        currentMatchID: currentMatchID,
                        selection: $selection,
                        newEntryDate: $newEntryDate,
                        newEntryText: $newEntryText,
                        complete: toggleCompleted,
                        remove: remove,
                        startMove: startMoving,
                        moveToTodo: moveToTodo,
                        todoGroups: todoGroups,
                        created: { setLastAction(.created($0)) }
                    )
                    .id(week.id)
                }

                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 16)
                    .onAppear { visibleWeekCount += 8 }
                    }
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            .padding(18)
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
                if let target = entries.first(where: { $0.id == id }) {
                    ensureDateIsLoaded(target.date)
                    await Task.yield()
                    if let week = weeks.first(where: { week in
                        week.days.contains { AppCalendar.isSameDay($0.date, target.date) }
                    }) {
                        proxy.scrollTo(week.id, anchor: .center)
                    }
                }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
                try? await Task.sleep(for: .milliseconds(260))
                proxy.scrollTo(id, anchor: .center)
            }
        }
        }
        .background(Color.appCanvasBackground)
        .safeAreaInset(edge: .bottom, spacing: 8) {
            if let feedbackMessage {
                UndoFeedbackBar(
                    iconSystemName: "checkmark.circle.fill",
                    iconColor: .brandHardBlue,
                    message: feedbackMessage,
                    undoTitle: "Terughalen",
                    action: undoLastAction,
                    preferredMessageLineLimit: 2
                )
                .frame(maxWidth: 560)
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $movingEntry) { entry in moveSheet(entry) }
        .confirmationDialog(
            "Toekomstige items ook verplaatsen?",
            isPresented: Binding(
                get: { recurringMoveOffer != nil },
                set: { if !$0 { recurringMoveOffer = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ook toekomstige items verplaatsen") { applyRecurringMoveOffer() }
            Button("Alleen dit item") { recurringMoveOffer = nil }
            Button("Annuleer", role: .cancel) { undoLastAction(); recurringMoveOffer = nil }
        } message: {
            Text("Wil je dezelfde datumverschuiving toepassen op alle volgende voorkomens van dit terugkerende item?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUndoAgendaAction)) { _ in
            undoLastAction()
        }
        .onDisappear { dismissFeedbackTask?.cancel() }
    }

    private func toggleCompleted(_ entry: DayEntry) {
        guard !entry.isDone else { return }
        entry.isDone = true
        entry.completedAt = .now
        PersistenceSafety.save(modelContext)
        setLastAction(.completed(entry))
        feedbackMessage = "‘\(entry.rawText)’\nverplaatst naar Afgerond"
        scheduleFeedbackDismissal()
    }

    private func remove(_ entry: DayEntry) {
        entry.isRemoved = true
        entry.completedAt = .now
        if selection == entry.id { selection = nil }
        PersistenceSafety.save(modelContext)
    }

    private func startMoving(_ entry: DayEntry) {
        moveDate = entry.date
        moveDateText = Self.moveDateFormatter.string(from: entry.date)
        movingEntry = entry
    }

    private func moveToTodo(_ entry: DayEntry, group: MacTodoDestination) {
        let text = entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let todo = TodoItem(text: text, bucket: .today)
        todo.bucketRawValue = group.id
        modelContext.insert(todo)
        modelContext.delete(entry)
        if selection == entry.id { selection = nil }
        PersistenceSafety.save(modelContext)
    }

    private func undoLastAction() {
        guard let lastAction else { return }
        dismissFeedbackTask?.cancel()
        switch lastAction {
        case .created(let entry):
            if selection == entry.id { selection = nil }
            modelContext.delete(entry)
        case .completed(let entry):
            entry.isDone = false
            entry.completedAt = nil
        case .moved(let entry, let previousDate):
            entry.date = previousDate
        }
        PersistenceSafety.save(modelContext)
        self.lastAction = nil
        NotificationCenter.default.post(name: .macAgendaUndoAvailability, object: false)
        withAnimation(.easeOut(duration: 0.2)) { feedbackMessage = nil }
    }

    private func setLastAction(_ action: MacAgendaUndoAction) {
        lastAction = action
        NotificationCenter.default.post(name: .macAgendaUndoAvailability, object: true)
    }

    private func scheduleFeedbackDismissal() {
        dismissFeedbackTask?.cancel()
        dismissFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { feedbackMessage = nil }
        }
    }

    private func ensureDateIsLoaded(_ date: Date) {
        let calendar = AppCalendar.calendar
        let start = AppCalendar.startOfDay(.now)
        let target = AppCalendar.startOfDay(date)
        guard let dayDistance = calendar.dateComponents([.day], from: start, to: target).day,
              dayDistance >= 0 else { return }
        visibleWeekCount = max(visibleWeekCount, dayDistance / 7 + 2)
    }

    private func moveSheet(_ entry: DayEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Verplaats agenda-item", systemImage: "calendar.badge.clock").font(.title2.bold())
            Text(entry.rawText.isEmpty ? "Agenda-item" : entry.rawText).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Nieuwe datum", text: $moveDateText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitTypedMove(entry) }

                Button("Open kalender", systemImage: "calendar") {
                    isMoveCalendarPresented.toggle()
                }
                .labelStyle(.iconOnly)
                .popover(isPresented: $isMoveCalendarPresented, arrowEdge: .bottom) {
                    DatePicker("Nieuwe datum", selection: $moveDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .onChange(of: moveDate) { _, date in
                            moveDateText = Self.moveDateFormatter.string(from: date)
                        }
                }
            }
            HStack {
                Spacer()
                Button("Annuleer", role: .cancel) { movingEntry = nil }
                Button("Verplaats") {
                    performMove(entry)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func performMove(_ entry: DayEntry) {
        let previousDate = AppCalendar.startOfDay(entry.date)
        let destination = AppCalendar.startOfDay(moveDate)
        guard previousDate != destination else {
            movingEntry = nil
            return
        }
        entry.date = destination
        if entry.recurringItemIdentifier != nil {
            entry.recurringDateOverride = destination
        }
        PersistenceSafety.save(modelContext)
        setLastAction(.moved(entry, previousDate: previousDate))
        feedbackMessage = "‘\(entry.rawText)’\nverplaatst naar \(destination.formatted(date: .abbreviated, time: .omitted))"
        scheduleFeedbackDismissal()
        movingEntry = nil
        if let itemID = entry.recurringItemIdentifier,
           recurringItems.contains(where: { $0.id == itemID }) {
            recurringMoveOffer = MacRecurringMoveOffer(
                itemID: itemID,
                originalDate: previousDate,
                targetDate: destination
            )
        }
    }

    private func applyRecurringMoveOffer() {
        guard let offer = recurringMoveOffer,
              let item = recurringItems.first(where: { $0.id == offer.itemID }) else {
            recurringMoveOffer = nil
            return
        }
        let offset = AppCalendar.calendar.dateComponents(
            [.day],
            from: offer.originalDate,
            to: offer.targetDate
        ).day ?? 0
        guard offset != 0 else { recurringMoveOffer = nil; return }
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: offer.originalDate,
            dayOffset: offset,
            to: item
        )
        let through = AppCalendar.calendar.date(byAdding: .month, value: 3, to: .now) ?? offer.targetDate
        RecurringScheduler.syncAll(items: recurringItems, in: modelContext, through: through)
        PersistenceSafety.save(modelContext)
        recurringMoveOffer = nil
    }

    private func commitTypedMove(_ entry: DayEntry) {
        guard let date = Self.moveDateFormatter.date(from: moveDateText) else { return }
        moveDate = AppCalendar.startOfDay(date)
        performMove(entry)
    }

    private static let moveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppCalendar.locale
        formatter.calendar = AppCalendar.calendar
        formatter.timeZone = AppCalendar.calendar.timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct MacWeekCard: View {
    let week: WeekSection
    let showsFirstAddPrompt: Bool
    let entriesByDay: [Date: [DayEntry]]
    let searchText: String
    let currentMatchID: UUID?
    @Binding var selection: UUID?
    @Binding var newEntryDate: Date?
    @Binding var newEntryText: String
    let complete: (DayEntry) -> Void
    let remove: (DayEntry) -> Void
    let startMove: (DayEntry) -> Void
    let moveToTodo: (DayEntry, MacTodoDestination) -> Void
    let todoGroups: [MacTodoDestination]
    let created: (DayEntry) -> Void

    private var visibleDays: [DayInfo] {
        let today = AppCalendar.startOfDay(.now)
        return week.days.filter { day in
            day.date >= today || !(entriesByDay[day.date] ?? []).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: "week #\(week.weekNumber) · start \(week.startDateLabel) · \(String(AppCalendar.calendar.component(.year, from: week.startDate)))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    DefaultColorCombination.isEnabled
                        ? Color.brandHardBlue.opacity(0.70)
                        : Color.secondary
                )
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(spacing: 0) {
                ForEach(Array(visibleDays.enumerated()), id: \.element.id) { dayIndex, day in
                    MacCalendarDay(
                        day: day,
                        showsAddPrompt: showsFirstAddPrompt && dayIndex == 0,
                        entries: (entriesByDay[day.date] ?? []).sorted(by: calendarEntryOrder),
                        searchText: searchText,
                        currentMatchID: currentMatchID,
                        selection: $selection,
                        newEntryDate: $newEntryDate,
                        newEntryText: $newEntryText,
                        complete: complete,
                        remove: remove,
                        startMove: startMove,
                        moveToTodo: moveToTodo,
                        todoGroups: todoGroups,
                        created: created
                    )
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(
                    DefaultColorCombination.isEnabled
                        ? Color.appCardOutline
                        : Color.primary.opacity(0.08)
                )
            }
            .shadow(color: .black.opacity(0.06), radius: 9, y: 3)
        }
    }

    private func calendarEntryOrder(_ lhs: DayEntry, _ rhs: DayEntry) -> Bool {
        switch (lhs.startMinutes, rhs.startMinutes) {
        case let (a?, b?) where a != b: return a < b
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.manualOrder < rhs.manualOrder
        }
    }
}

private struct MacCalendarDay: View {
    @Environment(\.modelContext) private var modelContext
    let day: DayInfo
    let showsAddPrompt: Bool
    let entries: [DayEntry]
    let searchText: String
    let currentMatchID: UUID?
    @Binding var selection: UUID?
    @Binding var newEntryDate: Date?
    @Binding var newEntryText: String
    let complete: (DayEntry) -> Void
    let remove: (DayEntry) -> Void
    let startMove: (DayEntry) -> Void
    let moveToTodo: (DayEntry, MacTodoDestination) -> Void
    let todoGroups: [MacTodoDestination]
    let created: (DayEntry) -> Void
    @FocusState private var newEntryFocused: Bool
    @AppStorage(SettingsKeys.hasUsedMacAgendaInput) private var hasUsedAgendaInput = false
    @AppStorage(SettingsKeys.weekdayLabelLength) private var weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue

    private var isToday: Bool { AppCalendar.isSameDay(day.date, .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                MacCalendarEntryRow(
                    entry: entry,
                    searchText: searchText,
                    currentMatchID: currentMatchID,
                    dateLabel: index == 0 ? day.dateLabel : "",
                    weekdayLetter: day.weekdayLetter,
                    isToday: isToday,
                    isSelected: selection == entry.id,
                    select: { selection = entry.id },
                    complete: { complete(entry) },
                    remove: { remove(entry) },
                    startMove: { startMove(entry) },
                    moveToTodo: { group in moveToTodo(entry, group) },
                    todoGroups: todoGroups
                )
            }

            inputRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            dayPrefix(dateLabel: entries.isEmpty ? day.dateLabel : "", weekday: day.weekdayLetter)
            Rectangle()
                .fill(Color.primary.opacity(0.23))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            if newEntryDate == day.date {
                TextField("Nieuw agenda-item", text: $newEntryText)
                    .textFieldStyle(.plain)
                    .focused($newEntryFocused)
                    .onSubmit { addEntry(continueEditing: false) }
                    .onChange(of: newEntryFocused) { wasFocused, focused in
                        guard wasFocused, !focused, newEntryDate == day.date else { return }
                        addEntry(continueEditing: false)
                    }
                    .onKeyPress(.tab) {
                        addEntry(continueEditing: true)
                        return .handled
                    }
                    .onExitCommand { cancelEntry() }

                Button("Voeg toe en ga door", systemImage: "plus.circle.fill") {
                    addEntry(continueEditing: true)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 17))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
                .foregroundStyle(Color.brandHardBlue)
                .help("Voeg toe en maak nog een item")
            } else {
                Button {
                    commitPendingEntryBeforeSwitchingDays()
                    hasUsedAgendaInput = true
                    newEntryText = ""
                    newEntryDate = day.date
                    Task { @MainActor in newEntryFocused = true }
                } label: {
                    Group {
                        if showsAddPrompt && !hasUsedAgendaInput {
                            Label("Voeg item toe", systemImage: "plus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 22)
    }

    private func dayPrefix(dateLabel: String, weekday: String) -> some View {
        HStack(spacing: 5) {
            Text(dateLabel)
                .foregroundStyle(isToday && !dateLabel.isEmpty ? Color.brandHardBlue : Color.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(weekday)
                .foregroundStyle(.secondary)
                .frame(
                    width: macWeekdayWidth,
                    alignment: AppCalendar.weekdayLabelLength == 1 ? .center : .leading
                )
        }
        .font(.system(size: 13, weight: .medium))
        .offset(x: -4)
    }

    private var macWeekdayWidth: CGFloat {
        CGFloat(14 + max(0, AppCalendar.weekdayLabelLength - 1) * 8)
    }

    private func addEntry(continueEditing: Bool) {
        hasUsedAgendaInput = true
        let text = newEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if !continueEditing { cancelEntry() }
            return
        }
        let order = (entries.map(\.manualOrder).max() ?? -1) + 1
        let entry = DayEntry(date: day.date, rawText: text, manualOrder: order)
        modelContext.insert(entry)
        PersistenceSafety.save(modelContext)
        created(entry)
        newEntryText = ""
        if continueEditing {
            newEntryDate = day.date
            Task { @MainActor in newEntryFocused = true }
        } else {
            newEntryDate = nil
            newEntryFocused = false
        }
    }

    private func commitPendingEntryBeforeSwitchingDays() {
        guard let pendingDate = newEntryDate,
              pendingDate != day.date else { return }
        let text = newEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let entry = DayEntry(date: pendingDate, rawText: text, manualOrder: 0)
        modelContext.insert(entry)
        PersistenceSafety.save(modelContext)
        created(entry)
        newEntryText = ""
    }

    private func cancelEntry() {
        newEntryDate = nil
        newEntryText = ""
        newEntryFocused = false
    }
}

private struct MacCalendarEntryRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: DayEntry
    let searchText: String
    let currentMatchID: UUID?
    let dateLabel: String
    let weekdayLetter: String
    let isToday: Bool
    let isSelected: Bool
    let select: () -> Void
    let complete: () -> Void
    let remove: () -> Void
    let startMove: () -> Void
    let moveToTodo: (MacTodoDestination) -> Void
    let todoGroups: [MacTodoDestination]
    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.weekdayLabelLength) private var weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue
    @FocusState private var isTextFocused: Bool
    @State private var draftText = ""

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(dateLabel)
                    .foregroundStyle(isToday && !dateLabel.isEmpty ? Color.brandHardBlue : Color.secondary)
                    .frame(width: 48, alignment: .trailing)
                Button(action: startMove) {
                    Text(weekdayLetter).frame(
                        width: macWeekdayWidth,
                        height: 24,
                        alignment: AppCalendar.weekdayLabelLength == 1 ? .center : .leading
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .help("Verplaats item")
            }
            .font(.system(size: 13, weight: .medium))
            .offset(x: -4)

            Rectangle()
                .fill(Color.primary.opacity(0.23))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            TextField("Agenda-item", text: $draftText)
                .textFieldStyle(.plain)
                .focused($isTextFocused)
                .foregroundStyle(entryAccentColor)
                .onSubmit { isTextFocused = false }
                .onChange(of: isTextFocused) { wasFocused, focused in
                    if !wasFocused, focused {
                        draftText = entry.rawText
                    }
                    guard wasFocused, !focused else { return }
                    finishEditing()
                }
                .frame(maxWidth: .infinity)

            Menu {
                Button("Verplaats naar andere datum", systemImage: "calendar.badge.clock", action: startMove)
                ForEach(todoGroups) { group in
                    Button("Verplaats naar \(group.title)", systemImage: group.icon) {
                        moveToTodo(group)
                    }
                }
                Divider()
                Button("Verwijder", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entryAccentColor)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(entryAccentColor)
            .fixedSize()

            Button(action: complete) {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(entry.isDone ? .green : entryAccentColor)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 22)
        .id(entry.id)
        .modifier(SearchMatchHighlight(
            isMatch: !searchText.isEmpty && entry.rawText.localizedCaseInsensitiveContains(searchText),
            isCurrent: currentMatchID == entry.id
        ))
        .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button("Verplaats naar andere datum", systemImage: "calendar.badge.clock", action: startMove)
            ForEach(todoGroups) { group in
                Button("Verplaats naar \(group.title)", systemImage: group.icon) { moveToTodo(group) }
            }
            Divider()
            Button("Verwijder", systemImage: "trash", role: .destructive, action: remove)
        }
        .onAppear {
            draftText = entry.rawText
        }
        .onChange(of: entry.rawText) { _, value in
            guard !isTextFocused else { return }
            draftText = value
        }
    }

    private var macWeekdayWidth: CGFloat {
        CGFloat(14 + max(0, AppCalendar.weekdayLabelLength - 1) * 8)
    }

    private func finishEditing() {
        let cleanText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            modelContext.delete(entry)
            PersistenceSafety.save(modelContext)
            return
        }
        draftText = cleanText
        entry.rawText = cleanText
        entry.refreshParsedFields()
        PersistenceSafety.save(modelContext)
    }

    private var entryAccentColor: Color {
        let categoryID = entry.accentRawValue == "birthdayReminder"
            ? RecurringTheme.birthday.rawValue
            : entry.accentRawValue
        struct Appearance: Decodable { let id: String; let colorRawValue: String }
        if let data = recurringCategoriesData.data(using: .utf8),
           let categories = try? JSONDecoder().decode([Appearance].self, from: data),
           let raw = categories.first(where: { $0.id == categoryID })?.colorRawValue {
            return RecurringThemeColorOption(rawValue: raw)?.color ?? .primary
        }
        switch categoryID {
        case RecurringTheme.birthday.rawValue: return .blue
        case RecurringTheme.general.rawValue: return .yellow
        case RecurringTheme.personal.rawValue: return .green
        case "holidays": return .orange
        case "none": return .primary
        default: return .primary
        }
    }
}
#endif
