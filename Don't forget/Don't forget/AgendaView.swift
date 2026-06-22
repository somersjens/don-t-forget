import SwiftUI
import SwiftData

struct AgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    @Query(sort: \DayEntry.date, order: .forward)
    private var entries: [DayEntry]

    @FocusState private var focusedField: AgendaField?
    @State private var isScrolled = false
    @State private var calendarSyncTask: Task<Void, Never>?

    @AppStorage(SettingsKeys.weekStart) private var weekStartSetting = WeekStartOption.monday.rawValue
    @AppStorage(SettingsKeys.weekNumberRule) private var weekNumberSetting = WeekNumberRule.iso8601.rawValue
    @AppStorage(SettingsKeys.language) private var languageSetting = AppLanguage.system.rawValue
    @AppStorage(SettingsKeys.calendarSyncEnabled) private var calendarSyncEnabled = false

    private var calendarSyncSignature: String {
        entries
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    String($0.date.timeIntervalSinceReferenceDate),
                    $0.rawText,
                    String($0.startMinutes ?? -1),
                    String($0.endMinutes ?? -1)
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private var weeks: [WeekSection] {
        let today = AppCalendar.startOfDay(.now)
        let oldestOpenDate = entries
            .filter { !$0.isDone && $0.date < today }
            .map(\.date)
            .min()
        let startDate = oldestOpenDate ?? today
        let endDate = AppCalendar.calendar.date(byAdding: .year, value: 2, to: today) ?? today
        let startOfFirstWeek = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        let startOfLastWeek = AppCalendar.calendar.dateInterval(of: .weekOfYear, for: endDate)?.start ?? endDate
        let weekCount = (AppCalendar.calendar.dateComponents(
            [.weekOfYear],
            from: startOfFirstWeek,
            to: startOfLastWeek
        ).weekOfYear ?? 104) + 1

        return AppCalendar.weekSections(
            startingFrom: startDate,
            numberOfWeeks: weekCount
        )
        .filter { week in
            week.days.contains(where: isVisible)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
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
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 12
            } action: { _, newValue in
                isScrolled = newValue
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
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(focusedField == nil)
                        .accessibilityLabel("Toetsenbord sluiten")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .onAppear {
                modelContext.undoManager = undoManager
            }
            .task {
                scheduleCalendarSync()
            }
            .onChange(of: calendarSyncSignature) { _, _ in
                scheduleCalendarSync()
            }
            .onChange(of: calendarSyncEnabled) { _, enabled in
                if enabled {
                    scheduleCalendarSync()
                } else {
                    calendarSyncTask?.cancel()
                }
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue == nil {
                    scheduleCalendarSync()
                }
            }
        }
    }

    private func isVisible(_ day: DayInfo) -> Bool {
        let today = AppCalendar.startOfDay(.now)

        if day.date >= today {
            return true
        }

        return entries.contains {
            AppCalendar.isSameDay($0.date, day.date) && !$0.isDone
        }
    }

    private func scheduleCalendarSync() {
        calendarSyncTask?.cancel()
        guard calendarSyncEnabled, focusedField == nil else { return }

        calendarSyncTask = Task(priority: .background) { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, focusedField == nil else { return }
            try? modelContext.save()
            try? CalendarSyncService.syncAll(in: modelContext)
            // Persist the EventKit identifiers assigned during this sync. Without
            // this second save, a fast app close can create duplicate events later.
            try? modelContext.save()
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

    private var visibleDays: [DayInfo] {
        let today = AppCalendar.startOfDay(.now)

        return week.days.filter { day in
            if day.date >= today {
                return true
            }

            return entries.contains {
                AppCalendar.isSameDay($0.date, day.date) && !$0.isDone
            }
        }
    }

    private var startDateLabel: String {
        let formatter = DateFormatter()
        let language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.language) ?? ""
        ) ?? .system
        formatter.locale = language.locale
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: week.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("week #\(week.weekNumber) - start \(startDateLabel)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(visibleDays) { day in
                    DayBlock(
                        day: day,
                        entries: entriesForDay(day.date),
                        focusedField: focusedField
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 17)
                    .fill(Color(.secondarySystemBackground))
            }
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

    @AppStorage(SettingsKeys.calendarSyncEnabled)
    private var calendarSyncEnabled = false

    @State private var isDeleting = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            AgendaLinePrefix(dateLabel: dateLabel, weekdayLetter: weekdayLetter)

            TextField("", text: $entry.rawText, axis: .vertical)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .strikethrough(entry.isDone)
                .foregroundStyle(entry.isDone ? Color.secondary : entryAccentColor)
                .focused(focusedField, equals: .entry(entry.id))
                .onChange(of: entry.rawText) { _, _ in
                    if entry.rawText.contains("\n") {
                        entry.rawText = entry.rawText
                            .replacingOccurrences(of: "\n", with: "")
                        entry.refreshParsedFields()
                        focusedField.wrappedValue = nil
                        return
                    }

                    if entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

                            if calendarSyncEnabled,
                               !eventIsShared,
                               let eventIdentifier {
                                Task(priority: .background) { @MainActor in
                                    try? await Task.sleep(for: .seconds(2))
                                    guard !Task.isCancelled else { return }
                                    try? CalendarSyncService.deleteEvent(
                                        withIdentifier: eventIdentifier
                                    )
                                }
                            }
                        }
                        return
                    }
                }
                .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
                    if !isDeleting, oldValue == .entry(entry.id), newValue != oldValue {
                        entry.refreshParsedFields()
                    }
                }

            if entry.isUncertain {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            Button {
                entry.toggleDone()
            } label: {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(entryAccentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var entryAccentColor: Color {
        switch entry.accentRawValue {
        case RecurringTheme.birthday.rawValue:
            return .blue
        case "birthdayReminder":
            return .cyan.opacity(0.72)
        case RecurringTheme.general.rawValue:
            return Color(red: 0.72, green: 0.53, blue: 0.02)
        case RecurringTheme.personal.rawValue:
            return .green
        default:
            return .primary
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

    @AppStorage(SettingsKeys.agendaPlaceholder)
    private var agendaPlaceholder = "x"

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            AgendaLinePrefix(dateLabel: dateLabel, weekdayLetter: weekdayLetter)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(agendaPlaceholder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.plain)
                    .lineLimit(1...)
                    .foregroundStyle(.primary)
                    .focused(focusedField, equals: .newEntry(date))
                    .submitLabel(.return)
                    .onChange(of: text) { _, newValue in
                        guard newValue.contains("\n") else {
                            return
                        }

                        text = newValue.replacingOccurrences(of: "\n", with: "")
                        finishEntry()
                    }
                    .onSubmit {
                        finishEntry()
                    }
            }

            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
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

private struct AgendaLinePrefix: View {
    let dateLabel: String
    let weekdayLetter: String

    var body: some View {
        HStack(spacing: 5) {
            Text(dateLabel.isEmpty ? "     " : dateLabel)
                .foregroundStyle(dateLabel.isEmpty ? .clear : .primary)

            Text(weekdayLetter)
                .foregroundStyle(.primary)

            Text("|")
                .foregroundStyle(.primary)
        }
        .font(.system(size: 13, design: .monospaced))
    }
}
