import SwiftUI
import SwiftData
import UIKit

enum AppKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Tracks the software keyboard's end frame. Consumers read it on demand to
/// decide whether an input row is actually covered; nothing is published, so
/// keyboard animations never invalidate views through this type.
@MainActor
final class KeyboardObserver {
    static let shared = KeyboardObserver()

    private var latestFrame: CGRect?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            MainActor.assumeIsolated {
                KeyboardObserver.shared.latestFrame = frame
            }
        }
        center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                KeyboardObserver.shared.latestFrame = nil
            }
        }
    }

    /// Top of the software keyboard in screen coordinates. `nil` when the
    /// keyboard is hidden, offscreen, or only a hardware-keyboard accessory
    /// strip is visible — in those cases no automatic scrolling is needed.
    var topOfKeyboard: CGFloat? {
        guard let latestFrame else { return nil }
        let screenBounds = UIScreen.main.bounds
        guard latestFrame.height > 110 else { return nil }
        guard latestFrame.minY < screenBounds.maxY - 1 else { return nil }
        return latestFrame.minY
    }
}

/// Records the global frame of the focused inline input row. Agenda and Todo
/// use this to scroll only when the row is genuinely (about to be) covered by
/// the keyboard, instead of unconditionally pinning it above the keyboard and
/// making the whole screen jump while it was already visible.
@MainActor
final class FocusedInputFrameTracker {
    static let agenda = FocusedInputFrameTracker()
    static let todo = FocusedInputFrameTracker()

    private var owner: AnyHashable?
    private var latestFrame: CGRect?

    func update(owner: AnyHashable, frame: CGRect) {
        self.owner = owner
        latestFrame = frame
    }

    func clear(owner: AnyHashable) {
        guard self.owner == owner else { return }
        self.owner = nil
        latestFrame = nil
    }

    /// Whether an automatic scroll is required to keep this input row usable.
    /// `true` when the row's bottom falls below the keyboard (minus a small
    /// comfort margin), when it sits above the viewport, or when its position
    /// is unknown — the previous always-scroll behavior remains the fallback.
    func needsKeyboardScroll(
        for owner: AnyHashable,
        comfortMargin: CGFloat = 16
    ) -> Bool {
        guard self.owner == owner, let frame = latestFrame else { return true }
        let screenBounds = UIScreen.main.bounds
        let visibleBottom = min(
            KeyboardObserver.shared.topOfKeyboard ?? screenBounds.maxY,
            screenBounds.maxY
        ) - comfortMargin
        if frame.maxY > visibleBottom { return true }
        if frame.minY < screenBounds.minY { return true }
        return false
    }
}

struct RootTabView: View {
    private enum MainTab: Hashable {
        case agenda, recurring, todo, history
    }

    @Environment(\.modelContext)
    private var modelContext

    @AppStorage(SettingsKeys.language)
    private var language = AppLanguage.system.rawValue

    @AppStorage(SettingsKeys.defaultColorCombinationEnabled)
    private var defaultColorCombinationEnabled = true

    @AppStorage(SettingsKeys.recurringHolidayCountry)
    private var holidayCountryCode = ""

    @AppStorage(SettingsKeys.calendarSyncEnabled)
    private var calendarSyncEnabled = false

    @AppStorage(SettingsKeys.calendarLastSyncDate)
    private var calendarLastSyncDate = 0.0

    @AppStorage(SettingsKeys.historyRetention)
    private var historyRetention = HistoryRetentionOption.default.rawValue

    @State private var hasPerformedLaunchSync = false
    @State private var isShowingQuickTodoCapture = false
    @State private var quickCaptureDestinationID: String?
    @State private var shouldFocusQuickCaptureTextField = false
    @State private var selectedTab = MainTab.agenda
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKeys.isRecurringHelpExpanded)
    private var isRecurringHelpExpanded = false
    @AppStorage(SettingsKeys.recurringTutorialStep)
    private var recurringTutorialStep = 0
    @AppStorage(SettingsKeys.hasCompletedRecurringTutorial)
    private var hasCompletedRecurringTutorial = false

    @AppStorage(SettingsKeys.todoGroups)
    private var todoGroupsData = ""

    @AppStorage(SettingsKeys.actionButtonDefaultDestination)
    private var actionButtonDefaultDestination = ActionButtonDefaultDestination.topTodoCategory.rawValue

    init() {
        // Register the keyboard-frame observers before the first keyboard
        // appearance, so the very first visibility decision is correct.
        _ = KeyboardObserver.shared

        let badgeColor = UIColor(Color.brandHardBlue)
        let inactiveIconColor = UIColor.label.withAlphaComponent(0.72)
        UITabBarItem.appearance().badgeColor = badgeColor

        let tabBarAppearance = UITabBar.appearance().standardAppearance
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = inactiveIconColor
        tabBarAppearance.stackedLayoutAppearance.normal.badgeBackgroundColor = badgeColor
        tabBarAppearance.stackedLayoutAppearance.selected.badgeBackgroundColor = badgeColor
        tabBarAppearance.inlineLayoutAppearance.normal.iconColor = inactiveIconColor
        tabBarAppearance.inlineLayoutAppearance.normal.badgeBackgroundColor = badgeColor
        tabBarAppearance.inlineLayoutAppearance.selected.badgeBackgroundColor = badgeColor
        tabBarAppearance.compactInlineLayoutAppearance.normal.iconColor = inactiveIconColor
        tabBarAppearance.compactInlineLayoutAppearance.normal.badgeBackgroundColor = badgeColor
        tabBarAppearance.compactInlineLayoutAppearance.selected.badgeBackgroundColor = badgeColor
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    private var appLocale: Locale {
        AppLanguage.effective(
            from: language,
            holidayCountryCode: holidayCountryCode
        ).locale
    }

    private var appLayoutDirection: LayoutDirection {
        let languageCode = appLocale.language.languageCode?.identifier ?? "en"
        return Locale.Language(identifier: languageCode).characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    private var showsRecurringCalendarHint: Bool {
        isRecurringHelpExpanded
            && !hasCompletedRecurringTutorial
            && recurringTutorialStep == 3
            && selectedTab == .recurring
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AgendaView()
                .tag(MainTab.agenda)
                .tabItem {
                    Image(systemName: "calendar")
                        .accessibilityLabel(AppSection.agenda.title(for: appLocale))
                }
                .badge(showsRecurringCalendarHint ? Text("↓") : nil)

            TodoView()
                .tag(MainTab.todo)
                .tabItem {
                    Image(systemName: "checklist")
                        .accessibilityLabel(AppSection.todo.title(for: appLocale))
                }

            RecurringView()
                .tag(MainTab.recurring)
                .tabItem {
                    Image(systemName: "repeat")
                        .accessibilityLabel(AppSection.recurring.title(for: appLocale))
                }

            HistoryView()
                .tag(MainTab.history)
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityLabel(AppSection.history.title(for: appLocale))
                }
        }
        .adaptiveTabViewStyle()
        .neverMinimizeTabBarWhenSupported()
        .tint(.brandHardBlue)
        .background(Color.appCanvasBackground.ignoresSafeArea())
        .environment(\.locale, appLocale)
        .environment(\.layoutDirection, appLayoutDirection)
        .background {
            WidgetSnapshotPublisherView()
                .equatable()
            EndOfDayReminderPublisherView()
        }
        .overlay(alignment: .top) {
            if isShowingQuickTodoCapture {
                QuickTodoCaptureView(
                    groups: todoGroups,
                    initialDestinationID: quickCaptureDestinationID,
                    focusesKeyboardImmediately: shouldFocusQuickCaptureTextField
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isShowingQuickTodoCapture = false
                    }
                }
                .id(quickCaptureDestinationID)
                .frame(height: 250)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .adaptiveReadableWidth(maxWidth: AdaptiveLayout.quickCaptureMaxWidth)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .overlay(alignment: .topLeading) {
            if selectedTab != .agenda {
                AppActivityIndicator()
                    .safeAreaPadding(.top, 8)
                    .padding(.leading, 14)
            }
        }
        .onAppear(perform: presentRequestedQuickCapture)
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab == .recurring,
               newTab == .agenda,
               isRecurringHelpExpanded,
               !hasCompletedRecurringTutorial,
               recurringTutorialStep == 3 {
                recurringTutorialStep = 4
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scheduleExpiredHistoryCleanup()
                presentRequestedQuickCapture()
            } else if phase == .background || phase == .inactive {
                // Never leave a coalesced save window open while the app can
                // be suspended.
                PersistenceSafety.flushScheduledSave()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickTodoCaptureRequested)) { _ in
            presentRequestedQuickCapture()
        }
        .onOpenURL { url in
            switch url.host {
            case "calendar": selectedTab = .agenda
            case "todo": selectedTab = .todo
            case "quick-add": presentWidgetQuickCapture(from: url)
            default: break
            }
        }
        .task {
            // History cleanup can fetch the complete history and write an
            // automatic backup. Launching the first tab, its queries and the
            // keyboard always outranks that maintenance, so it runs deferred.
            scheduleExpiredHistoryCleanup()

            guard !hasPerformedLaunchSync else { return }
            hasPerformedLaunchSync = true
            guard calendarSyncEnabled else { return }

            // EventKit round-trips are XPC calls. Delay the launch sync so it
            // cannot collide with the first render or the user's first
            // interactions.
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            do {
                try CalendarSyncService.syncAll(in: modelContext)
                try modelContext.save()
                calendarLastSyncDate = Date.now.timeIntervalSinceReferenceDate
            } catch {
                // A manual retry remains available in Settings.
            }
        }
    }

    @State private var expiredHistoryCleanupTask: Task<Void, Never>?

    private func scheduleExpiredHistoryCleanup() {
        guard expiredHistoryCleanupTask == nil else { return }
        expiredHistoryCleanupTask = Task { @MainActor in
            // Keep the fetch/delete pass out of the foreground transition so
            // returning to the app never starts with a blocked main actor.
            try? await Task.sleep(for: .milliseconds(900))
            defer { expiredHistoryCleanupTask = nil }
            guard !Task.isCancelled else { return }
            removeExpiredHistory()
        }
    }

    private var todoGroups: [TodoGroup] {
        TodoGroupStore.decode(todoGroupsData)
    }

    private func removeExpiredHistory() {
        let retention = HistoryRetentionOption(rawValue: historyRetention) ?? .default
        do {
            try HistoryCleanupService.removeExpiredHistory(
                retention: retention,
                from: modelContext
            )
        } catch {
            PersistenceSafety.report(error)
        }
    }

    private func presentRequestedQuickCapture() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKeys.quickTodoCaptureRequested) else { return }
        defaults.set(false, forKey: SettingsKeys.quickTodoCaptureRequested)
        quickCaptureDestinationID = nil
        shouldFocusQuickCaptureTextField = true
        let destination = ActionButtonDefaultDestination(rawValue: actionButtonDefaultDestination)
            ?? .topTodoCategory
        selectedTab = destination == .calendarToday ? .agenda : .todo
        if !isShowingQuickTodoCapture {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                isShowingQuickTodoCapture = true
            }
        }
    }

    private func presentWidgetQuickCapture(from url: URL) {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let destination = queryItems.first(where: { $0.name == "destination" })?.value
        let requestedCategoryID = queryItems.first(where: { $0.name == "category" })?.value

        if destination == "calendar" {
            selectedTab = .agenda
            quickCaptureDestinationID = QuickTodoCaptureView.agendaDestinationID
        } else {
            selectedTab = .todo
            quickCaptureDestinationID = todoGroups.contains(where: { $0.id == requestedCategoryID })
                ? requestedCategoryID
                : todoGroups.first?.id
        }
        shouldFocusQuickCaptureTextField = true

        if !isShowingQuickTodoCapture {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                isShowingQuickTodoCapture = true
            }
        }
    }

}

private extension View {
    @ViewBuilder
    func adaptiveTabViewStyle() -> some View {
        if #available(iOS 18.0, *) {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }

    @ViewBuilder
    func neverMinimizeTabBarWhenSupported() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}

private struct EndOfDayReminderPublisherView: View {
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<DayEntry> { entry in
        !entry.isDone && !entry.isRemoved
    }) private var entries: [DayEntry]

    @AppStorage(SettingsKeys.endOfDayReminderEnabled)
    private var isEnabled = false

    @AppStorage(SettingsKeys.endOfDayReminderMinutes)
    private var reminderMinutes = EndOfDayReminderService.defaultMinutes

    @AppStorage(SettingsKeys.language)
    private var language = AppLanguage.system.rawValue

    @State private var pendingScheduleTask: Task<Void, Never>?

    /// A hash keeps this per-mutation signature allocation-free; the previous
    /// joined string grew linearly with the agenda and was rebuilt on the main
    /// actor for every observed change.
    private var reminderSignature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.date)
            hasher.combine(entry.rawText)
            hasher.combine(entry.startMinutes)
            hasher.combine(entry.manualOrder)
        }
        hasher.combine(isEnabled)
        hasher.combine(reminderMinutes)
        hasher.combine(language)
        return hasher.finalize()
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { queueReschedule(after: .zero) }
            .onChange(of: reminderSignature) { _, _ in
                queueReschedule(after: .milliseconds(500))
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active || phase == .background else { return }
                queueReschedule(after: .zero)
            }
            .onDisappear { pendingScheduleTask?.cancel() }
    }

    private func queueReschedule(after delay: Duration) {
        pendingScheduleTask?.cancel()
        let currentEntries = entries
        let currentMinutes = reminderMinutes
        let currentlyEnabled = isEnabled

        pendingScheduleTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            if currentlyEnabled {
                try? await EndOfDayReminderService.reschedule(
                    entries: currentEntries,
                    minutes: currentMinutes
                )
            } else {
                EndOfDayReminderService.cancelPendingReminders()
            }
            pendingScheduleTask = nil
        }
    }
}

private struct WidgetSnapshotPublisherView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    @Query(filter: #Predicate<DayEntry> { entry in
        !entry.isDone && !entry.isRemoved
    }) private var entries: [DayEntry]
    @Query(filter: #Predicate<TodoItem> { todo in
        !todo.isDone && !todo.isRemoved
    }) private var todos: [TodoItem]

    @AppStorage(SettingsKeys.recurringCategories) private var categoriesData = ""
    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""
    @AppStorage(SettingsKeys.language) private var language = AppLanguage.system.rawValue
    @AppStorage(SettingsKeys.dateFormat) private var dateFormat = DateFormatOption.system.rawValue
    @AppStorage(SettingsKeys.actionButtonContent)
    private var lockScreenContent = ActionButtonContentOption.today.rawValue
    @AppStorage(SettingsKeys.actionButtonDatePrefix)
    private var lockScreenDatePrefix = ActionButtonDatePrefixOption.date.rawValue
    @AppStorage(SettingsKeys.actionButtonItemCount) private var lockScreenItemCount = 3
    @AppStorage(SettingsKeys.lockScreenWordTruncation)
    private var lockScreenWordTruncation = LockScreenWordTruncationOption.ellipsis.rawValue
    @AppStorage(SettingsKeys.homeWidgetContent)
    private var homeWidgetContent = HomeWidgetContentOption.combined.rawValue
    @AppStorage(SettingsKeys.homeWidgetCalendarRange)
    private var homeWidgetCalendarRange = HomeWidgetCalendarRangeOption.today.rawValue
    @AppStorage(SettingsKeys.homeWidgetDatePrefix)
    private var homeWidgetDatePrefix = ActionButtonDatePrefixOption.date.rawValue
    @AppStorage(SettingsKeys.homeWidgetTextFlow)
    private var homeWidgetTextFlow = HomeWidgetTextFlowOption.truncate.rawValue
    @AppStorage(SettingsKeys.homeWidgetShowsTitle)
    private var homeWidgetShowsTitle = true
    @AppStorage(SettingsKeys.homeWidgetBackground)
    private var homeWidgetBackground = HomeWidgetBackgroundOption.brandLightBlue.rawValue
    @AppStorage(SettingsKeys.homeWidgetShowsOtherWhenEmpty)
    private var homeWidgetShowsOtherWhenEmpty = true
    @AppStorage(SettingsKeys.homeWidgetTodoCategoryID)
    private var homeWidgetTodoCategoryID = ""

    @State private var pendingPublishTask: Task<Void, Never>?

    /// Hash-based for the same reason as the reminder signature: this value is
    /// recomputed after every observed mutation and must stay cheap even with
    /// thousands of entries.
    private var snapshotSignature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.date)
            hasher.combine(entry.rawText)
            hasher.combine(entry.startMinutes)
            hasher.combine(entry.manualOrder)
            hasher.combine(entry.accentRawValue)
        }
        for todo in todos {
            hasher.combine(todo.id)
            hasher.combine(todo.text)
            hasher.combine(todo.bucketRawValue)
            hasher.combine(todo.createdAt)
        }
        hasher.combine(categoriesData)
        hasher.combine(todoGroupsData)
        hasher.combine(language)
        hasher.combine(dateFormat)
        hasher.combine(lockScreenContent)
        hasher.combine(lockScreenDatePrefix)
        hasher.combine(lockScreenItemCount)
        hasher.combine(lockScreenWordTruncation)
        hasher.combine(homeWidgetContent)
        hasher.combine(homeWidgetCalendarRange)
        hasher.combine(homeWidgetDatePrefix)
        hasher.combine(homeWidgetTextFlow)
        hasher.combine(homeWidgetShowsTitle)
        hasher.combine(homeWidgetBackground)
        hasher.combine(homeWidgetShowsOtherWhenEmpty)
        hasher.combine(homeWidgetTodoCategoryID)
        return hasher.finalize()
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                schedulePublish(after: .zero)
            }
            .onChange(of: snapshotSignature) { _, _ in
                schedulePublish(after: .milliseconds(500))
            }
            .onDisappear {
                pendingPublishTask?.cancel()
            }
    }

    private func schedulePublish(after delay: Duration) {
        pendingPublishTask?.cancel()

        let currentEntries = entries
        let currentTodos = todos
        let currentCategoriesData = categoriesData
        let currentTodoGroupsData = todoGroupsData
        let currentLockScreenContent = lockScreenContent
        let currentLockScreenDatePrefix = lockScreenDatePrefix
        let currentLockScreenItemCount = lockScreenItemCount
        let currentLockScreenWordTruncation = lockScreenWordTruncation
        let currentHomeWidgetContent = homeWidgetContent
        let currentHomeWidgetCalendarRange = homeWidgetCalendarRange
        let currentHomeWidgetDatePrefix = homeWidgetDatePrefix
        let currentHomeWidgetTextFlow = homeWidgetTextFlow
        let currentHomeWidgetShowsTitle = homeWidgetShowsTitle
        let currentHomeWidgetBackground = homeWidgetBackground
        let currentHomeWidgetShowsOtherWhenEmpty = homeWidgetShowsOtherWhenEmpty
        let currentHomeWidgetTodoCategoryID = homeWidgetTodoCategoryID

        pendingPublishTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            CalendarWidgetSnapshotPublisher.publish(
                entries: currentEntries,
                todos: currentTodos,
                categoriesData: currentCategoriesData,
                todoGroupsData: currentTodoGroupsData,
                lockScreenContent: currentLockScreenContent,
                lockScreenDatePrefix: currentLockScreenDatePrefix,
                lockScreenItemCount: currentLockScreenItemCount,
                lockScreenWordTruncation: currentLockScreenWordTruncation,
                homeWidgetContent: currentHomeWidgetContent,
                homeWidgetCalendarRange: currentHomeWidgetCalendarRange,
                homeWidgetDatePrefix: currentHomeWidgetDatePrefix,
                homeWidgetTextFlow: currentHomeWidgetTextFlow,
                homeWidgetShowsTitle: currentHomeWidgetShowsTitle,
                homeWidgetBackground: currentHomeWidgetBackground,
                homeWidgetShowsOtherWhenEmpty: currentHomeWidgetShowsOtherWhenEmpty,
                homeWidgetTodoCategoryID: currentHomeWidgetTodoCategoryID
            )
            pendingPublishTask = nil
        }
    }
}
