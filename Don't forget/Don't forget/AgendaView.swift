import SwiftUI
import SwiftData

private extension View {
    @ViewBuilder
    func agendaScrollCompatibility(
        isScrolled: Binding<Bool>,
        scrollIdleChanged: @escaping (Bool) -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
                .onScrollPhaseChange { _, newPhase in
                    scrollIdleChanged(newPhase == .idle)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 12
                } action: { _, newValue in
                    isScrolled.wrappedValue = newValue
                }
        } else if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, newPhase in
                scrollIdleChanged(newPhase == .idle)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 12
            } action: { _, newValue in
                isScrolled.wrappedValue = newValue
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleAgendaGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func agendaVisibilityCompatibility(
        changed: @escaping (Bool) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onScrollVisibilityChange(threshold: 0.01, changed)
        } else {
            onAppear { changed(true) }
                .onDisappear { changed(false) }
        }
    }
}

private struct AgendaRecurringCategoryAppearance: Decodable {
    let id: String
    let colorRawValue: String
}

private struct RecurringMoveBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

private struct AgendaTodoMoveUndo {
    let todoID: UUID
    let entryID: UUID
    let destinationTitle: String
    let date: Date
    let rawText: String
    let sourceRawValue: String
    let manualOrder: Double
    let showOnWidget: Bool
    let createdAt: Date
    let calendarEventIdentifier: String?
    let recurringItemIdentifier: UUID?
    let recurringOccurrenceKey: String?
    let recurringDateOverride: Date?
    let accentRawValue: String
}

private struct AgendaRecurringMoveOffer {
    enum Phase {
        case prompt
        case processing
        case success
        case failure
    }

    let itemID: UUID
    let effectiveFrom: Date
    let seriesDate: Date
    let targetDate: Date
    var phase: Phase = .prompt
    var shiftWasSaved = false
}

@Observable
@MainActor
private final class AgendaRecurringMoveController {
    var offer: AgendaRecurringMoveOffer?
}

private struct AgendaRecurringMoveBar: View {
    @Bindable var controller: AgendaRecurringMoveController
    let locale: Locale
    let apply: () -> Void

    var body: some View {
        Group {
            if let offer = controller.offer {
                Button(action: apply) {
                    HStack(spacing: 12) {
                        leadingIcon(for: offer.phase)
                            .frame(width: 18, height: 18)
                        Text(message(for: offer.phase))
                            .font(.system(size: 14, weight: offer.phase == .prompt ? .semibold : .medium))
                            .multilineTextAlignment(.leading)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        // Prompt text, spinner and checkmark occupy exactly the
                        // same slot. The material card therefore cannot resize
                        // or appear to be replaced when only its state changes.
                        trailingAction(for: offer.phase)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .modifier(RecurringMoveBarStyle())
                }
                .buttonStyle(.plain)
                // `.disabled` dims a Button, including its material background.
                // Keep this one card visually constant and only stop hit testing
                // while its content changes to progress or success.
                .allowsHitTesting(offer.phase == .prompt || offer.phase == .failure)
                .accessibilityLabel(message(for: offer.phase))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func leadingIcon(for phase: AgendaRecurringMoveOffer.Phase) -> some View {
        switch phase {
        case .prompt, .processing:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(Color.brandHardBlue)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandHardBlue)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func trailingAction(for phase: AgendaRecurringMoveOffer.Phase) -> some View {
        switch phase {
        case .prompt:
            Text(locale.localized("Ja graag"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brandHardBlue)
                .fixedSize(horizontal: true, vertical: false)
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.regular)
                .tint(Color.brandHardBlue)
                .scaleEffect(1.08)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.brandHardBlue)
        case .failure:
            Text(locale.localized("recurring.retry"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brandHardBlue)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func message(for phase: AgendaRecurringMoveOffer.Phase) -> String {
        switch phase {
        case .prompt:
            locale.localized("Volgende herhalingen meeverschuiven?")
        case .processing:
            locale.localized("recurring.rescheduling")
        case .success:
            locale.localized("Volgende herhalingen zijn meeverschoven")
        case .failure:
            locale.localized("recurring.reschedulingFailed")
        }
    }
}

private struct AgendaDateMoveUndo {
    let entry: DayEntry
    let originalDate: Date
    let targetDate: Date
}

private enum AgendaEntryOrdering {
    nonisolated static func areInIncreasingOrder(_ first: DayEntry, _ second: DayEntry) -> Bool {
        switch (first.startMinutes, second.startMinutes) {
        case let (a?, b?):
            if a != b {
                return a < b
            }
            return compareManualOrderThenIdentity(first, second)

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        case (nil, nil):
            return compareManualOrderThenIdentity(first, second)
        }
    }

    nonisolated private static func compareManualOrderThenIdentity(_ first: DayEntry, _ second: DayEntry) -> Bool {
        if first.manualOrder != second.manualOrder {
            return first.manualOrder < second.manualOrder
        }

        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }

        return first.id.uuidString < second.id.uuidString
    }
}

/// Day visibility changes rapidly during a fling. Keeping this outside
/// observable SwiftUI state prevents every entering/leaving day from
/// invalidating and rebuilding the complete agenda hierarchy.
@MainActor
private final class AgendaVisibilityCache {
    var dates: Set<Date> = []
    var entryIDs: Set<UUID> = []
    var isScrollIdle = true
    var pendingFutureLoadLimit: Int?
    var futureLoadTask: Task<Void, Never>?
}

@Observable
@MainActor
private final class AgendaScrollPresentation {
    var isScrolled = false
}

struct AgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.locale) private var locale

    @Query(
        filter: #Predicate<DayEntry> { entry in
            !entry.isDone && !entry.isRemoved
        },
        sort: \DayEntry.date,
        order: .forward
    )
    private var entries: [DayEntry]

    @Query(filter: #Predicate<RecurringItem> { !$0.isRemoved })
    private var recurringItems: [RecurringItem]

    @FocusState private var focusedField: AgendaField?
    @State private var scrollPresentation = AgendaScrollPresentation()
    @State private var activeMoveEntryID: UUID?
    @State private var moveDraftDate = AppCalendar.startOfDay(.now)
    @State private var scrollTargetDate: Date?
    @State private var scrollTask: Task<Void, Never>?
    @State private var visibilityCache = AgendaVisibilityCache()
    @State private var loadedFutureWeeks = 26
    @State private var isLoadingMoreFuture = false
    @State private var recentlyRemovedEntry: DayEntry?
    @State private var recentlyRemovedEntryTitle = ""
    @State private var recentlyRemovedEventIdentifier: String?
    @State private var dismissRemovalUndoTask: Task<Void, Never>?
    @State private var recentlyCompletedEntry: DayEntry?
    @State private var recentlyMovedToTodo: AgendaTodoMoveUndo?
    @State private var recentlyMovedToDate: AgendaDateMoveUndo?
    @State private var dismissDateMoveUndoTask: Task<Void, Never>?
    @State private var recurringMoveController = AgendaRecurringMoveController()
    @State private var recurringSeriesPresentationRevision = 0
    @State private var agendaDataRefreshState = AgendaDataRefreshState.shared
    @State private var dismissRecurringMoveOfferTask: Task<Void, Never>?
    @State private var deferredRecurringMoveTask: Task<Void, Never>?
    @State private var deferredMoveSaveTask: Task<Void, Never>?
    @State private var isHelpExpanded = false
    @State private var hasPerformedAgendaTutorialMove = false
    @State private var weatherStore = AppleWeatherForecastStore()
    @State private var recurringSyncState = RecurringSyncState.shared
    @State private var isSearchPresented = false
    @State private var isKeyboardVisible = false
    @State private var searchText = ""
    @State private var currentSearchMatch = 0
    @State private var searchScrollRequest = 0
    @State private var searchScrollTask: Task<Void, Never>?
    @State private var lastSearchScrollTargetID: UUID?
    @FocusState private var isSearchFocused: Bool

    @AppStorage(SettingsKeys.hasPresentedAgendaHelp)
    private var hasPresentedAgendaHelp = false

    @AppStorage(SettingsKeys.hasOpenedAgendaHelp)
    private var hasOpenedAgendaHelp = false

    @AppStorage(SettingsKeys.agendaTutorialStep)
    private var agendaTutorialStep = 0

    @AppStorage(SettingsKeys.hasCompletedAgendaTutorial)
    private var hasCompletedAgendaTutorial = false

    @AppStorage(SettingsKeys.hasSeededAgendaExamples)
    private var hasSeededAgendaExamples = false

    @AppStorage(SettingsKeys.agendaSportsExampleID)
    private var agendaSportsExampleID = ""

    @AppStorage(SettingsKeys.agendaDinnerExampleID)
    private var agendaDinnerExampleID = ""

    @AppStorage(SettingsKeys.weekStart) private var weekStartSetting = WeekStartOption.monday.rawValue
    @AppStorage(SettingsKeys.weekdayLabelLength) private var weekdayLabelLengthSetting = WeekdayLabelLengthOption.one.rawValue
    @AppStorage(SettingsKeys.weekNumberRule) private var weekNumberSetting = WeekNumberRule.iso8601.rawValue
    @AppStorage(SettingsKeys.language) private var languageSetting = AppLanguage.system.rawValue
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""
    @AppStorage(SettingsKeys.weatherInAgendaEnabled) private var weatherInAgendaEnabled = false
    @AppStorage(SettingsKeys.weatherLatitude) private var weatherLatitude = 0.0
    @AppStorage(SettingsKeys.weatherLongitude) private var weatherLongitude = 0.0
    @AppStorage(SettingsKeys.weatherReloadToken) private var weatherReloadToken = 0
    @AppStorage(SettingsKeys.recurringHorizon)
    private var recurringHorizon = RecurringHorizonOption.threeMonths.rawValue
    @AppStorage(SettingsKeys.recurringExtendedThrough)
    private var recurringExtendedThrough = 0.0

    private var todoGroups: [TodoGroup] {
        TodoGroupStore.decode(todoGroupsData)
    }

    private var openPastDates: Set<Date> {
        let today = AppCalendar.startOfDay(.now)
        return Set(entries.compactMap { entry in
            guard entry.date < today else { return nil }
            return AppCalendar.startOfDay(entry.date)
        })
    }

    private var entriesByDay: [Date: [DayEntry]] {
        Dictionary(grouping: entries) { AppCalendar.startOfDay($0.date) }
    }

    private var searchMatches: [DayEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return entries
            .filter { $0.rawText.localizedStandardContains(query) }
            .sorted { first, second in
                let firstDay = AppCalendar.startOfDay(first.date)
                let secondDay = AppCalendar.startOfDay(second.date)
                if firstDay != secondDay {
                    return firstDay < secondDay
                }
                return AgendaEntryOrdering.areInIncreasingOrder(first, second)
            }
    }

    private var searchMatchIDs: [UUID] {
        searchMatches.map(\.id)
    }

    private var currentSearchMatchEntry: DayEntry? {
        guard searchMatches.indices.contains(currentSearchMatch) else { return nil }
        return searchMatches[currentSearchMatch]
    }

    private var isRecurringMoveProcessing: Bool {
        recurringMoveController.offer?.phase == .processing
    }

    /// Changes only when the actively rescheduled series has visibly changed in
    /// Agenda's @Query. This distinguishes a completed private-context save
    /// from a completed UI merge.
    private var activeRecurringSeriesSignature: Int? {
        guard let offer = recurringMoveController.offer,
              offer.phase == .processing else { return nil }

        var hasher = Hasher()
        for entry in entries where entry.recurringItemIdentifier == offer.itemID {
            hasher.combine(entry.id)
            hasher.combine(entry.recurringOccurrenceKey)
            hasher.combine(entry.date)
            hasher.combine(entry.recurringDateOverride)
            hasher.combine(entry.rawText)
            hasher.combine(entry.manualOrder)
        }
        return hasher.finalize()
    }

    private var onboardingMoveExampleEntry: DayEntry? {
        let today = AppCalendar.startOfDay(.now)
        let todayEntries = entries
            .filter { AppCalendar.isSameDay($0.date, today) }
            .sorted(by: sortEntries)
        guard !todayEntries.isEmpty else { return nil }
        return todayEntries[min(2, todayEntries.count - 1)]
    }

    private var visibleOnboardingStep: Int? {
        isHelpExpanded && !hasCompletedAgendaTutorial ? agendaTutorialStep : nil
    }

    private var weeks: [WeekSection] {
        let today = AppCalendar.startOfDay(.now)
        let oldestOpenDate = entries
            .filter { $0.date < today }
            .map(\.date)
            .min()
        let startDate = oldestOpenDate ?? today
        let defaultEndDate = AppCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: loadedFutureWeeks,
            to: today
        ) ?? today
        let endDate = max(
            max(defaultEndDate, AppCalendar.startOfDay(moveDraftDate)),
            currentSearchMatchEntry.map { AppCalendar.startOfDay($0.date) } ?? today
        )
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
        let weatherByDay = weatherStore.days
        let firstWeatherWeekID = visibleWeeks.first { week in
            week.days.contains { weatherByDay[AppCalendar.startOfDay($0.date)] != nil }
        }?.id

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if isHelpExpanded {
                            AgendaHelpCard(
                                locale: locale,
                                step: agendaTutorialStep,
                                isCompleted: hasCompletedAgendaTutorial,
                                previous: showPreviousAgendaTutorialStep,
                                next: showNextAgendaTutorialStep,
                                replay: replayAgendaTutorial,
                                close: collapseHelp
                            )
                            .padding(.bottom, 4)
                        }

                        ForEach(Array(visibleWeeks.enumerated()), id: \.element.id) { index, week in
                            WeekCard(
                                week: week,
                                entriesByDay: groupedEntries,
                                weatherByDay: weatherByDay,
                                weatherAttribution: week.id == firstWeatherWeekID
                                    ? weatherStore.attribution
                                    : nil,
                                focusedField: $focusedField,
                                moveEntry: moveEntry,
                                moveEntryOneStep: moveEntryOneStep,
                                moveEntryToTodo: moveEntryToTodo,
                                todoGroups: todoGroups,
                                activeMoveEntryID: $activeMoveEntryID,
                                moveDraftDate: $moveDraftDate,
                                toggleMoveControls: toggleMoveControls,
                                removed: showRemovalUndo,
                                dayVisibilityChanged: updateDayVisibility,
                                entryVisibilityChanged: updateEntryVisibility,
                                onboardingStep: visibleOnboardingStep,
                                onboardingExampleIDs: Set([
                                    UUID(uuidString: agendaSportsExampleID),
                                    UUID(uuidString: agendaDinnerExampleID)
                                ].compactMap { $0 }),
                                hasPerformedOnboardingMove: hasPerformedAgendaTutorialMove,
                                onboardingEntryAdded: {
                                    completeAgendaTutorialAction(for: 0)
                                },
                                completed: { entry in
                                    showCompletionUndo(entry)
                                    completeAgendaTutorialAction(for: 3)
                                },
                                onboardingMoveEditingFinished: {
                                    completeAgendaTutorialAction(for: 2)
                                },
                                onboardingMoveCancelled: {
                                    returnToAgendaTutorialMoveStep()
                                },
                                searchMatchIDs: Set(searchMatchIDs),
                                currentSearchMatchID: searchMatchIDs.indices.contains(currentSearchMatch)
                                    ? searchMatchIDs[currentSearchMatch] : nil
                            )
                            .id(AgendaScrollTarget.week(week.startDate))
                            .onAppear {
                                if index >= visibleWeeks.count - 2 {
                                    queueMoreFutureWeeks(ifCurrentLimitIs: loadedWeekLimit)
                                }
                            }
                        }

                        if loadedWeekLimit < maximumFutureWeekCount {
                            AgendaFutureLoadingFooter(locale: locale)
                                .onAppear {
                                    queueMoreFutureWeeks(ifCurrentLimitIs: loadedWeekLimit)
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .adaptiveReadableWidth()
                }
                .contentMargins(.bottom, isSearchPresented ? 96 : 0, for: .scrollContent)
                // A series save can publish many changed DayEntry models in a
                // single frame. Keep the scroll position stable while SwiftData
                // merges that batch so lazy rows cannot be recycled mid-update.
                .scrollDisabled(isLoadingMoreFuture || isRecurringMoveProcessing)
                .allowsHitTesting(!isRecurringMoveProcessing)
                .agendaScrollCompatibility(
                    isScrolled: Binding(
                        get: { scrollPresentation.isScrolled },
                        set: { scrollPresentation.isScrolled = $0 }
                    )
                ) { isIdle in
                    visibilityCache.isScrollIdle = isIdle
                    if isIdle {
                        startPendingFutureLoad()
                    } else {
                        cancelDeferredFutureLoad()
                    }
                }
                .onChange(of: scrollTargetDate) { _, targetDate in
                    guard let targetDate else { return }

                    scrollTask?.cancel()
                    scrollTask = Task { @MainActor in
                        // Give SwiftUI one layout pass to insert a newly exposed
                        // week before asking the lazy stack for its day anchor.
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                        withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                            proxy.scrollTo(
                                AgendaScrollTarget.day(targetDate),
                                anchor: .center
                            )
                        }
                        scrollTargetDate = nil
                        scrollTask = nil
                    }
                }
                .onChange(of: searchText) { _, _ in
                    currentSearchMatch = 0
                    searchScrollRequest &+= 1
                }
                .onChange(of: searchScrollRequest) { _, _ in scrollToAgendaMatch(proxy) }
            }
            .background(Color.appCanvasBackground)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        AgendaTopTitle(
                            presentation: scrollPresentation,
                            locale: locale,
                            showsInfoHint: !hasOpenedAgendaHelp,
                            isHelpExpanded: isHelpExpanded,
                            toggleHelp: toggleHelp
                        )

                        HStack {
                            Button {
                                undoManager?.undo()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(width: 44, height: 44)
                            }
                            .compatibleAgendaGlassEffect()
                            .disabled(!(undoManager?.canUndo ?? false))
                            .accessibilityLabel("Laatste wijziging terugdraaien")

                            Spacer()

                            Button {
                                if isKeyboardVisible {
                                    isSearchFocused = false
                                    finishAgendaEditing()
                                    AppKeyboard.dismiss()
                                } else if isSearchPresented {
                                    searchText = ""
                                    isSearchFocused = false
                                    isSearchPresented = false
                                } else if activeMoveEntryID != nil {
                                    finishAgendaEditing()
                                } else {
                                    isSearchPresented = true
                                    Task { @MainActor in isSearchFocused = true }
                                }
                            } label: {
                                Image(systemName: (isKeyboardVisible || isSearchPresented || activeMoveEntryID != nil) ? "checkmark" : "magnifyingglass")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.brandHardBlue)
                                    .frame(width: 44, height: 44)
                            }
                            .compatibleAgendaGlassEffect()
                            .background(
                                visibleOnboardingStep == 2 && hasPerformedAgendaTutorialMove
                                    ? Color.brandLightBlue
                                    : Color.clear,
                                in: Circle()
                            )
                            .accessibilityLabel(
                                isKeyboardVisible
                                    ? "Toetsenbord sluiten"
                                    : (isSearchPresented ? "Zoeken sluiten" : ((activeMoveEntryID != nil) ? "Bewerken afsluiten" : "Zoeken"))
                            )
                            .overlay {
                                if visibleOnboardingStep == 2 && hasPerformedAgendaTutorialMove {
                                    Circle()
                                        .stroke(Color.brandHardBlue, lineWidth: 3)
                                        .padding(-4)
                                }
                            }
                        }
                    }
                    .padding(.leading, 22)
                    .padding(.trailing, 18)
                    .padding(.vertical, 6)
                    .adaptiveReadableWidth()

                    if isSearchPresented {
                        InlineMatchSearchBar(
                            text: $searchText,
                            isFocused: $isSearchFocused,
                            matchCount: searchMatchIDs.count,
                            currentMatch: currentSearchMatch,
                            next: advanceAgendaMatch,
                            clear: clearAgendaSearch
                        )
                        .adaptiveReadableWidth()
                    }

                    if recurringSyncState.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(locale.localized("recurring.loading"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .adaptiveReadableWidth()
                        .transition(.opacity)
                    }

                }
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                Group {
                    if recentlyMovedToDate != nil {
                        dateMoveUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if recentlyMovedToTodo != nil {
                        moveToTodoUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if recentlyRemovedEntry != nil {
                        removalUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if recentlyCompletedEntry != nil {
                        completionUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .adaptiveReadableWidth()
                .padding(.bottom, 4)
            }
            .overlay(alignment: .bottom) {
                AgendaRecurringMoveBar(
                    controller: recurringMoveController,
                    locale: locale,
                    apply: applyRecurringMoveOffer
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .adaptiveReadableWidth()
                .zIndex(10)
            }
            .onAppear {
                modelContext.undoManager = undoManager
                configureLoadedHorizon()
                localizeAgendaOnboardingExamplesIfPresent()
                if !hasPresentedAgendaHelp {
                    insertAgendaOnboardingExamplesIfNeeded()
                    hasPresentedAgendaHelp = true
                    isHelpExpanded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isSearchPresented = false
                }
            }
            .onDisappear {
                searchScrollTask?.cancel()
            }
            .task(id: "\(weatherInAgendaEnabled)|\(weatherLatitude)|\(weatherLongitude)|\(weatherReloadToken)") {
                await weatherStore.reload()
            }
            .onChange(of: languageSetting) { _, _ in
                localizeAgendaOnboardingExamplesIfPresent()
            }
            .onChange(of: recurringHorizon) { _, _ in
                configureLoadedHorizon()
            }
            .onChange(of: activeRecurringSeriesSignature) { oldValue, newValue in
                guard oldValue != nil, newValue != nil, oldValue != newValue else { return }
                recurringSeriesPresentationRevision &+= 1
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue == nil {
                    _ = PersistenceSafety.save(modelContext)
                    startPendingFutureLoad()
                } else {
                    // Text input always outranks speculative future loading.
                    cancelDeferredFutureLoad()
                }
            }
            .onDisappear {
                scrollTask?.cancel()
                visibilityCache.futureLoadTask?.cancel()
                dismissRecurringMoveOfferTask?.cancel()
                deferredRecurringMoveTask?.cancel()
                dismissDateMoveUndoTask?.cancel()
                flushDeferredMoveSave()
            }
        }
    }

    private func advanceAgendaMatch() {
        guard searchMatchIDs.count > 1 else { return }
        currentSearchMatch = (currentSearchMatch + 1) % searchMatchIDs.count
        searchScrollRequest &+= 1
    }

    private func clearAgendaSearch() {
        searchScrollTask?.cancel()
        lastSearchScrollTargetID = nil
        searchText = ""
        if !isKeyboardVisible {
            isSearchFocused = false
            isSearchPresented = false
        }
    }

    private func scrollToAgendaMatch(_ proxy: ScrollViewProxy) {
        guard let target = currentSearchMatchEntry else {
            searchScrollTask?.cancel()
            lastSearchScrollTargetID = nil
            return
        }
        let targetID = target.id
        guard targetID != lastSearchScrollTargetID else { return }

        let targetDate = AppCalendar.startOfDay(target.date)
        let targetWeek = AppCalendar.calendar.dateInterval(
            of: .weekOfYear,
            for: targetDate
        )?.start ?? targetDate

        searchScrollTask?.cancel()
        lastSearchScrollTargetID = targetID
        searchScrollTask = Task { @MainActor in
            // Coalesce successive keystrokes, but retain an in-flight scroll
            // when refining the query still points at this exact entry.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }

            if visibilityCache.entryIDs.contains(targetID) {
                // The matching row is already within a visible day. Keeping
                // the current position avoids a small recentering bump while
                // the search bar and keyboard finish changing the viewport.
                searchScrollTask = nil
                return
            } else {
                // Materialize a distant lazy week first. The final, usually
                // very small row alignment also animates so it cannot present
                // as a one-frame correction at the end of the movement.
                withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                    proxy.scrollTo(AgendaScrollTarget.week(targetWeek), anchor: .center)
                }
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
            searchScrollTask = nil
        }
    }

    private func scrollAgenda(
        _ targetID: UUID,
        with proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            proxy.scrollTo(targetID, anchor: .center)
        }
        if animated {
            withAnimation(.smooth(duration: 0.24, extraBounce: 0), action)
        } else {
            action()
        }
    }

    private func toggleHelp() {
        hasOpenedAgendaHelp = true
        if isHelpExpanded {
            collapseHelp()
            return
        }
        if !hasSeededAgendaExamples && !hasCompletedAgendaTutorial {
            insertAgendaOnboardingExamplesIfNeeded()
        }
        isHelpExpanded = true
    }

    private func collapseHelp() {
        isHelpExpanded = false
        removeAgendaOnboardingExamples()
    }

    private func removeAgendaOnboardingExamples() {
        let allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? entries
        var examplesToDelete: [DayEntry] = []

        // Older app versions did not always retain the example IDs. Only fall
        // back to matching their localized text when the corresponding ID is
        // unavailable, so a user-created entry with the same text is preserved
        // whenever the seeded example can be identified precisely.
        let knownTexts: [Set<String>] = [
            ["17u exercising", "16u sports (example)", "16u sporten", "4PM sports"],
            ["18u dinnertime", "18u dinner (example)", "18u uit eten", "6PM dinner"]
        ]
        let storedIDStrings = [agendaSportsExampleID, agendaDinnerExampleID]
        for index in knownTexts.indices {
            let storedExample = UUID(uuidString: storedIDStrings[index]).flatMap { id in
                allEntries.first { $0.id == id }
            }
            if let example = storedExample
                ?? allEntries.first(where: { knownTexts[index].contains($0.rawText) }) {
                examplesToDelete.append(example)
            }
        }

        for entry in Dictionary(uniqueKeysWithValues: examplesToDelete.map { ($0.id, $0) }).values {
            if activeMoveEntryID == entry.id {
                activeMoveEntryID = nil
            }
            modelContext.delete(entry)
        }

        agendaSportsExampleID = ""
        agendaDinnerExampleID = ""
        _ = PersistenceSafety.save(modelContext)
    }

    private func insertAgendaOnboardingExamplesIfNeeded(reset: Bool = false) {
        guard !hasSeededAgendaExamples || reset else { return }
        hasSeededAgendaExamples = true

        let today = AppCalendar.startOfDay(.now)
        let examples = agendaOnboardingExamples
        let allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? entries
        let legacyExamples = [
            "17u exercising": examples[0],
            "18u dinnertime": examples[1],
            "16u sports (example)": examples[0],
            "18u dinner (example)": examples[1]
        ]

        for (legacyText, newText) in legacyExamples {
            guard !allEntries.contains(where: { $0.rawText == newText }),
                  let legacyEntry = allEntries.first(where: { $0.rawText == legacyText }) else {
                continue
            }
            legacyEntry.rawText = newText
            legacyEntry.refreshParsedFields()
        }

        for (index, text) in examples.enumerated() {
            if let existing = allEntries.first(where: { $0.rawText == text }) {
                setAgendaExampleID(existing.id, at: index)
                if reset {
                    existing.date = today
                    existing.isDone = false
                    existing.isRemoved = false
                    existing.completedAt = nil
                    existing.manualOrder = Double(index)
                    existing.refreshParsedFields()
                }
            } else {
                let entry = DayEntry(date: today, rawText: text, manualOrder: Double(index))
                modelContext.insert(entry)
                setAgendaExampleID(entry.id, at: index)
            }
        }
        _ = PersistenceSafety.save(modelContext)
    }

    private var agendaOnboardingExamples: [String] {
        let selectedLocale = AppLanguage.resolved(from: languageSetting).locale
        return [
            selectedLocale.localized("onboarding.agenda.example.sports"),
            selectedLocale.localized("onboarding.agenda.example.dinner")
        ]
    }

    private func setAgendaExampleID(_ id: UUID, at index: Int) {
        if index == 0 {
            agendaSportsExampleID = id.uuidString
        } else {
            agendaDinnerExampleID = id.uuidString
        }
    }

    private func localizeAgendaOnboardingExamplesIfPresent() {
        guard hasSeededAgendaExamples else { return }
        let allEntries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? entries
        let examples = agendaOnboardingExamples
        let knownLegacyTexts: [Set<String>] = [
            ["17u exercising", "16u sports (example)", "16u sporten", "4PM sports"],
            ["18u dinnertime", "18u dinner (example)", "18u uit eten", "6PM dinner"]
        ]
        let storedIDs = [UUID(uuidString: agendaSportsExampleID), UUID(uuidString: agendaDinnerExampleID)]

        for index in examples.indices {
            let entry = storedIDs[index].flatMap { id in allEntries.first { $0.id == id } }
                ?? allEntries.first { knownLegacyTexts[index].contains($0.rawText) }
            guard let entry else { continue }

            setAgendaExampleID(entry.id, at: index)
            if entry.rawText != examples[index] {
                entry.rawText = examples[index]
                entry.refreshParsedFields()
            }
        }
        _ = PersistenceSafety.save(modelContext)
    }

    private func showPreviousAgendaTutorialStep() {
        if hasCompletedAgendaTutorial {
            hasCompletedAgendaTutorial = false
            showAgendaTutorialStep(AgendaHelpCard.stepCount - 1)
            return
        }
        showAgendaTutorialStep(agendaTutorialStep - 1)
    }

    private func showNextAgendaTutorialStep() {
        if agendaTutorialStep == 3 {
            finishAgendaTutorial()
            return
        }

        showAgendaTutorialStep(agendaTutorialStep + 1)
    }

    private func showAgendaTutorialStep(_ requestedStep: Int) {
        let targetStep = min(max(requestedStep, 0), AgendaHelpCard.stepCount - 1)
        hasPerformedAgendaTutorialMove = false

        if targetStep == 2, let entry = onboardingMoveExampleEntry {
            setMoveMode(entryID: entry.id, date: entry.date)
        } else {
            setMoveMode(entryID: nil)
        }

        agendaTutorialStep = targetStep
    }

    private func completeAgendaTutorialAction(for step: Int) {
        guard isHelpExpanded,
              !hasCompletedAgendaTutorial,
              agendaTutorialStep == step else { return }

        if step == 2 {
            activeMoveEntryID = nil
            agendaTutorialStep = 3
            hasPerformedAgendaTutorialMove = false
            return
        }

        if step == 3 {
            finishAgendaTutorial()
            return
        }

        agendaTutorialStep += 1
    }

    private func finishAgendaTutorial() {
        hasCompletedAgendaTutorial = true
    }

    private func finishAgendaEditing() {
        scrollTask?.cancel()
        focusedField = nil
        activeMoveEntryID = nil
        completeAgendaTutorialAction(for: 2)
    }

    private func scheduleDeferredMoveSave() {
        deferredMoveSaveTask?.cancel()
        deferredMoveSaveTask = Task { @MainActor in
            // Give the moved card and the independently observed prompt one
            // render opportunity. Repeated arrow taps share this single save.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            _ = PersistenceSafety.save(modelContext)
            deferredMoveSaveTask = nil
        }
    }

    private func flushDeferredMoveSave() {
        guard deferredMoveSaveTask != nil else { return }
        deferredMoveSaveTask?.cancel()
        deferredMoveSaveTask = nil
        _ = PersistenceSafety.save(modelContext)
    }

    private func recordAgendaTutorialMove() {
        guard isHelpExpanded,
              !hasCompletedAgendaTutorial,
              agendaTutorialStep == 2 else { return }
        hasPerformedAgendaTutorialMove = true
    }

    private func returnToAgendaTutorialMoveStep() {
        guard isHelpExpanded,
              !hasCompletedAgendaTutorial,
              agendaTutorialStep == 2 else { return }
        activeMoveEntryID = nil
        hasPerformedAgendaTutorialMove = false
        agendaTutorialStep = 1
    }

    private func replayAgendaTutorial() {
        hasCompletedAgendaTutorial = false
        agendaTutorialStep = 0
        activeMoveEntryID = nil
        hasPerformedAgendaTutorialMove = false
        insertAgendaOnboardingExamplesIfNeeded(reset: true)
    }

    private func showRemovalUndo(_ entry: DayEntry, eventIdentifier: String?) {
        dismissRemovalUndoTask?.cancel()
        recentlyCompletedEntry = nil
        recentlyMovedToTodo = nil
        recentlyRemovedEntry = entry
        recentlyRemovedEntryTitle = entry.rawText
        recentlyRemovedEventIdentifier = eventIdentifier
        dismissRemovalUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyRemovedEntry = nil
            }
        }
    }

    private func showCompletionUndo(_ entry: DayEntry) {
        dismissRemovalUndoTask?.cancel()
        recentlyRemovedEntry = nil
        recentlyMovedToTodo = nil
        withAnimation(.snappy(duration: 0.25)) {
            recentlyCompletedEntry = entry
        }
        dismissRemovalUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyCompletedEntry = nil
            }
        }
    }

    private func undoCompletion() {
        guard let entry = recentlyCompletedEntry else { return }
        entry.isDone = false
        entry.completedAt = nil
        _ = PersistenceSafety.save(modelContext)
        dismissRemovalUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyCompletedEntry = nil
        }
    }

    private var completionUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "checkmark.circle.fill",
            iconColor: .blue,
            message: completionUndoText,
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoCompletion,
            preferredMessageLineLimit: 2
        )
    }

    private var completionUndoText: String {
        guard let entry = recentlyCompletedEntry else { return "" }
        return locale.localizedFormat("feedback.movedToFinished", entry.rawText)
    }

    private func undoRemoval() {
        guard let entry = recentlyRemovedEntry else { return }
        entry.isDone = false
        entry.isRemoved = false
        entry.completedAt = nil
        if let identifier = recentlyRemovedEventIdentifier {
            CalendarSyncService.cancelEventDeletion(withIdentifier: identifier)
            entry.calendarEventIdentifier = identifier
        }
        _ = PersistenceSafety.save(modelContext)
        dismissRemovalUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyRemovedEntry = nil
        }
    }

    private var removalUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "trash.fill",
            iconColor: .red,
            message: locale.localizedFormat("feedback.deleted", recentlyRemovedEntryTitle),
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoRemoval
        )
    }

    private func moveEntry(_ entryID: UUID, to targetDate: Date, insertionIndex: Int? = nil) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }

        let originalDay = AppCalendar.startOfDay(entry.date)
        let day = AppCalendar.startOfDay(targetDate)

        if originalDay != day, entry.recurringItemIdentifier != nil {
            // Moving the row, saving it and scrolling the lazy agenda all
            // invalidate layout. Finish those operations before inserting the
            // prompt; starting them 16 ms after the popup appeared made its
            // first animation frames visibly stall.
            deferredRecurringMoveTask?.cancel()
            performMoveEntry(
                entryID,
                from: originalDay,
                to: day,
                insertionIndex: insertionIndex,
                shouldOfferRecurringShift: false
            )
            deferredRecurringMoveTask = Task { @MainActor in
                // The deferred move save runs after 80 ms and an offscreen
                // scroll finishes after roughly 230 ms. Presenting at 300 ms
                // keeps both completely outside the popup transition.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                guard let movedEntry = entries.first(where: { $0.id == entryID }) else {
                    deferredRecurringMoveTask = nil
                    return
                }
                showRecurringMoveOfferIfNeeded(
                    for: movedEntry,
                    from: originalDay,
                    to: day
                )
                deferredRecurringMoveTask = nil
            }
            return
        }

        performMoveEntry(
            entryID,
            from: originalDay,
            to: day,
            insertionIndex: insertionIndex,
            shouldOfferRecurringShift: true
        )
    }

    private func performMoveEntry(
        _ entryID: UUID,
        from originalDay: Date,
        to day: Date,
        insertionIndex: Int?,
        shouldOfferRecurringShift: Bool
    ) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        // Grouping the complete query just to find one destination day is
        // noticeably expensive for large agendas. A direct scan avoids the
        // dictionary allocation on the latency-sensitive move path.
        let targetEntries = entries
            .filter {
                !$0.isRemoved
                    && $0.id != entryID
                    && AppCalendar.isSameDay($0.date, day)
            }
            .sorted(by: sortEntries)
        let targetIndex = min(max(insertionIndex ?? targetEntries.count, 0), targetEntries.count)

        focusedField = nil
        let updateEntry = {
            entry.date = day
            moveDraftDate = day
            if entry.recurringItemIdentifier != nil {
                entry.recurringDateOverride = day
            }
            renumber(entries: targetEntries, inserting: entry, at: targetIndex)
        }
        if originalDay == day {
            withAnimation(.smooth(duration: 0.18, extraBounce: 0), updateEntry)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, updateEntry)
        }
        if originalDay != day {
            if shouldOfferRecurringShift {
                showRecurringMoveOfferIfNeeded(for: entry, from: originalDay, to: day)
            }
            if entry.recurringItemIdentifier == nil {
                showDateMoveUndo(for: entry, from: originalDay, to: day)
            }
            requestScroll(to: day)
        }
        scheduleDeferredMoveSave()
        recordAgendaTutorialMove()
    }

    private func showDateMoveUndo(for entry: DayEntry, from originalDate: Date, to targetDate: Date) {
        dismissDateMoveUndoTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) {
            recentlyMovedToDate = AgendaDateMoveUndo(
                entry: entry,
                originalDate: originalDate,
                targetDate: targetDate
            )
        }
        dismissDateMoveUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { recentlyMovedToDate = nil }
        }
    }

    private func undoDateMove() {
        guard let move = recentlyMovedToDate else { return }
        move.entry.date = move.originalDate
        if move.entry.recurringItemIdentifier != nil {
            move.entry.recurringDateOverride = move.originalDate
        }
        _ = PersistenceSafety.save(modelContext)
        dismissDateMoveUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { recentlyMovedToDate = nil }
        requestScroll(to: move.originalDate)
    }

    private var dateMoveUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "calendar.badge.checkmark",
            iconColor: .brandHardBlue,
            message: dateMoveUndoText,
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoDateMove,
            preferredMessageLineLimit: 2
        )
    }

    private var dateMoveUndoText: String {
        guard let move = recentlyMovedToDate else { return "" }
        let date = move.targetDate.formatted(date: .abbreviated, time: .omitted)
        return "‘\(move.entry.rawText)’\nverplaatst naar \(date)"
    }

    private func showRecurringMoveOfferIfNeeded(for entry: DayEntry, from originalDate: Date, to targetDate: Date) {
        guard let itemID = entry.recurringItemIdentifier,
              let item = recurringItems.first(where: { $0.id == itemID }),
              originalDate != targetDate else { return }

        let schedulePosition = RecurrenceEngine.scheduledEntryDate(
            for: entry.recurringOccurrenceKey,
            item: item
        )
        let seriesDate = schedulePosition?.entryDate ?? originalDate
        let effectiveFrom = schedulePosition?.effectiveFrom ?? originalDate

        dismissRecurringMoveOfferTask?.cancel()
        dismissDateMoveUndoTask?.cancel()
        recentlyMovedToDate = nil
        withAnimation(.snappy(duration: 0.25)) {
            recurringMoveController.offer = AgendaRecurringMoveOffer(
                itemID: itemID,
                effectiveFrom: effectiveFrom,
                seriesDate: seriesDate,
                targetDate: targetDate
            )
        }
        dismissRecurringMoveOfferTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recurringMoveController.offer = nil
            }
        }
    }

    private func applyRecurringMoveOffer() {
        guard var offer = recurringMoveController.offer,
              offer.phase == .prompt || offer.phase == .failure,
              let item = recurringItems.first(where: { $0.id == offer.itemID }) else { return }
        let offset = AppCalendar.calendar.dateComponents(
            [.day],
            from: AppCalendar.startOfDay(offer.seriesDate),
            to: AppCalendar.startOfDay(offer.targetDate)
        ).day ?? 0
        guard offset != 0 else { return }

        deferredMoveSaveTask?.cancel()
        deferredMoveSaveTask = nil
        dismissRecurringMoveOfferTask?.cancel()
        offer.phase = .processing
        // This is the same material card; only replace its contents. Animating
        // the whole phase also animates Material internals and briefly looks
        // like a second translucent card underneath the first one.
        var loadingTransaction = Transaction()
        loadingTransaction.disablesAnimations = true
        withTransaction(loadingTransaction) {
            recurringMoveController.offer = offer
        }
        dismissRecurringMoveOfferTask = Task { @MainActor in
            // Do not merely yield the main actor: that can resume in the same
            // render transaction. Keep the actor free for several display
            // frames, so the unchanged card and spinner are committed before
            // any save, plan construction, or series synchronization starts.
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            finishAgendaEditing()

            // Finishing edit mode can itself invalidate agenda rows. Give that
            // smaller update its own render pass as well instead of combining
            // it with the persistence transaction below.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let presentationRevisionBeforeSync = recurringSeriesPresentationRevision
            let dataRefreshRevisionBeforeSync = agendaDataRefreshState.revision

            var workingOffer = offer
            if !workingOffer.shiftWasSaved {
                RecurrenceEngine.appendScheduleShift(
                    effectiveFrom: workingOffer.effectiveFrom,
                    dayOffset: offset,
                    to: item
                )
                guard PersistenceSafety.save(modelContext) else {
                    workingOffer.phase = .failure
                    recurringMoveController.offer = workingOffer
                    return
                }
                workingOffer.shiftWasSaved = true
                workingOffer.phase = .processing
                recurringMoveController.offer = workingOffer
            }

            let endDate = AppCalendar.calendar.date(
                byAdding: .weekOfYear,
                value: loadedFutureWeeks,
                to: AppCalendar.startOfDay(.now)
            ) ?? offer.targetDate
            let modelContainer = modelContext.container
            let itemID = workingOffer.itemID
            let plan = RecurringScheduler.seriesPlan(
                for: item,
                from: AppCalendar.startOfDay(.now),
                through: endDate
            )
            let didChangeEntries: Bool
            do {
                didChangeEntries = try await Task.detached(priority: .userInitiated) {
                    try RecurringSeriesWorker.sync(
                        itemID: itemID,
                        plan: plan,
                        in: modelContainer
                    )
                }.value
            } catch {
                PersistenceSafety.report(error)
                var failedOffer = workingOffer
                failedOffer.phase = .failure
                recurringMoveController.offer = failedOffer
                return
            }

            let didSettle = await waitForRecurringSeriesToSettle(
                after: presentationRevisionBeforeSync,
                dataRefreshRevision: dataRefreshRevisionBeforeSync,
                expectsQueryChange: didChangeEntries
            )
            guard !Task.isCancelled else { return }
            guard didSettle else {
                var failedOffer = workingOffer
                failedOffer.phase = .failure
                recurringMoveController.offer = failedOffer
                return
            }

            var completedOffer = workingOffer
            completedOffer.phase = .success
            withAnimation(.easeInOut(duration: 0.2)) {
                recurringMoveController.offer = completedOffer
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                recurringMoveController.offer = nil
            }
        }
    }

    /// Waits for three distinct completion stages: SwiftData has published the
    /// series into this view, the resulting layout has gone quiet, and all
    /// debounced consumers of the same query have finished their work.
    private func waitForRecurringSeriesToSettle(
        after presentationRevision: Int,
        dataRefreshRevision: Int,
        expectsQueryChange: Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        if expectsQueryChange {
            let queryDeadline = clock.now.advanced(by: .seconds(5))

            while recurringSeriesPresentationRevision == presentationRevision,
                  clock.now < queryDeadline,
                  !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled,
                  recurringSeriesPresentationRevision != presentationRevision else {
                return false
            }

            // Require two quiet windows. A large @Query update may reach the lazy
            // hierarchy in more than one observation/layout pass.
            var stableRevision = recurringSeriesPresentationRevision
            var quietWindows = 0
            let layoutDeadline = clock.now.advanced(by: .seconds(3))
            while quietWindows < 2, clock.now < layoutDeadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return false }
                if recurringSeriesPresentationRevision != stableRevision {
                    stableRevision = recurringSeriesPresentationRevision
                    quietWindows = 0
                } else {
                    quietWindows += 1
                }
            }
            guard quietWindows == 2 else { return false }
        }

        // Widget and reminder publishers mark themselves busy immediately when
        // they receive the query change, including their debounce interval.
        let refreshDeadline = clock.now.advanced(by: .seconds(10))
        var derivedWorkDidFinish = !expectsQueryChange && !agendaDataRefreshState.isBusy
        while clock.now < refreshDeadline, !Task.isCancelled {
            let observedDerivedWork = !expectsQueryChange
                || agendaDataRefreshState.revision > dataRefreshRevision
            if observedDerivedWork && !agendaDataRefreshState.isBusy {
                derivedWorkDidFinish = true
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard derivedWorkDidFinish, !Task.isCancelled else { return false }

        // Leave one final quiet frame between the last derived task and the
        // success animation.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(100))
        return !Task.isCancelled && !agendaDataRefreshState.isBusy
    }

    private func loadMoreFutureWeeks(ifCurrentLimitIs expectedLimit: Int) {
        guard loadedFutureWeeks == expectedLimit,
              loadedFutureWeeks < maximumFutureWeekCount,
              !isLoadingMoreFuture,
              visibilityCache.futureLoadTask == nil else {
            return
        }

        let today = AppCalendar.startOfDay(.now)
        let currentEndDate = AppCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: loadedFutureWeeks,
            to: today
        ) ?? today
        let maximumEndDate = AppCalendar.calendar.date(
            byAdding: .month,
            value: 24,
            to: today
        ) ?? currentEndDate
        let proposedEndDate = AppCalendar.calendar.date(
            byAdding: .month,
            value: 3,
            to: currentEndDate
        ) ?? currentEndDate
        let endDate = min(proposedEndDate, maximumEndDate)
        let newLimit = weekCount(through: endDate)

        visibilityCache.futureLoadTask = Task { @MainActor in
            // Loading is speculative. Wait until scrolling has settled and
            // leave a generous window in which a tap can focus a text field.
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled,
                  visibilityCache.isScrollIdle,
                  focusedField == nil,
                  activeMoveEntryID == nil else {
                visibilityCache.futureLoadTask = nil
                return
            }

            visibilityCache.pendingFutureLoadLimit = nil
            isLoadingMoreFuture = true
            await Task.yield()
            guard !Task.isCancelled else {
                isLoadingMoreFuture = false
                visibilityCache.futureLoadTask = nil
                return
            }

            do {
                try RecurringScheduler.extendAll(
                    in: modelContext.container,
                    from: currentEndDate,
                    through: endDate
                )
                recurringExtendedThrough = max(
                    recurringExtendedThrough,
                    endDate.timeIntervalSinceReferenceDate
                )
                // Give the live @Query one run-loop turn to merge the single
                // store save before exposing the newly generated weeks.
                try? await Task.sleep(for: .milliseconds(50))
                loadedFutureWeeks = newLimit
            } catch {
                // Keep the current boundary; approaching it retries naturally.
            }
            isLoadingMoreFuture = false
            visibilityCache.futureLoadTask = nil
        }
    }

    private func queueMoreFutureWeeks(ifCurrentLimitIs expectedLimit: Int) {
        guard loadedFutureWeeks == expectedLimit,
              loadedFutureWeeks < maximumFutureWeekCount else {
            return
        }

        visibilityCache.pendingFutureLoadLimit = expectedLimit
        if visibilityCache.isScrollIdle {
            startPendingFutureLoad()
        }
    }

    private func startPendingFutureLoad() {
        guard visibilityCache.isScrollIdle,
              !isLoadingMoreFuture,
              focusedField == nil,
              activeMoveEntryID == nil,
              visibilityCache.futureLoadTask == nil,
              let expectedLimit = visibilityCache.pendingFutureLoadLimit else {
            return
        }

        loadMoreFutureWeeks(ifCurrentLimitIs: expectedLimit)
    }

    private func cancelDeferredFutureLoad() {
        guard !isLoadingMoreFuture else { return }
        visibilityCache.futureLoadTask?.cancel()
        visibilityCache.futureLoadTask = nil
    }

    private func configureLoadedHorizon() {
        visibilityCache.futureLoadTask?.cancel()
        visibilityCache.futureLoadTask = nil
        visibilityCache.pendingFutureLoadLimit = nil
        isLoadingMoreFuture = false
        let option = RecurringHorizonOption(rawValue: recurringHorizon) ?? .threeMonths
        let today = AppCalendar.startOfDay(.now)
        let configuredEndDate = AppCalendar.calendar.date(
            byAdding: .month,
            value: option.months,
            to: today
        ) ?? today
        // A previously generated recurrence range may be longer than the
        // user's current display preference. It must not make the initial
        // agenda (and its scroll indicator) longer than that preference.
        loadedFutureWeeks = min(
            weekCount(through: configuredEndDate),
            maximumFutureWeekCount
        )
    }

    private var maximumFutureWeekCount: Int {
        let today = AppCalendar.startOfDay(.now)
        let maximumEndDate = AppCalendar.calendar.date(
            byAdding: .month,
            value: 24,
            to: today
        ) ?? today
        return weekCount(through: maximumEndDate)
    }

    private func weekCount(through endDate: Date) -> Int {
        let days = AppCalendar.calendar.dateComponents(
            [.day],
            from: AppCalendar.startOfDay(.now),
            to: AppCalendar.startOfDay(endDate)
        ).day ?? 0
        return max(1, (max(0, days) + 6) / 7)
    }

    private func moveEntryToStartOfUntimedEntries(_ entryID: UUID, on targetDate: Date) {
        moveEntry(entryID, to: targetDate, insertionIndex: 0)
    }

    private func toggleMoveControls(for entry: DayEntry) {
        if activeMoveEntryID == entry.id {
            setMoveMode(entryID: nil)
            completeAgendaTutorialAction(for: 2)
            return
        }

        let entryDate = AppCalendar.startOfDay(entry.date)
        focusedField = nil
        AppKeyboard.dismiss()
        _ = PersistenceSafety.save(modelContext)
        setMoveMode(entryID: entry.id, date: entryDate)
        completeAgendaTutorialAction(for: 1)
    }

    private func setMoveMode(entryID: UUID?, date: Date? = nil) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeMoveEntryID = entryID
            if let date { moveDraftDate = date }
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
            .filter { !$0.isRemoved && AppCalendar.isSameDay($0.date, day) && !$0.hasTime && $0.id != entryID }
            .sorted(by: sortEntries)
        let currentEntries = entries
            .filter { !$0.isRemoved && AppCalendar.isSameDay($0.date, day) && !$0.hasTime }
            .sorted(by: sortEntries)

        guard let currentIndex = currentEntries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        let targetIndex = currentIndex + direction
        if currentEntries.indices.contains(targetIndex) {
            focusedField = nil
            renumber(entries: movableEntries, inserting: entry, at: targetIndex)
            _ = PersistenceSafety.save(modelContext)
            recordAgendaTutorialMove()
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

        let eventIdentifier = entry.calendarEventIdentifier
        let allEntries = ((try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? entries)
            .filter { !$0.isRemoved }
        CalendarSyncService.deleteEventIfUnshared(for: entry, among: allEntries)

        let todo = TodoItem(text: cleanText, bucket: .today)
        todo.bucketRawValue = groupID
        todo.showOnWidget = entry.showOnWidget
        let undo = AgendaTodoMoveUndo(
            todoID: todo.id,
            entryID: entry.id,
            destinationTitle: todoGroups.first(where: { $0.id == groupID })?.title ?? "Taken",
            date: entry.date,
            rawText: entry.rawText,
            sourceRawValue: entry.sourceRawValue,
            manualOrder: entry.manualOrder,
            showOnWidget: entry.showOnWidget,
            createdAt: entry.createdAt,
            calendarEventIdentifier: eventIdentifier,
            recurringItemIdentifier: entry.recurringItemIdentifier,
            recurringOccurrenceKey: entry.recurringOccurrenceKey,
            recurringDateOverride: entry.recurringDateOverride,
            accentRawValue: entry.accentRawValue
        )
        modelContext.insert(todo)
        modelContext.delete(entry)
        activeMoveEntryID = nil
        _ = PersistenceSafety.save(modelContext)
        showMoveToTodoUndo(undo)
        returnToAgendaTutorialMoveStep()
    }

    private func showMoveToTodoUndo(_ move: AgendaTodoMoveUndo) {
        dismissRemovalUndoTask?.cancel()
        recentlyCompletedEntry = nil
        recentlyRemovedEntry = nil
        withAnimation(.snappy(duration: 0.25)) {
            recentlyMovedToTodo = move
        }
        dismissRemovalUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyMovedToTodo = nil
            }
        }
    }

    private func undoMoveToTodo() {
        guard let move = recentlyMovedToTodo else { return }

        let todos = (try? modelContext.fetch(FetchDescriptor<TodoItem>())) ?? []
        if let todo = todos.first(where: { $0.id == move.todoID }) {
            modelContext.delete(todo)
        }

        let entry = DayEntry(
            date: move.date,
            rawText: move.rawText,
            source: EntrySource(rawValue: move.sourceRawValue) ?? .manual,
            manualOrder: move.manualOrder
        )
        entry.id = move.entryID
        entry.showOnWidget = move.showOnWidget
        entry.createdAt = move.createdAt
        entry.calendarEventIdentifier = move.calendarEventIdentifier
        entry.recurringItemIdentifier = move.recurringItemIdentifier
        entry.recurringOccurrenceKey = move.recurringOccurrenceKey
        entry.recurringDateOverride = move.recurringDateOverride
        entry.accentRawValue = move.accentRawValue
        modelContext.insert(entry)

        if let identifier = move.calendarEventIdentifier {
            CalendarSyncService.cancelEventDeletion(withIdentifier: identifier)
        }
        _ = PersistenceSafety.save(modelContext)
        dismissRemovalUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyMovedToTodo = nil
        }
    }

    private var moveToTodoUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "arrow.left.arrow.right",
            iconColor: .blue,
            message: locale.localizedFormat(
                "feedback.movedTo",
                recentlyMovedToTodo?.rawText ?? "",
                recentlyMovedToTodo?.destinationTitle ?? AppSection.todo.title(for: locale)
            ),
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoMoveToTodo
        )
    }

    private func requestScroll(to date: Date) {
        let day = AppCalendar.startOfDay(date)
        guard !visibilityCache.dates.contains(day) else { return }
        if day > AppCalendar.startOfDay(.now) {
            let weeksAhead = AppCalendar.calendar.dateComponents(
                [.weekOfYear],
                from: AppCalendar.startOfDay(.now),
                to: day
            ).weekOfYear ?? 0
            loadedFutureWeeks = max(loadedFutureWeeks, weeksAhead + 1)
        }
        scrollTargetDate = day
    }

    private func updateDayVisibility(_ date: Date, isVisible: Bool) {
        let day = AppCalendar.startOfDay(date)
        if isVisible {
            visibilityCache.dates.insert(day)
        } else {
            visibilityCache.dates.remove(day)
        }
    }

    private func updateEntryVisibility(_ id: UUID, isVisible: Bool) {
        if isVisible {
            visibilityCache.entryIDs.insert(id)
        } else {
            visibilityCache.entryIDs.remove(id)
        }
    }

    private func sortEntries(_ first: DayEntry, _ second: DayEntry) -> Bool {
        AgendaEntryOrdering.areInIncreasingOrder(first, second)
    }

    private func renumber(entries targetEntries: [DayEntry], inserting entry: DayEntry, at targetIndex: Int) {
        var reordered = targetEntries
        reordered.insert(entry, at: targetIndex)

        for (index, entry) in reordered.enumerated() {
            entry.manualOrder = Double(index)
        }
    }

}

private struct AgendaTopTitle: View {
    let presentation: AgendaScrollPresentation
    let locale: Locale
    let showsInfoHint: Bool
    let isHelpExpanded: Bool
    let toggleHelp: () -> Void

    var body: some View {
        Button(action: toggleHelp) {
            HStack(spacing: 6) {
                Text(AppSection.agenda.title(for: locale))
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
        .opacity(presentation.isScrolled ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: presentation.isScrolled)
        .accessibilityLabel(locale.localized("Uitleg over Agenda"))
        .accessibilityValue(isHelpExpanded
            ? locale.localized("Uitgeklapt")
            : locale.localized("Ingeklapt"))
        .accessibilityHint(locale.localized("Tik om de uitleg in of uit te klappen"))
    }
}

private struct AgendaHelpStep: Identifiable {
    let id: Int
    let icon: String
    let key: String
    let noteKey: String?

    func text(for locale: Locale) -> String {
        locale.localized(key)
    }

    func note(for locale: Locale) -> String? {
        noteKey.map(locale.localized)
    }
}

private struct AgendaHelpCard: View {
    static let stepCount = 4

    let locale: Locale
    let step: Int
    let isCompleted: Bool
    let previous: () -> Void
    let next: () -> Void
    let replay: () -> Void
    let close: () -> Void

    private let steps = [
        AgendaHelpStep(
            id: 0,
            icon: "text.cursor",
            key: "Tik achter een dag om iets te schrijven. Klaar? Tik rechtsboven op ✓.",
            noteKey: nil,
        ),
        AgendaHelpStep(
            id: 1,
            icon: "arrow.up.arrow.down",
            key: "Tik op de weekdag vóór de lijn om de verplaatsmodus te openen.",
            noteKey: nil,
        ),
        AgendaHelpStep(
            id: 2,
            icon: "calendar.badge.clock",
            key: "Gebruik de controls, of tik op een andere weekdag om direct te verplaatsen.",
            noteKey: "Een geel gearceerde weekdag bevat een tijd en blijft binnen de dag automatisch op tijd gesorteerd.",
        ),
        AgendaHelpStep(
            id: 3,
            icon: "checkmark.circle",
            key: "Iets afgerond? Tik op de cirkel rechts. Het verhuist naar Afgerond.",
            noteKey: nil,
        ),
    ]

    private var currentStep: AgendaHelpStep {
        steps[min(max(step, 0), steps.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isCompleted {
                completedContent
            } else {
                stepContent
            }
        }
        .tutorialCardStyle(isCompleted: isCompleted, close: close)
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            instructionContent

            navigationControls
                .id(step)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }

    private var instructionContent: some View {
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

                Text(currentStep.text(for: locale))
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = currentStep.note(for: locale) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)

                    Text(highlightedNote(note))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func highlightedNote(_ note: String) -> AttributedString {
        var text = AttributedString(note)
        let highlightedWord = locale.localized("tutorial.highlight.yellowWord")

        if let range = text.range(of: highlightedWord, options: [.caseInsensitive]) {
            text[range].backgroundColor = Color.yellow.opacity(0.34)
        }
        return text
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

    private var completedContent: some View {
        TutorialCompletionContent(
            message: locale.localized("Je agenda staat klaar voor alles wat komt."),
            replayTitle: locale.localized("Opnieuw"),
            backAccessibilityLabel: locale.localized("Vorige stap"),
            closeAccessibilityLabel: locale.localized("Sluiten"),
            back: previous,
            replay: replay,
            close: close
        )
    }
}

private struct AgendaFutureLoadingFooter: View {
    let locale: Locale

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(locale.localized("Volgende 3 maanden laden…"))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 51)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCardBackground)
        }
        .accessibilityElement(children: .combine)
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
    static var weekdayWidth: CGFloat {
        switch AppCalendar.weekdayLabelLength {
        case 1: 14
        case 2: 22
        default: 30
        }
    }
    static let dateWeekdaySpacing: CGFloat = 2
    static let lineSpacing: CGFloat = 6
    static let lineWidth: CGFloat = 1
    static let rowSpacing: CGFloat = 8
    static let completionControlInset: CGFloat = 8
    static let weatherBadgeWidth: CGFloat = 48
    static let moveActionSpacing: CGFloat = 8
    static let categoryControlWidth: CGFloat = 22
    static let dateControlWidth: CGFloat = 76
    static let stepControlWidth: CGFloat = 24
    static let finishControlWidth: CGFloat = 20
    static let onboardingControlsTrailingSpace: CGFloat = 6

    static var moveControlsFixedWidth: CGFloat {
        categoryControlWidth + dateControlWidth
            + (2 * stepControlWidth) + finishControlWidth
    }

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
    let weatherByDay: [Date: AgendaWeatherDay]
    let weatherAttribution: AgendaWeatherAttribution?
    let focusedField: FocusState<AgendaField?>.Binding
    let moveEntry: (UUID, Date, Int?) -> Void
    let moveEntryOneStep: (UUID, Int) -> Void
    let moveEntryToTodo: (UUID, String) -> Void
    let todoGroups: [TodoGroup]
    @Binding var activeMoveEntryID: UUID?
    @Binding var moveDraftDate: Date
    let toggleMoveControls: (DayEntry) -> Void
    let removed: (DayEntry, String?) -> Void
    let dayVisibilityChanged: (Date, Bool) -> Void
    let entryVisibilityChanged: (UUID, Bool) -> Void
    let onboardingStep: Int?
    let onboardingExampleIDs: Set<UUID>
    let hasPerformedOnboardingMove: Bool
    let onboardingEntryAdded: () -> Void
    let completed: (DayEntry) -> Void
    let onboardingMoveEditingFinished: () -> Void
    let onboardingMoveCancelled: () -> Void
    let searchMatchIDs: Set<UUID>
    let currentSearchMatchID: UUID?

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

    private var startYear: Int {
        AppCalendar.calendar.component(.year, from: week.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "week #\(week.weekNumber) · start \(startDateLabel) · \(startYear)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    DefaultColorCombination.isEnabled
                        ? Color.brandHardBlue.opacity(0.70)
                        : Color.secondary
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleDays) { day in
                    DayBlock(
                        day: day,
                        entries: entriesByDay[day.date] ?? [],
                        weather: weatherByDay[AppCalendar.startOfDay(day.date)],
                        focusedField: focusedField,
                        moveEntry: moveEntry,
                        moveEntryOneStep: moveEntryOneStep,
                        moveEntryToTodo: moveEntryToTodo,
                        todoGroups: todoGroups,
                        activeMoveEntryID: $activeMoveEntryID,
                        moveDraftDate: $moveDraftDate,
                        toggleMoveControls: toggleMoveControls,
                        removed: removed,
                        dayVisibilityChanged: dayVisibilityChanged,
                        entryVisibilityChanged: entryVisibilityChanged,
                        onboardingStep: onboardingStep,
                        onboardingExampleIDs: onboardingExampleIDs,
                        hasPerformedOnboardingMove: hasPerformedOnboardingMove,
                        onboardingEntryAdded: onboardingEntryAdded,
                        completed: completed,
                        onboardingMoveEditingFinished: onboardingMoveEditingFinished,
                        onboardingMoveCancelled: onboardingMoveCancelled,
                        searchMatchIDs: searchMatchIDs,
                        currentSearchMatchID: currentSearchMatchID
                    )
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(Color.appCardOutline, lineWidth: 1)
        }


            if let weatherAttribution {
                AgendaWeatherAttributionLink(attribution: weatherAttribution)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
            }
        }
    }
}

private struct AgendaWeatherAttributionLink: View {
    @Environment(\.colorScheme) private var colorScheme
    let attribution: AgendaWeatherAttribution

    var body: some View {
        Link(destination: attribution.legalPageURL) {
            AsyncImage(url: markURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Text("Apple Weather")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 82, height: 13)
        }
        .accessibilityLabel("Apple Weather, broninformatie")
    }

    private var markURL: URL {
        colorScheme == .dark ? attribution.lightMarkURL : attribution.darkMarkURL
    }
}

struct DayBlock: View {
    let day: DayInfo
    let entries: [DayEntry]
    let weather: AgendaWeatherDay?
    let focusedField: FocusState<AgendaField?>.Binding
    let moveEntry: (UUID, Date, Int?) -> Void
    let moveEntryOneStep: (UUID, Int) -> Void
    let moveEntryToTodo: (UUID, String) -> Void
    let todoGroups: [TodoGroup]
    @Binding var activeMoveEntryID: UUID?
    @Binding var moveDraftDate: Date
    let toggleMoveControls: (DayEntry) -> Void
    let removed: (DayEntry, String?) -> Void
    let dayVisibilityChanged: (Date, Bool) -> Void
    let entryVisibilityChanged: (UUID, Bool) -> Void
    let onboardingStep: Int?
    let onboardingExampleIDs: Set<UUID>
    let hasPerformedOnboardingMove: Bool
    let onboardingEntryAdded: () -> Void
    let completed: (DayEntry) -> Void
    let onboardingMoveEditingFinished: () -> Void
    let onboardingMoveCancelled: () -> Void
    let searchMatchIDs: Set<UUID>
    let currentSearchMatchID: UUID?

    private var sortedEntries: [DayEntry] {
        entries.sorted(by: AgendaEntryOrdering.areInIncreasingOrder)
    }

    private var nextUntimedManualOrder: Double {
        let currentUntimedOrders = sortedEntries
            .filter { !$0.hasTime }
            .map(\.manualOrder)
        return (currentUntimedOrders.max() ?? -1) + 1
    }

    private var onboardingExampleIndex: Int? {
        guard AppCalendar.isSameDay(day.date, .now), !sortedEntries.isEmpty else { return nil }
        return min(2, sortedEntries.count - 1)
    }

    private var onboardingCompletionIndex: Int? {
        guard AppCalendar.isSameDay(day.date, .now), !sortedEntries.isEmpty else { return nil }
        return sortedEntries.firstIndex { !onboardingExampleIDs.contains($0.id) }
            ?? onboardingExampleIndex
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
                            weather: day.date >= AppCalendar.startOfDay(.now)
                                ? weather
                                : nil,
                            focusedField: focusedField,
                            isMoveModeActive: activeMoveEntryID != nil,
                            isMoveTargetHighlighted: false,
                            moveActiveEntryHere: moveActiveEntryHere,
                            finishMove: finishMove,
                            isOnboardingHighlighted: onboardingStep == 0
                                && AppCalendar.isSameDay(day.date, .now),
                            entryAdded: onboardingEntryAdded
                        )
                    } else {
                        ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                            AgendaEntryLine(
                                dateLabel: index == 0 ? day.dateLabel : "",
                                weekdayLetter: day.weekdayLetter,
                                entry: entry,
                                weather: index == 0 && day.date >= AppCalendar.startOfDay(.now)
                                    ? weather
                                    : nil,
                                focusedField: focusedField,
                                isMoveActive: activeMoveEntryID == entry.id,
                                isMoveModeActive: activeMoveEntryID != nil,
                                isMoveTargetHighlighted: activeMoveEntryID != nil
                                    && activeMoveEntryID != entry.id
                                    && entry.hasTime,
                                moveDraftDate: $moveDraftDate,
                                handlePrefixTap: {
                                    if activeMoveEntryID == nil || activeMoveEntryID == entry.id {
                                        toggleMoveControls(entry)
                                    } else {
                                        moveActiveEntry(before: entry)
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
                                },
                                moveToTodo: { groupID in
                                    moveEntryToTodo(entry.id, groupID)
                                },
                                todoGroups: todoGroups,
                                removed: removed,
                                finishMove: finishMove,
                                highlightsMoveHandle: onboardingStep == 1
                                    && index == onboardingExampleIndex,
                                highlightsMoveControls: onboardingStep == 2
                                    && entry.id == activeMoveEntryID
                                    && !hasPerformedOnboardingMove,
                                highlightsMoveFinish: onboardingStep == 2
                                    && entry.id == activeMoveEntryID
                                    && hasPerformedOnboardingMove,
                                highlightsCompletion: onboardingStep == 3
                                    && index == onboardingCompletionIndex,
                                completed: completed,
                                onboardingMoveCancelled: onboardingMoveCancelled,
                                isSearchMatch: searchMatchIDs.contains(entry.id),
                                isCurrentSearchMatch: currentSearchMatchID == entry.id
                            )
                            .agendaVisibilityCompatibility { isVisible in
                                entryVisibilityChanged(entry.id, isVisible)
                            }
                        }

                        AgendaInputLine(
                            dateLabel: "",
                            weekdayLetter: day.weekdayLetter,
                            date: day.date,
                            nextOrder: nextUntimedManualOrder,
                            weather: nil,
                            focusedField: focusedField,
                            isMoveModeActive: activeMoveEntryID != nil,
                            isMoveTargetHighlighted: false,
                            moveActiveEntryHere: moveActiveEntryHere,
                            finishMove: finishMove,
                            isOnboardingHighlighted: onboardingStep == 0
                                && AppCalendar.isSameDay(day.date, .now),
                            entryAdded: onboardingEntryAdded
                        )
                    }
                }
                .transaction { transaction in
                    if activeMoveEntryID == nil {
                        transaction.animation = nil
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
        .transaction { transaction in
            if activeMoveEntryID == nil {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .agendaVisibilityCompatibility { isVisible in
            dayVisibilityChanged(day.date, isVisible)
        }
    }

    private func moveActiveEntryHere() {
        guard let activeMoveEntryID else { return }
        moveEntry(activeMoveEntryID, day.date, nil)
    }

    private func moveActiveEntry(before targetEntry: DayEntry) {
        guard let activeMoveEntryID, activeMoveEntryID != targetEntry.id else { return }

        let targetEntries = sortedEntries.filter { $0.id != activeMoveEntryID }
        guard let targetIndex = targetEntries.firstIndex(where: { $0.id == targetEntry.id }) else {
            return
        }

        moveEntry(activeMoveEntryID, day.date, targetIndex)
    }

    private func handleDayLineTap() {
        if activeMoveEntryID != nil {
            moveActiveEntryHere()
        } else {
            focusedField.wrappedValue = .newEntry(day.date)
        }
    }

    private func finishMove() {
        activeMoveEntryID = nil
        onboardingMoveEditingFinished()
    }

}

struct AgendaEntryLine: View {
    let dateLabel: String
    let weekdayLetter: String

    @Bindable var entry: DayEntry
    let weather: AgendaWeatherDay?
    let focusedField: FocusState<AgendaField?>.Binding
    let isMoveActive: Bool
    let isMoveModeActive: Bool
    let isMoveTargetHighlighted: Bool
    @Binding var moveDraftDate: Date
    let handlePrefixTap: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveToDate: () -> Void
    let moveToTodo: (String) -> Void
    let todoGroups: [TodoGroup]
    let removed: (DayEntry, String?) -> Void
    let finishMove: () -> Void
    let highlightsMoveHandle: Bool
    let highlightsMoveControls: Bool
    let highlightsMoveFinish: Bool
    let highlightsCompletion: Bool
    let completed: (DayEntry) -> Void
    let onboardingMoveCancelled: () -> Void
    let isSearchMatch: Bool
    let isCurrentSearchMatch: Bool

    @Environment(\.modelContext)
    private var modelContext

    @State private var isDeleting = false
    @State private var draftText: String?
    @State private var moveSelectionToEndToken = 0
    @State private var isProtectingInitialTap = false
    @State private var initialTapProtectionTask: Task<Void, Never>?
    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""

    var body: some View {
        VStack(alignment: .leading, spacing: isMoveActive ? 5 : 0) {
            HStack(alignment: .top, spacing: AgendaLayout.rowSpacing) {
                AgendaLinePrefix(
                    dateLabel: dateLabel,
                    weekdayLetter: weekdayLetter,
                    date: entry.date,
                    isMoveActive: isMoveActive,
                    isMoveTargetHighlighted: isMoveTargetHighlighted,
                    isOnboardingHighlighted: highlightsMoveHandle
                )
                    .contentShape(Rectangle())
                    .onTapGesture(perform: activateMoveHandle)
                    .accessibilityLabel("Verplaatsopties")

                entryContent

                if entry.isUncertain {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                Spacer(minLength: 2)

                completionControl
            }

            if isMoveActive {
                AgendaMoveControls(
                    date: $moveDraftDate,
                    moveUp: moveUp,
                    moveDown: moveDown,
                    moveToDate: moveToDate,
                    moveToTodo: moveToTodo,
                    remove: {
                        onboardingMoveCancelled()
                        removeEntry()
                    },
                    todoGroups: todoGroups,
                    finishMove: finishMove,
                    highlightsControls: highlightsMoveControls,
                    highlightsFinish: highlightsMoveFinish
                )
            }
        }
        .modifier(SearchMatchHighlight(isMatch: isSearchMatch, isCurrent: isCurrentSearchMatch))
        .id(entry.id)
        .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
            if !isDeleting, oldValue == .entry(entry.id), newValue != oldValue {
                commitDraft()
            }

            if newValue == .entry(entry.id), oldValue != newValue {
                prepareDraftForEditing()
            }
        }
        .onDisappear {
            initialTapProtectionTask?.cancel()
            commitDraft()
        }
        .transaction { transaction in
            if !isMoveModeActive {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    @ViewBuilder private var completionControl: some View {
        if let weather, !entry.isDone {
            AgendaWeatherBadge(weather: weather)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleDone)
                .accessibilityLabel("\(weather.temperature) graden, afvinken")
                .overlay {
                    if highlightsCompletion {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.brandHardBlue, lineWidth: 3)
                            .padding(.horizontal, -4)
                            .padding(.vertical, -5)
                    }
                }
                .offset(x: -AgendaLayout.completionControlInset)
        } else {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entryAccentColor)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
                .contentShape(Circle())
                .onTapGesture(perform: toggleDone)
                .accessibilityLabel("Afvinken")
                .overlay {
                    if highlightsCompletion {
                        Circle()
                            .stroke(Color.brandHardBlue, lineWidth: 3)
                            .padding(-5)
                    }
                }
                // Apply the offset after the onboarding overlay so the ring,
                // checkbox and hit area stay centered on the same axis.
                .offset(x: -AgendaLayout.completionControlInset)
        }
    }

    @ViewBuilder private var entryContent: some View {
        Group {
            if isMoveModeActive {
                Text(editableText.isEmpty ? " " : editableText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: finishMove)
                    .accessibilityLabel("Verplaatsmodus afsluiten")
            } else {
                Text(editableText.isEmpty ? " " : editableText)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            compatibleTextField
                                .textFieldStyle(.plain)
                                .focused(focusedField, equals: .entry(entry.id))
                                .lineLimit(1...)
                                .onChange(of: draftText) { _, newValue in
                                    guard let newValue else { return }
                                    handleTextChange(newValue)
                                }

                            if focusedField.wrappedValue != .entry(entry.id) || isProtectingInitialTap {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        beginEditing()
                                    }
                                    .accessibilityLabel("Regel bewerken")
                            }
                        }
                    }
            }
        }
        .font(.system(size: 16, weight: .regular))
        .lineLimit(1...)
        .strikethrough(entry.isDone)
        .foregroundStyle(entry.isDone ? Color.secondary : entryAccentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var compatibleTextField: some View {
        if #available(iOS 18.0, *) {
            AgendaSelectionTextField(
                text: draftBinding,
                moveSelectionToEndToken: moveSelectionToEndToken
            )
        } else {
            TextField("", text: draftBinding, axis: .vertical)
        }
    }

    private var editableText: String {
        draftText ?? entry.rawText
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { editableText },
            set: { draftText = $0 }
        )
    }

    private func beginEditing() {
        if focusedField.wrappedValue != .entry(entry.id) {
            prepareDraftForEditing()
            protectInitialTap()
            focusedField.wrappedValue = .entry(entry.id)
        } else {
            moveSelectionToEnd()
        }
    }

    private func activateMoveHandle() {
        if focusedField.wrappedValue == .entry(entry.id) {
            commitDraft()
        }
        focusedField.wrappedValue = nil
        AppKeyboard.dismiss()
        handlePrefixTap()
    }

    private func prepareDraftForEditing() {
        if draftText == nil {
            draftText = entry.rawText
        }
        moveSelectionToEnd()
    }

    private func moveSelectionToEnd() {
        moveSelectionToEndToken &+= 1
    }

    private func protectInitialTap() {
        initialTapProtectionTask?.cancel()
        isProtectingInitialTap = true

        initialTapProtectionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            isProtectingInitialTap = false
            initialTapProtectionTask = nil
        }
    }

    private func handleTextChange(_ newValue: String) {
        if newValue.contains("\n") {
            draftText = newValue.replacingOccurrences(of: "\n", with: "")
            commitDraft()
            focusedField.wrappedValue = nil
        }
    }

    private func commitDraft() {
        guard !isDeleting, let draftText else { return }

        initialTapProtectionTask?.cancel()
        initialTapProtectionTask = nil
        isProtectingInitialTap = false

        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteEntry()
            return
        }

        if entry.rawText != draftText {
            entry.rawText = draftText
        }
        entry.refreshParsedFields()
        self.draftText = nil
        _ = PersistenceSafety.save(modelContext)
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
            _ = PersistenceSafety.save(modelContext)

            if !eventIsShared, let eventIdentifier {
                CalendarSyncService.enqueueEventDeletion(withIdentifier: eventIdentifier)
            }
        }
    }

    private func removeEntry() {
        guard !isDeleting else { return }
        isDeleting = true
        focusedField.wrappedValue = nil
        AppKeyboard.dismiss()

        let eventIdentifier = entry.calendarEventIdentifier
        let activeEntries = ((try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? [])
            .filter { !$0.isRemoved }
        CalendarSyncService.deleteEventIfUnshared(for: entry, among: activeEntries)
        entry.isDone = false
        entry.isRemoved = true
        entry.completedAt = .now
        finishMove()
        _ = PersistenceSafety.save(modelContext)
        removed(entry, eventIdentifier)
    }

    private func toggleDone() {
        entry.toggleDone()
        _ = PersistenceSafety.save(modelContext)
        if entry.isDone {
            completed(entry)
        }
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
        RecurringThemeColorOption(rawValue: rawValue)?.color ?? .primary
    }
}

@available(iOS 18.0, *)
private struct AgendaSelectionTextField: View {
    @Binding var text: String
    let moveSelectionToEndToken: Int

    @State private var selection: TextSelection?

    var body: some View {
        TextField("", text: $text, selection: $selection, axis: .vertical)
            .onAppear(perform: moveSelectionToEnd)
            .onChange(of: moveSelectionToEndToken) { _, _ in
                moveSelectionToEnd()
            }
    }

    private func moveSelectionToEnd() {
        selection = TextSelection(insertionPoint: text.endIndex)
    }
}

struct AgendaInputLine: View {
    let dateLabel: String
    let weekdayLetter: String
    let date: Date
    let nextOrder: Double
    let weather: AgendaWeatherDay?
    let focusedField: FocusState<AgendaField?>.Binding
    let isMoveModeActive: Bool
    let isMoveTargetHighlighted: Bool
    let moveActiveEntryHere: () -> Void
    let finishMove: () -> Void
    let isOnboardingHighlighted: Bool
    let entryAdded: () -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""
    @State private var textFieldResetToken = 0
    @State private var suppressFocusCommit = false

    private var cleanText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AgendaLayout.rowSpacing) {
            AgendaLinePrefix(
                dateLabel: dateLabel,
                weekdayLetter: weekdayLetter,
                date: date,
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

            Text(text.isEmpty ? " " : text)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        TextField("", text: $text, axis: .vertical)
                            .id(textFieldResetToken)
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
                            .allowsHitTesting(!isMoveModeActive)

                        if isMoveModeActive {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: finishMove)
                                .accessibilityLabel("Verplaatsmodus afsluiten")
                        }
                    }
                }
            .font(.system(size: 16, weight: .regular))
            .lineLimit(1...)
            .foregroundStyle(.primary)
            .overlay {
                if isOnboardingHighlighted {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.brandHardBlue, lineWidth: 3)
                        .padding(.leading, -4)
                        .padding(.trailing, 2)
                        .padding(.vertical, -5)
                }
            }

            if let weather, cleanText.isEmpty {
                AgendaWeatherBadge(weather: weather)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isMoveModeActive {
                            finishMove()
                        } else {
                            focusedField.wrappedValue = .newEntry(date)
                        }
                    }
                    .offset(x: -AgendaLayout.completionControlInset)
            } else {
                Button {
                    addEntry()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .opacity(cleanText.isEmpty ? 0 : 1)
                .offset(x: -AgendaLayout.completionControlInset)
            }
        }
        .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
            if oldValue == .newEntry(date),
               newValue != oldValue,
               !suppressFocusCommit {
                addEntry(continueEditing: false)
            }
        }
        .onDisappear {
            addEntry(continueEditing: false)
        }
        .transaction { transaction in
            if !isMoveModeActive {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private func addEntry(continueEditing: Bool = true) {
        guard !cleanText.isEmpty else {
            return
        }

        suppressFocusCommit = true
        let entry = DayEntry(
            date: date,
            rawText: cleanText,
            manualOrder: nextOrder
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            text = ""
            textFieldResetToken &+= 1
            modelContext.insert(entry)
        }
        entryAdded()

        Task { @MainActor in
            await Task.yield()
            text = ""
            if continueEditing {
                // Enter and the plus button continue on a fresh entry for this day.
                focusedField.wrappedValue = .newEntry(date)
            }
            suppressFocusCommit = false
        }
    }

    private func finishEntry() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            focusedField.wrappedValue = nil
        }
        AppKeyboard.dismiss()
        addEntry(continueEditing: false)
    }
}

private struct AgendaWeatherBadge: View {
    let weather: AgendaWeatherDay

    var body: some View {
        HStack(spacing: 2) {
            weatherIcon

            temperatureText
        }
        .frame(width: AgendaLayout.weatherBadgeWidth, alignment: .trailing)
        .padding(.top, -1)
        .accessibilityLabel("\(weather.temperature) graden")
    }

    private var temperatureText: some View {
        ZStack(alignment: .topTrailing) {
            Text("\(weather.temperature)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 19, alignment: .center)

            Text("°")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .offset(x: 5, y: -1)
        }
        .frame(width: 24, height: 18, alignment: .center)
    }

    @ViewBuilder private var weatherIcon: some View {
        if weather.symbolName == "sun.max.fill" || weather.symbolName == "sun.min.fill" {
            Image(systemName: weather.symbolName)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.yellow)
                .frame(width: 15, height: 18)
        } else {
            Image(systemName: weather.symbolName)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 15, height: 18)
        }
    }
}

private struct AgendaMoveControls: View {
    @Binding var date: Date
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveToDate: () -> Void
    let moveToTodo: (String) -> Void
    let remove: () -> Void
    let todoGroups: [TodoGroup]
    let finishMove: () -> Void
    let highlightsControls: Bool
    let highlightsFinish: Bool

    var body: some View {
        HStack(spacing: AgendaLayout.rowSpacing) {
            Color.clear
                .frame(width: AgendaLayout.prefixWidth, height: 32)

            movementControls
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if highlightsControls {
                        GeometryReader { geometry in
                            let distributedSpacing = max(
                                AgendaLayout.moveActionSpacing,
                                (geometry.size.width - AgendaLayout.moveControlsFixedWidth) / 4
                            )

                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.brandHardBlue, lineWidth: 3)
                                .frame(
                                    width: geometry.size.width
                                        - distributedSpacing
                                        - AgendaLayout.finishControlWidth
                                        + AgendaLayout.onboardingControlsTrailingSpace
                                )
                                .padding(.leading, -5)
                                .padding(.vertical, -4)
                        }
                    }
                }
                .padding(.trailing, AgendaLayout.completionControlInset)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var movementControls: some View {
        HStack(spacing: 0) {
            Menu {
                Section("Verplaats naar:") {
                    ForEach(todoGroups) { group in
                        Button {
                            moveToTodo(group.id)
                        } label: {
                            Label {
                                Text(group.title)
                            } icon: {
                                Image(systemName: group.icon)
                                    .foregroundStyle(group.color)
                            }
                        }
                    }
                }

                Divider()

                Button(role: .destructive, action: remove) {
                    Label("Verwijderen", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .tint(.red)
            } label: {
                Color.clear
                    .frame(width: AgendaLayout.categoryControlWidth, height: 32)
                    .overlay {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .contentShape(Rectangle().inset(by: -4))
            .accessibilityLabel("Verplaatsopties")

            Spacer(minLength: AgendaLayout.moveActionSpacing)

            DatePicker("", selection: dateSelection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
                .opacity(0.02)
                .overlay {
                    Text(AppCalendar.localizedDate(date, template: "dMMMyyyy"))
                        .allowsHitTesting(false)
                }
                .frame(width: AgendaLayout.dateControlWidth, height: 32)
                .contentShape(Rectangle().inset(by: -4))
                .accessibilityValue(AppCalendar.localizedDate(date, template: "dMMMyyyy"))

            Spacer(minLength: AgendaLayout.moveActionSpacing)

            Button {
                performStep(moveUp)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: AgendaLayout.stepControlWidth, height: 32)
                    .contentShape(Rectangle().inset(by: -4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Een positie omhoog")

            Spacer(minLength: AgendaLayout.moveActionSpacing)

            Button {
                performStep(moveDown)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: AgendaLayout.stepControlWidth, height: 32)
                    .contentShape(Rectangle().inset(by: -4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Een positie omlaag")

            Spacer(minLength: AgendaLayout.moveActionSpacing)

            finishButton
        }
    }

    private var finishButton: some View {
        Button(action: finishMove) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(y: -2)
                .frame(width: AgendaLayout.finishControlWidth, height: 32)
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Klaar met verplaatsen")
        .overlay {
            if highlightsFinish {
                Circle()
                    .stroke(Color.brandHardBlue, lineWidth: 3)
                    .padding(-4)
            }
        }
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
    let date: Date
    var isMoveActive = false
    var isMoveTargetHighlighted = false
    var isOnboardingHighlighted = false

    var body: some View {
        HStack(spacing: AgendaLayout.dateWeekdaySpacing) {
            Text(dateLabel.isEmpty ? "     " : dateLabel)
                .foregroundStyle(
                    dateLabel.isEmpty
                        ? Color.clear
                        : (AppCalendar.isSameDay(date, .now) ? Color.brandHardBlue : Color.secondary)
                )
                .monospacedDigit()
                .frame(width: AgendaLayout.dateWidth, alignment: .leading)

            Text(weekdayLetter)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(
                    width: AgendaLayout.weekdayWidth,
                    height: 22,
                    alignment: AppCalendar.weekdayLabelLength == 1 ? .center : .leading
                )
                .background {
                    if isMoveActive {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.green.opacity(0.18))
                    } else if isMoveTargetHighlighted {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.yellow.opacity(0.28))
                    }
                }
                .overlay {
                    if isOnboardingHighlighted {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.brandHardBlue, lineWidth: 3)
                            .padding(-3)
                    }
                }
        }
        .font(.system(size: 15, weight: .medium))
        .frame(width: AgendaLayout.prefixWidth, alignment: .leading)
    }
}
