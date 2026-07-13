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
                    focusesKeyboardImmediately: quickCaptureDestinationID != nil
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
                removeExpiredHistory()
                presentRequestedQuickCapture()
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
            removeExpiredHistory()

            guard !hasPerformedLaunchSync else { return }
            hasPerformedLaunchSync = true
            guard calendarSyncEnabled else { return }

            do {
                try CalendarSyncService.syncAll(in: modelContext)
                try modelContext.save()
                calendarLastSyncDate = Date.now.timeIntervalSinceReferenceDate
            } catch {
                // A manual retry remains available in Settings.
            }
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

    private var reminderSignature: String {
        let entrySignature = entries.map {
            [
                $0.id.uuidString,
                String($0.date.timeIntervalSinceReferenceDate),
                $0.rawText,
                String($0.startMinutes ?? -1),
                String($0.manualOrder)
            ].joined(separator: "|")
        }.joined(separator: "\n")

        return [String(isEnabled), String(reminderMinutes), language, entrySignature]
            .joined(separator: "\n")
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

    private var snapshotSignature: String {
        let entrySignature = entries.map {
            [
                $0.id.uuidString,
                String($0.date.timeIntervalSinceReferenceDate),
                $0.rawText,
                String($0.startMinutes ?? -1),
                String($0.manualOrder),
                $0.accentRawValue
            ].joined(separator: "|")
        }.joined(separator: "\n")
        let todoSignature = todos.map {
            [
                $0.id.uuidString,
                $0.text,
                $0.bucketRawValue,
                String($0.createdAt.timeIntervalSinceReferenceDate)
            ].joined(separator: "|")
        }.joined(separator: "\n")
        return [
            categoriesData,
            todoGroupsData,
            language,
            dateFormat,
            lockScreenContent,
            lockScreenDatePrefix,
            String(lockScreenItemCount),
            lockScreenWordTruncation,
            homeWidgetContent,
            homeWidgetCalendarRange,
            homeWidgetDatePrefix,
            homeWidgetTextFlow,
            String(homeWidgetShowsTitle),
            homeWidgetBackground,
            String(homeWidgetShowsOtherWhenEmpty),
            homeWidgetTodoCategoryID,
            entrySignature,
            todoSignature
        ].joined(separator: "\n")
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
