import SwiftData
import SwiftUI
import UIKit

private extension View {
    @ViewBuilder
    func recurringScrollCompatibility(isScrolled: Binding<Bool>) -> some View {
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
    func compatibleRecurringGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

private struct RecurringCategory: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var isFixed: Bool
    var colorRawValue: String
    var iconName: String? = nil

    var color: Color {
        RecurringThemeColorOption(rawValue: colorRawValue)?.color ?? .gray
    }

    var backgroundColor: Color {
        RecurringThemeColorOption(rawValue: colorRawValue)?.backgroundColor ?? Color.gray.opacity(0.18)
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RecurringCategoryIcons {
    static let all = [
        "repeat", "calendar", "calendar.badge.clock", "calendar.badge.checkmark",
        "birthday.cake.fill", "party.popper.fill", "gift.fill", "balloon.2.fill",
        "star.fill", "heart.fill", "person.fill", "figure.2",
        "house.fill", "building.2.fill", "briefcase.fill", "graduationcap.fill",
        "book.fill", "pencil", "checkmark.circle.fill", "bell.fill",
        "clock.fill", "timer", "hourglass", "sun.max.fill",
        "moon.stars.fill", "cloud.sun.fill", "leaf.fill", "tree.fill",
        "pawprint.fill", "car.fill", "airplane", "bicycle",
        "fork.knife", "cup.and.saucer.fill", "cart.fill", "creditcard.fill",
        "eurosign.circle.fill", "cross.case.fill", "pills.fill", "dumbbell.fill",
        "music.note", "camera.fill", "gamecontroller.fill", "wrench.and.screwdriver.fill"
    ]

    static func fallback(for categoryID: String) -> String {
        switch categoryID {
        case RecurringCategoryStore.birthdayID: "birthday.cake.fill"
        case RecurringCategoryStore.holidayID: "party.popper.fill"
        default: "repeat"
        }
    }
}

private enum RecurringCategoryStore {
    static let maxCount = 10
    static let birthdayID = RecurringTheme.birthday.rawValue
    static let generalID = RecurringTheme.general.rawValue
    static let holidayID = "holidays"

    static var defaults: [RecurringCategory] {
        defaults(for: AppCalendar.locale)
    }

    static func defaults(for locale: Locale) -> [RecurringCategory] {
        [
            RecurringCategory(
                id: birthdayID,
                title: String(localized: "category.recurring.birthdays", locale: locale),
                isFixed: true,
                colorRawValue: RecurringThemeColorOption.blue.rawValue,
                iconName: "birthday.cake.fill"
            ),
            RecurringCategory(
                id: generalID,
                title: String(localized: "category.recurring.general", locale: locale),
                isFixed: false,
                colorRawValue: RecurringThemeColorOption.yellow.rawValue,
                iconName: "repeat"
            ),
            RecurringCategory(
                id: holidayID,
                title: String(localized: "category.recurring.holidays", locale: locale),
                isFixed: true,
                colorRawValue: RecurringThemeColorOption.orange.rawValue,
                iconName: "party.popper.fill"
            )
        ]
    }

    static func decode(_ data: String) -> [RecurringCategory] {
        guard let encoded = data.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RecurringCategory].self, from: encoded) else {
            return defaults
        }

        return normalize(decoded)
    }

    static func encode(_ categories: [RecurringCategory]) -> String {
        let normalized = normalize(categories)
        guard let data = try? JSONEncoder().encode(normalized),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func normalize(_ categories: [RecurringCategory]) -> [RecurringCategory] {
        var result: [RecurringCategory] = []
        var seen: Set<String> = []

        for category in categories {
            let id = category.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id), result.count < maxCount else {
                continue
            }

            let fallback = defaults.first { $0.id == id }
            var normalized = category
            normalized.id = id
            normalized.isFixed = id == birthdayID || id == holidayID
            if id == birthdayID || id == holidayID {
                normalized.title = fallback?.title ?? normalized.trimmedTitle
            } else if normalized.trimmedTitle.isEmpty || isDefaultTitle(normalized.trimmedTitle, for: id) {
                normalized.title = fallback?.title ?? AppCalendar.locale.localized("Nieuw")
            } else {
                normalized.title = normalized.trimmedTitle
            }
            if RecurringThemeColorOption(rawValue: normalized.colorRawValue) == nil {
                normalized.colorRawValue = fallback?.colorRawValue ?? RecurringThemeColorOption.gray.rawValue
            }
            if let iconName = normalized.iconName,
               !RecurringCategoryIcons.all.contains(iconName) {
                normalized.iconName = nil
            }

            result.append(normalized)
            seen.insert(id)
        }

        if !seen.contains(birthdayID),
           let birthday = defaults.first(where: { $0.id == birthdayID }) {
            if result.count >= maxCount { result.removeLast() }
            result.insert(birthday, at: 0)
            seen.insert(birthdayID)
        }

        if !seen.contains(holidayID),
           let holiday = defaults.first(where: { $0.id == holidayID }) {
            if result.count >= maxCount { result.removeLast() }
            let insertionIndex = min(1, result.count)
            result.insert(holiday, at: insertionIndex)
            seen.insert(holidayID)
        }

        return result
    }

    private static func isDefaultTitle(_ title: String, for id: String) -> Bool {
        let knownTitles: [String: Set<String>] = [
            birthdayID: ["Verjaardagen", "Birthdays"],
            generalID: ["Algemeen", "General"],
            holidayID: ["Feestdagen", "Holidays"]
        ]
        return knownTitles[id]?.contains(title) == true
    }
}

private enum RecurringCompactRowStore {
    static func decode(_ data: String) -> Set<String> {
        guard !data.isEmpty,
              let encoded = data.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: encoded) else {
            return [RecurringCategoryStore.holidayID]
        }
        return Set(ids)
    }

    static func encode(_ ids: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

private struct RecurringNewItemRequest: Identifiable {
    let id = UUID()
    let categoryID: String?
}

private struct RecurringLeadingColumnWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 38

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<RecurringItem> { !$0.isRemoved })
    private var recurringItems: [RecurringItem]

    @AppStorage(SettingsKeys.recurringLastSyncSignature) private var lastSyncSignature = ""
    @AppStorage(SettingsKeys.recurringHorizon)
    private var recurringHorizon = RecurringHorizonOption.threeMonths.rawValue
    @AppStorage(SettingsKeys.recurringExtendedThrough)
    private var recurringExtendedThrough = 0.0
    @State private var isScrolled = false
    @State private var isKeyboardVisible = false
    @State private var newItemRequest: RecurringNewItemRequest?
    @State private var showingSettings = false
    @State private var showingHolidayManager = false
    @State private var editingItem: RecurringItem?
    @State private var syncTask: Task<Void, Never>?
    @State private var requiresImmediateSync = false
    @State private var recentlyRemovedItem: RecurringItem?
    @State private var dismissRemovalUndoTask: Task<Void, Never>?
    @State private var newCategoryTitle = ""
    @State private var leadingColumnWidth: CGFloat = 38

    @AppStorage(SettingsKeys.hasOpenedRecurringHelp)
    private var hasOpenedRecurringHelp = false
    @AppStorage(SettingsKeys.isRecurringHelpExpanded)
    private var isRecurringHelpExpanded = false
    @AppStorage(SettingsKeys.recurringTutorialStep)
    private var recurringTutorialStep = 0
    @AppStorage(SettingsKeys.hasCompletedRecurringTutorial)
    private var hasCompletedRecurringTutorial = false
    @AppStorage(SettingsKeys.recurringTutorialCategoryID)
    private var recurringTutorialCategoryID = ""

    @AppStorage(SettingsKeys.recurringBirthdayColor) private var birthdayColor = RecurringThemeColorOption.blue.rawValue
    @AppStorage(SettingsKeys.recurringGeneralColor) private var generalColor = RecurringThemeColorOption.yellow.rawValue
    @AppStorage(SettingsKeys.recurringPersonalColor) private var personalColor = RecurringThemeColorOption.green.rawValue
    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.recurringBirthdayCategoryDeleted) private var birthdayCategoryDeleted = false
    @AppStorage(SettingsKeys.recurringShowNextDate) private var showNextDate = true
    @AppStorage(SettingsKeys.recurringCompactCategoryIDs) private var compactCategoryIDsData = ""
    @AppStorage(SettingsKeys.recurringSoonestFirst) private var soonestFirst = true
    @AppStorage(SettingsKeys.recurringShowHolidays) private var showHolidays = true

    private var syncSignature: String {
        recurringItems.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [
                $0.id.uuidString, $0.title, $0.themeRawValue, $0.recurrenceKindRawValue,
                String($0.nextDate.timeIntervalSinceReferenceDate), String($0.intervalValue), $0.scheduleShiftsData,
                $0.intervalUnitRawValue, String($0.monthlyDay), String($0.monthlyOrdinal),
                String($0.monthlyWeekday), String($0.reminderDaysBefore ?? -1),
                String($0.birthDate?.timeIntervalSinceReferenceDate ?? -1),
                String($0.birthdayYearUncertain),
                String($0.annualMonth), $0.notes, $0.linksData
            ].joined(separator: "|")
        }.joined(separator: "\n")
    }

    private var effectiveSyncSignature: String {
        let today = AppCalendar.calendar.dateComponents(
            [.year, .month, .day],
            from: AppCalendar.startOfDay(.now)
        )
        return [
            syncSignature,
            recurringHorizon,
            String(format: "%04d-%02d-%02d", today.year ?? 0, today.month ?? 0, today.day ?? 0)
        ].joined(separator: "\n")
    }

    private var syncEndDate: Date {
        let option = RecurringHorizonOption(rawValue: recurringHorizon) ?? .threeMonths
        let base = AppCalendar.calendar.date(byAdding: .month, value: option.months, to: .now) ?? .now
        guard recurringExtendedThrough > 0 else { return base }
        return max(base, Date(timeIntervalSinceReferenceDate: recurringExtendedThrough))
    }

    private var categories: [RecurringCategory] {
        get {
            RecurringCategoryStore.decode(recurringCategoriesData).filter {
                !birthdayCategoryDeleted || $0.id != RecurringCategoryStore.birthdayID
            }
        }
        nonmutating set { recurringCategoriesData = RecurringCategoryStore.encode(newValue) }
    }

    private var compactCategoryIDs: Set<String> {
        RecurringCompactRowStore.decode(compactCategoryIDsData)
    }

    private var tutorialCategoryID: String? {
        if categories.contains(where: { $0.id == recurringTutorialCategoryID }) {
            return recurringTutorialCategoryID
        }
        return categories.first(where: { !$0.isFixed })?.id
            ?? categories.first(where: { $0.id != RecurringCategoryStore.holidayID })?.id
    }

    private var visibleTutorialStep: Int? {
        isRecurringHelpExpanded && !hasCompletedRecurringTutorial
            ? recurringTutorialStep
            : nil
    }

    var body: some View {
        let currentCategories = categories
        let visibleCategories = currentCategories.enumerated().filter {
            showHolidays || $0.element.id != RecurringCategoryStore.holidayID
        }
        let itemsByCategory = Dictionary(grouping: recurringItems, by: \.themeRawValue)

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isRecurringHelpExpanded {
                        RecurringHelpCard(
                            locale: locale,
                            step: recurringTutorialStep,
                            isCompleted: hasCompletedRecurringTutorial,
                            previous: showPreviousRecurringTutorialStep,
                            next: showNextRecurringTutorialStep,
                            replay: replayRecurringTutorial,
                            close: { isRecurringHelpExpanded = false }
                        )
                        .padding(.bottom, 4)
                    }

                    ForEach(visibleCategories, id: \.element.id) { index, category in
                        let items = sortedItems(itemsByCategory[category.id] ?? [])
                        RecurringThemeCard(
                            category: category,
                            items: items,
                            leadingColumnWidth: leadingColumnWidth,
                            showNextDate: showNextDate,
                            compactRows: compactCategoryIDs.contains(category.id),
                            canMoveUp: index > 0,
                            canMoveDown: index < currentCategories.count - 1,
                            canDeleteCategory: items.isEmpty && (
                                category.id == RecurringCategoryStore.birthdayID
                                    || !category.isFixed
                            ),
                            rename: { renameCategory(category.id, to: $0) },
                            changeColor: { changeCategoryColor(category.id, to: $0) },
                            changeIcon: { changeCategoryIcon(category.id, to: $0) },
                            delete: { deleteCategory(category.id) },
                            moveUp: { moveCategory(from: index, direction: -1) },
                            moveDown: { moveCategory(from: index, direction: 1) },
                            addItem: {
                                if category.id == RecurringCategoryStore.holidayID {
                                    showingHolidayManager = true
                                } else {
                                    showNewItem(in: category.id)
                                }
                            },
                            edit: { editingItem = $0 },
                            manageHolidays: category.id == RecurringCategoryStore.holidayID
                                ? { showingHolidayManager = true }
                                : nil,
                            highlightsAppearance: visibleTutorialStep == 1
                                && category.id == tutorialCategoryID,
                            highlightsAdd: visibleTutorialStep == 2
                                && category.id == tutorialCategoryID
                        )
                    }

                    if currentCategories.count < RecurringCategoryStore.maxCount {
                        NewRecurringCategoryLine(
                            text: $newCategoryTitle,
                            add: addCategory,
                            isOnboardingHighlighted: visibleTutorialStep == 0
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .adaptiveReadableWidth()
            }
            .onPreferenceChange(RecurringLeadingColumnWidthPreferenceKey.self) { width in
                leadingColumnWidth = max(38, width)
            }
            .background(Color.appCanvasBackground)
            .recurringScrollCompatibility(isScrolled: $isScrolled)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    RecurringTopTitle(
                        locale: locale,
                        isScrolled: isScrolled,
                        showsInfoHint: !hasOpenedRecurringHelp,
                        isHelpExpanded: isRecurringHelpExpanded,
                        toggleHelp: toggleRecurringHelp
                    )

                    HStack {
                        Button {
                            showingSettings = true
                            if visibleTutorialStep == 4 {
                                hasCompletedRecurringTutorial = true
                            }
                        } label: {
                            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.brandHardBlue)
                                .frame(width: 44, height: 44)
                        }
                        .compatibleRecurringGlassEffect()
                        .background(
                            visibleTutorialStep == 4 ? Color.brandLightBlue : Color.clear,
                            in: Circle()
                        )
                        .accessibilityLabel("Herhalingen beheren")
                        .overlay {
                            if visibleTutorialStep == 4 {
                                Circle()
                                    .stroke(Color.brandHardBlue, lineWidth: 3)
                                    .padding(-4)
                            }
                        }

                        Spacer()

                        Button {
                            newItemRequest = RecurringNewItemRequest(categoryID: nil)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.brandHardBlue)
                                .frame(width: 44, height: 44)
                        }
                        .compatibleRecurringGlassEffect()
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 18)
                .padding(.vertical, 6)
                .adaptiveReadableWidth()
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if let recentlyRemovedItem {
                    removalUndoBar(title: recentlyRemovedItem.title)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .adaptiveReadableWidth()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $newItemRequest) { request in
                RecurringEditorView(
                    item: nil,
                    categories: categories,
                    initialCategoryID: request.categoryID
                )
            }
            .sheet(isPresented: $showingSettings) {
                RecurringSettingsView()
            }
            .sheet(isPresented: $showingHolidayManager) {
                HolidayManagerView()
            }
            .sheet(item: $editingItem) { item in
                RecurringEditorView(
                    item: item,
                    categories: categories,
                    deleted: showRemovalUndo
                )
            }
            .onAppear {
                modelContext.undoManager = undoManager
                if effectiveSyncSignature != lastSyncSignature {
                    scheduleSync()
                }
            }
            .onChange(of: effectiveSyncSignature) { _, _ in
                scheduleSync(immediately: requiresImmediateSync)
            }
            .onChange(of: recurringItems.map(\.id)) { oldIDs, newIDs in
                guard visibleTutorialStep == 2,
                      let categoryID = tutorialCategoryID else { return }
                let addedIDs = Set(newIDs).subtracting(oldIDs)
                guard recurringItems.contains(where: {
                    addedIDs.contains($0.id) && $0.themeRawValue == categoryID
                }) else { return }
                completeRecurringTutorialAction(for: 2)
            }
            .onChange(of: recurringHorizon) { _, _ in
                recurringExtendedThrough = 0
            }
            .onChange(of: isKeyboardVisible) { _, visible in
                if visible && !requiresImmediateSync {
                    syncTask?.cancel()
                } else if !visible {
                    scheduleSync(immediately: requiresImmediateSync)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .recurringSyncRequested)) { _ in
                requiresImmediateSync = true
                AppActivityState.shared.begin(.recurringSync)
                scheduleSync(immediately: true)
            }
        }
    }

    private func sortedItems(for theme: RecurringTheme) -> [RecurringItem] {
        sortedItems(for: RecurringCategory(
            id: theme.rawValue,
            title: theme.title,
            isFixed: theme == .birthday,
            colorRawValue: colorRawValue(for: theme)
        ))
    }

    private func sortedItems(for category: RecurringCategory) -> [RecurringItem] {
        sortedItems(recurringItems.filter { $0.themeRawValue == category.id })
    }

    private func sortedItems(_ items: [RecurringItem]) -> [RecurringItem] {
        items
            .map { item in
                (item: item, nextDate: RecurrenceEngine.nextDate(for: item) ?? .distantFuture)
            }
            .sorted { lhs, rhs in
                if lhs.nextDate == rhs.nextDate {
                    return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
                }
                return soonestFirst ? lhs.nextDate < rhs.nextDate : lhs.nextDate > rhs.nextDate
            }
            .map(\.item)
    }

    private func color(for theme: RecurringTheme) -> Color {
        RecurringThemeColorOption(rawValue: colorRawValue(for: theme))?.color ?? .gray
    }

    private func colorRawValue(for theme: RecurringTheme) -> String {
        switch theme {
        case .birthday:
            birthdayColor
        case .general:
            generalColor
        case .personal:
            personalColor
        }
    }

    private func renameCategory(_ id: String, to title: String) {
        var updated = categories
        guard let index = updated.firstIndex(where: { $0.id == id }),
              !updated[index].isFixed else {
            return
        }

        updated[index].title = title
        categories = updated
    }

    private func changeCategoryColor(_ id: String, to colorRawValue: String) {
        var updated = categories
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].colorRawValue = colorRawValue
        categories = updated
        completeRecurringTutorialAction(for: 1)
    }

    private func changeCategoryIcon(_ id: String, to iconName: String) {
        var updated = categories
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].iconName = iconName
        categories = updated
        completeRecurringTutorialAction(for: 1)
    }

    private func addCategory() {
        let title = newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, categories.count < RecurringCategoryStore.maxCount else {
            return
        }

        var updated = categories
        updated.append(RecurringCategory(
            id: "custom-\(UUID().uuidString)",
            title: title,
            isFixed: false,
            colorRawValue: nextCategoryColorRawValue(for: updated.count),
            iconName: "repeat"
        ))
        categories = updated
        recurringTutorialCategoryID = updated.last?.id ?? ""
        newCategoryTitle = ""
        completeRecurringTutorialAction(for: 0)
    }

    private func toggleRecurringHelp() {
        hasOpenedRecurringHelp = true
        isRecurringHelpExpanded.toggle()
    }

    private func showPreviousRecurringTutorialStep() {
        if hasCompletedRecurringTutorial {
            hasCompletedRecurringTutorial = false
            recurringTutorialStep = RecurringHelpCard.stepCount - 1
            return
        }
        recurringTutorialStep = max(0, recurringTutorialStep - 1)
    }

    private func showNextRecurringTutorialStep() {
        if recurringTutorialStep == RecurringHelpCard.stepCount - 1 {
            hasCompletedRecurringTutorial = true
        } else {
            recurringTutorialStep += 1
        }
    }

    private func completeRecurringTutorialAction(for step: Int) {
        guard isRecurringHelpExpanded,
              !hasCompletedRecurringTutorial,
              recurringTutorialStep == step else { return }
        recurringTutorialStep = min(step + 1, RecurringHelpCard.stepCount - 1)
    }

    private func replayRecurringTutorial() {
        hasCompletedRecurringTutorial = false
        recurringTutorialStep = 0
        recurringTutorialCategoryID = ""
    }

    private func showNewItem(in categoryID: String) {
        newItemRequest = RecurringNewItemRequest(categoryID: categoryID)
    }

    private func deleteCategory(_ id: String) {
        var updated = categories
        guard let index = updated.firstIndex(where: { $0.id == id }),
              !recurringItems.contains(where: { $0.themeRawValue == id }) else {
            return
        }

        let isBirthday = id == RecurringCategoryStore.birthdayID
        guard isBirthday || !updated[index].isFixed else { return }

        updated.remove(at: index)
        categories = updated
        if isBirthday { birthdayCategoryDeleted = true }
        _ = PersistenceSafety.save(modelContext)
        scheduleSync()
    }

    private func moveCategory(from index: Int, direction: Int) {
        var updated = categories
        let newIndex = index + direction
        guard updated.indices.contains(index), updated.indices.contains(newIndex) else {
            return
        }

        updated.swapAt(index, newIndex)

        withAnimation(.easeOut(duration: 0.13)) {
            categories = updated
        }
    }

    private func nextCategoryColorRawValue(for index: Int) -> String {
        let palette = RecurringThemeColorOption.allCases
        return palette[index % palette.count].rawValue
    }

    private func scheduleSync(immediately: Bool = false) {
        syncTask?.cancel()
        guard immediately || !isKeyboardVisible else { return }
        syncTask = Task(priority: .background) { @MainActor in
            // Yield briefly so SwiftData can publish a just-saved item to the query.
            try? await Task.sleep(for: immediately ? .milliseconds(50) : .seconds(2))
            guard !Task.isCancelled,
                  (immediately || !isKeyboardVisible) else { return }
            guard effectiveSyncSignature != lastSyncSignature else {
                requiresImmediateSync = false
                AppActivityState.shared.finish(.recurringSync)
                return
            }
            let signatureBeingSynced = effectiveSyncSignature
            let plan = RecurringScheduler.fullSyncPlan(
                items: recurringItems,
                through: syncEndDate
            )
            let modelContainer = modelContext.container
            do {
                try await Task.detached(priority: .utility) {
                    try RecurringFullSyncWorker.sync(
                        plan: plan,
                        in: modelContainer
                    )
                }.value
                guard !Task.isCancelled,
                      effectiveSyncSignature == signatureBeingSynced else { return }
                lastSyncSignature = signatureBeingSynced
            } catch {
                // Keep the old signature so a later change/appearance retries.
            }
            requiresImmediateSync = false
            AppActivityState.shared.finish(.recurringSync)
        }
    }

    private func showRemovalUndo(_ item: RecurringItem) {
        dismissRemovalUndoTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) {
            recentlyRemovedItem = item
        }
        dismissRemovalUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyRemovedItem = nil
            }
        }
    }

    private func undoRemoval() {
        guard let item = recentlyRemovedItem else { return }
        item.isRemoved = false
        item.completedAt = nil
        _ = PersistenceSafety.save(modelContext)
        dismissRemovalUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyRemovedItem = nil
        }
        scheduleSync()
    }

    private func removalUndoBar(title: String) -> some View {
        UndoFeedbackBar(
            iconSystemName: "trash.fill",
            iconColor: .red,
            message: locale.localizedFormat("feedback.deleted", title),
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoRemoval
        )
    }
}

private struct RecurringTopTitle: View {
    let locale: Locale
    let isScrolled: Bool
    let showsInfoHint: Bool
    let isHelpExpanded: Bool
    let toggleHelp: () -> Void

    var body: some View {
        Button(action: toggleHelp) {
            HStack(spacing: 6) {
                Text(AppSection.recurring.title(for: locale))
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
        .opacity(isScrolled ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: isScrolled)
        .accessibilityLabel(locale.localized("Uitleg over herhalingen"))
        .accessibilityValue(isHelpExpanded
            ? locale.localized("Uitgeklapt")
            : locale.localized("Ingeklapt"))
        .accessibilityHint(locale.localized("Tik om de uitleg in of uit te klappen"))
    }
}

private struct RecurringHelpStep: Identifiable {
    let id: Int
    let icon: String
    let key: String

    func text(for locale: Locale) -> String {
        locale.localized(key)
    }
}

private struct RecurringHelpCard: View {
    static let stepCount = 5

    let locale: Locale
    let step: Int
    let isCompleted: Bool
    let previous: () -> Void
    let next: () -> Void
    let replay: () -> Void
    let close: () -> Void

    private let steps = [
        RecurringHelpStep(
            id: 0,
            icon: "rectangle.and.pencil.and.ellipsis",
            key: "Maak zelf een categorie. Tik op de tekst in het nieuwe blok en kies een naam.",
        ),
        RecurringHelpStep(
            id: 1,
            icon: "paintpalette",
            key: "Pas het icoon en de kleur van je categorie aan door op het logo te tikken.",
        ),
        RecurringHelpStep(
            id: 2,
            icon: "plus.circle",
            key: "Maak binnen je categorie een nieuwe herhaling door op het plusje te tikken.",
        ),
        RecurringHelpStep(
            id: 3,
            icon: "calendar",
            key: "Ga terug naar de kalender om je herhaling te vinden. Een herhaling wordt steeds opnieuw vooruit gepland.",
        ),
        RecurringHelpStep(
            id: 4,
            icon: "arrow.trianglehead.2.clockwise.rotate.90",
            key: "Tik linksboven op de pijlen om de instellingen voor herhalingen aan te passen.",
        ),
    ]

    private var currentStep: RecurringHelpStep {
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

                        Text(currentStep.text(for: locale))
                            .font(.system(size: 16, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    navigationControls
                        .id(step)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
        }
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

    private var completedContent: some View {
        TutorialCompletionContent(
            message: locale.localized("Je herhalingen regelen voortaan zichzelf."),
            replayTitle: locale.localized("Opnieuw"),
            backAccessibilityLabel: locale.localized("Vorige stap"),
            closeAccessibilityLabel: locale.localized("Sluiten"),
            back: previous,
            replay: replay,
            close: close
        )
    }
}

private struct RecurringThemeCard: View {
    let category: RecurringCategory
    let items: [RecurringItem]
    let leadingColumnWidth: CGFloat
    let showNextDate: Bool
    let compactRows: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDeleteCategory: Bool
    let rename: (String) -> Void
    let changeColor: (String) -> Void
    let changeIcon: (String) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let addItem: () -> Void
    let edit: (RecurringItem) -> Void
    let manageHolidays: (() -> Void)?
    let highlightsAppearance: Bool
    let highlightsAdd: Bool
    @State private var showingAppearancePicker = false
    @State private var showingCategoryActions = false

    private var color: Color {
        category.color
    }

    private var categoryIcon: String {
        category.iconName ?? RecurringCategoryIcons.fallback(for: category.id)
    }

    private var canDelete: Bool {
        canDeleteCategory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    showingAppearancePicker = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(category.backgroundColor)
                        Image(systemName: categoryIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .frame(width: leadingColumnWidth)
                .accessibilityLabel("Kleur en icoon van \(category.title) aanpassen")
                .overlay {
                    if highlightsAppearance {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Color.brandHardBlue, lineWidth: 3)
                            .padding(-4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if category.isFixed {
                            Text(category.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            DeferredCommitTextField(
                                "Categorie",
                                value: category.title,
                                commit: rename
                            )
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(categorySubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 36, alignment: .center)
                .offset(y: -2)
                .layoutPriority(1)

                Spacer(minLength: 4)

                actionToolbar
            }
            .padding(.leading, 11)
            .padding(.trailing, 8)
            .padding(.vertical, 14)

            Divider()
                .overlay(Color.primary.opacity(0.07))
                .padding(.leading, 11 + leadingColumnWidth + 12)

            if items.isEmpty {
                Button(action: addItem) {
                    HStack(spacing: 12) {
                        Image(systemName: category.id == RecurringCategoryStore.holidayID
                            ? "calendar.badge.plus"
                            : "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: leadingColumnWidth)
                        Text(category.id == RecurringCategoryStore.holidayID
                            ? "Feestdagen kiezen"
                            : category.id == RecurringCategoryStore.birthdayID
                                ? "Eerste verjaardag toevoegen"
                                : "Eerste herhaling toevoegen")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 36)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 11)
                .padding(.trailing, 8)
                .padding(.vertical, compactRows ? 10 : 12)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 2) {
                        Button {
                            if HolidayCatalog.managedHoliday(from: item.notes) != nil,
                               let manageHolidays {
                                manageHolidays()
                            } else {
                                edit(item)
                            }
                        } label: {
                            RecurringRow(
                                item: item,
                                color: color,
                                backgroundColor: category.backgroundColor,
                                leadingColumnWidth: leadingColumnWidth,
                                showNextDate: showNextDate,
                                compactRows: compactRows
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        if category.id != RecurringCategoryStore.holidayID {
                            if let firstLink = RecurringLinkDraft.decode(item.linksData).first,
                               let destination = firstLink.destination {
                                Link(destination: destination) {
                                    Image(systemName: "link")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(color)
                                        .frame(width: 36, height: 36)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(firstLink.name.isEmpty ? "Link 1" : firstLink.name)
                            } else {
                                Button {
                                    edit(item)
                                } label: {
                                    Image(systemName: "chevron.forward")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(color)
                                        .frame(width: 36, height: 36)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(item.title) bewerken")
                            }
                        }
                    }
                    .padding(.leading, 11)
                    .padding(.trailing, 8)
                    .padding(.vertical, compactRows ? 7 : 8)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(Color.primary.opacity(0.06))
                            .padding(.leading, 11 + leadingColumnWidth + 12)
                    }
                }
            }
        }
        .padding(.bottom, compactRows ? 3 : 0)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    Color.appThemeColor(
                        lightBlue: Color.appCardOutline,
                        gray: Color.primary.opacity(0.045)
                    ),
                    lineWidth: 1
                )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 28).onEnded { value in
                guard let manageHolidays,
                      value.translation.width < -100,
                      abs(value.translation.height) < 65 else { return }
                manageHolidays()
            }
        )
        .contextMenu {
            if let manageHolidays {
                Button("Feestdagen kiezen", systemImage: "calendar.badge.plus") {
                    manageHolidays()
                }
            }
        }
        .sheet(isPresented: $showingAppearancePicker) {
            CategoryAppearancePicker(
                categoryTitle: category.title,
                selectedColorRawValue: category.colorRawValue,
                selectedIconName: categoryIcon,
                changeColor: changeColor,
                changeIcon: changeIcon
            )
        }
    }

    private var actionToolbar: some View {
        HStack(spacing: 6) {
            Button {
                showingCategoryActions = true
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
            .accessibilityLabel("Volgorde van \(category.title) aanpassen")
            .popover(
                isPresented: $showingCategoryActions,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                categoryActionsPopover
                    .presentationCompactAdaptation(.popover)
            }

            Button(action: addItem) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
            .accessibilityLabel("Herhaling toevoegen aan \(category.title)")
            .overlay {
                if highlightsAdd {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.brandHardBlue, lineWidth: 3)
                        .padding(-3)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var categorySubtitle: String {
        if category.id == RecurringCategoryStore.birthdayID {
            let countText = items.count == 1 ? "1 verjaardag" : "\(items.count) verjaardagen"
            let reminderCount = items.filter { $0.reminderDaysBefore != nil }.count
            guard reminderCount > 0 else { return countText }
            let reminderText = reminderCount == 1 ? "1 reminder" : "\(reminderCount) reminders"
            return "\(countText) · \(reminderText)"
        }

        if category.id == RecurringCategoryStore.holidayID {
            let countText = items.count == 1 ? "1 feestdag" : "\(items.count) feestdagen"
            let customCount = items.filter {
                HolidayCatalog.managedHoliday(from: $0.notes) == nil
            }.count
            guard customCount > 0 else { return countText }
            let customText = customCount == 1 ? "1 zelf toegevoegd" : "\(customCount) zelf toegevoegd"
            return "\(countText) · \(customText)"
        }

        return items.count == 1 ? "1 herhaling" : "\(items.count) herhalingen"
    }

    private var categoryActionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryActionButton("Omhoog verplaatsen", systemImage: "arrow.up", enabled: canMoveUp, action: moveUp)
            categoryActionButton("Omlaag verplaatsen", systemImage: "arrow.down", enabled: canMoveDown, action: moveDown)

            if canDelete {
                Divider()
                Button(role: .destructive) {
                    performCategoryAction(delete)
                } label: {
                    Label("Categorie verwijderen", systemImage: "trash")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .padding(.trailing, 14)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .tint(.red)
            }
        }
        .frame(width: 230)
        .padding(.vertical, 5)
    }

    private func categoryActionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            performCategoryAction(action)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
                .padding(.trailing, 14)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func performCategoryAction(_ action: () -> Void) {
        showingCategoryActions = false
        action()
    }
}

private struct CategoryAppearancePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let categoryTitle: String
    let changeColor: (String) -> Void
    let changeIcon: (String) -> Void
    @State private var selectedColorRawValue: String
    @State private var selectedIconName: String

    init(
        categoryTitle: String,
        selectedColorRawValue: String,
        selectedIconName: String,
        changeColor: @escaping (String) -> Void,
        changeIcon: @escaping (String) -> Void
    ) {
        self.categoryTitle = categoryTitle
        self.changeColor = changeColor
        self.changeIcon = changeIcon
        _selectedColorRawValue = State(initialValue: selectedColorRawValue)
        _selectedIconName = State(initialValue: selectedIconName)
    }

    private var selectedColor: Color {
        RecurringThemeColorOption(rawValue: selectedColorRawValue)?.color ?? .gray
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kleur")
                            .font(.headline)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                            ForEach(RecurringThemeColorOption.allCases) { option in
                                Button {
                                    selectedColorRawValue = option.rawValue
                                    changeColor(option.rawValue)
                                } label: {
                                    VStack(spacing: 7) {
                                        ZStack {
                                            Circle()
                                                .fill(option.color)
                                                .frame(width: 38, height: 38)
                                            if selectedColorRawValue == option.rawValue {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        Text(option.title(for: locale))
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Icoon")
                            .font(.headline)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(RecurringCategoryIcons.all, id: \.self) { iconName in
                                Button {
                                    selectedIconName = iconName
                                    changeIcon(iconName)
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedIconName == iconName
                                                ? selectedColor.opacity(0.2)
                                                : Color(.tertiarySystemFill))
                                        Image(systemName: iconName)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(selectedIconName == iconName ? selectedColor : .secondary)
                                    }
                                    .frame(height: 48)
                                    .overlay {
                                        if selectedIconName == iconName {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(selectedColor, lineWidth: 2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(iconName)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(categoryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { dismiss() }
                }
            }
        }
    }
}

private struct RecurringRow: View {
    let item: RecurringItem
    let color: Color
    let backgroundColor: Color
    let leadingColumnWidth: CGFloat
    let showNextDate: Bool
    let compactRows: Bool

    private var nextDate: Date? { RecurrenceEngine.nextDate(for: item) }

    private var birthdayTimingText: String? {
        guard item.recurrenceKind == .birthday,
              let nextDate else {
            return nil
        }
        let days = max(0, AppCalendar.calendar.dateComponents(
            [.day],
            from: AppCalendar.startOfDay(.now),
            to: AppCalendar.startOfDay(nextDate)
        ).day ?? 0)
        if days == 0 {
            if item.birthdayYearUncertain {
                return AppCalendar.locale.localized("birthday.status.today")
            }
            guard let age = RecurrenceEngine.ageTurning(for: item, on: nextDate) else {
                return AppCalendar.locale.localized("birthday.status.today")
            }
            return AppCalendar.locale.localizedFormat("birthday.status.turnedToday", age)
        }
        if item.birthdayYearUncertain {
            return birthdayInDaysText(days)
        }
        guard let age = RecurrenceEngine.ageTurning(for: item, on: nextDate) else { return nil }
        return turnsInDaysText(age: age, days: days)
    }

    private func birthdayInDaysText(_ days: Int) -> String {
        AppCalendar.locale.localizedFormat(
            days == 1 ? "birthday.status.birthdayInOneDay" : "birthday.status.birthdayInDays",
            days
        )
    }

    private func turnsInDaysText(age: Int, days: Int) -> String {
        AppCalendar.locale.localizedFormat(
            days == 1 ? "birthday.status.turnsInOneDay" : "birthday.status.turnsInDays",
            age,
            days
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if showNextDate {
                    if let nextDate {
                        Text(AppCalendar.localizedDate(nextDate, template: "dMMM"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(backgroundColor, in: Capsule())
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: RecurringLeadingColumnWidthPreferenceKey.self,
                                        value: geometry.size.width
                                    )
                                }
                            }
                    } else {
                        Color.clear
                    }
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: leadingColumnWidth, height: 18, alignment: .center)

            VStack(alignment: .leading, spacing: compactRows ? 2 : 3) {
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !compactRows {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            detailText
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            detailText
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var detailText: some View {
        Group {
            if item.recurrenceKind == .birthday {
                if let birthdayTimingText {
                    Text(birthdayTimingText)
                }
                if let days = item.reminderDaysBefore {
                    Text("· reminder \(days)")
                        .foregroundStyle(color.opacity(0.65))
                }
            } else {
                Text(RecurrenceEngine.description(for: item))
            }
        }
    }
}

private struct NewRecurringCategoryLine: View {
    @Binding var text: String
    let add: () -> Void
    let isOnboardingHighlighted: Bool
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                beginEditing()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nieuwe categorie invoeren")

            TextField("Nieuwe categorie", text: $text, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1...)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    finishEditing()
                }
                .onSubmit {
                    finishEditing()
                }

            Button(action: finishEditing) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .padding(.vertical, 13)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isOnboardingHighlighted
                        ? Color.brandHardBlue
                        : Color.appThemeColor(
                            lightBlue: Color.appCardOutline,
                            gray: Color.primary.opacity(0.045)
                        ),
                    lineWidth: isOnboardingHighlighted ? 3 : 1
                )
        }
    }

    private func finishEditing() {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add()
        }
        isTextFieldFocused = false
    }

    private func beginEditing() {
        Task { @MainActor in
            await Task.yield()
            isTextFieldFocused = true
        }
    }
}

private struct RecurringSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.recurringBirthdayCategoryDeleted) private var birthdayCategoryDeleted = false
    @AppStorage(SettingsKeys.recurringShowNextDate) private var showNextDate = true
    @AppStorage(SettingsKeys.recurringCompactCategoryIDs) private var compactCategoryIDsData = ""
    @AppStorage(SettingsKeys.recurringSoonestFirst) private var soonestFirst = true
    @AppStorage(SettingsKeys.recurringShowHolidays) private var showHolidays = true
    @AppStorage(SettingsKeys.recurringHolidayCountry) private var holidayCountryCode = ""
    @AppStorage(SettingsKeys.defaultColorCombinationEnabled) private var defaultColorCombinationEnabled = true
    @State private var showingHolidayManager = false

    private var categories: [RecurringCategory] {
        get {
            RecurringCategoryStore.decode(recurringCategoriesData).filter {
                !birthdayCategoryDeleted || $0.id != RecurringCategoryStore.birthdayID
            }
        }
        nonmutating set { recurringCategoriesData = RecurringCategoryStore.encode(newValue) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Overzicht") {
                    Button {
                        showingHolidayManager = true
                    } label: {
                        HStack {
                            Text("Feestdagen")
                            Spacer()
                            Text(selectedHolidayCountry.title(for: locale))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Toggle("Toon volgende datum", isOn: $showNextDate)
                    Toggle("Sorteer eerstvolgende bovenaan", isOn: $soonestFirst)
                    Toggle("Toon feestdagen in overzicht", isOn: $showHolidays)
                }

                Section {
                    ForEach(categories) { category in
                        RecurringCategorySettingsRow(
                            title: category.title,
                            colorSelection: colorBinding(for: category.id),
                            compactRows: compactBinding(for: category.id)
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    Text("Compacte rijen")
                } footer: {
                    Text("Tik op de gekleurde stip om de kleur te wijzigen. Compacte categorieën tonen alleen de titel en eerstvolgende datum.")
                }
            }
            .appFormBackground(lightBlueEnabled: defaultColorCombinationEnabled)
            .navigationTitle("Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { dismiss() }
                }
            }
            .sheet(isPresented: $showingHolidayManager) {
                HolidayManagerView()
            }
        }
    }

    private var selectedHolidayCountry: HolidayCountry {
        HolidayCountry(rawValue: holidayCountryCode) ?? .localeDefault
    }

    private func compactBinding(for categoryID: String) -> Binding<Bool> {
        Binding(
            get: { RecurringCompactRowStore.decode(compactCategoryIDsData).contains(categoryID) },
            set: { isCompact in
                var ids = RecurringCompactRowStore.decode(compactCategoryIDsData)
                if isCompact { ids.insert(categoryID) }
                else { ids.remove(categoryID) }
                compactCategoryIDsData = RecurringCompactRowStore.encode(ids)
            }
        )
    }

    private func colorBinding(for id: String) -> Binding<String> {
        Binding(
            get: {
                categories.first { $0.id == id }?.colorRawValue
                    ?? RecurringThemeColorOption.gray.rawValue
            },
            set: { newValue in
                var updated = categories
                guard let index = updated.firstIndex(where: { $0.id == id }) else {
                    return
                }

                updated[index].colorRawValue = newValue
                categories = updated
            }
        )
    }
}

private struct RecurringCategorySettingsRow: View {
    @Environment(\.locale) private var locale
    let title: String
    @Binding var colorSelection: String
    @Binding var compactRows: Bool

    private var selectedColor: Color {
        RecurringThemeColorOption(rawValue: colorSelection)?.color ?? .gray
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Kleur", selection: $colorSelection) {
                    ForEach(RecurringThemeColorOption.allCases) { option in
                        Label {
                            Text(option.title(for: locale))
                        } icon: {
                            Circle()
                                .fill(option.color)
                        }
                        .tag(option.rawValue)
                    }
                }
            } label: {
                Circle()
                    .fill(selectedColor)
                    .frame(width: 13, height: 13)
                    .frame(width: 28, height: 30)
            }
            .tint(.primary)
            .buttonStyle(.plain)
            .accessibilityLabel("Kleur voor \(title)")

            Text(title)

            Spacer()

            Toggle("", isOn: $compactRows)
                .labelsHidden()
                .accessibilityLabel("Compacte rij voor \(title)")
        }
    }
}

private struct HolidayManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<RecurringItem> { !$0.isRemoved })
    private var recurringItems: [RecurringItem]

    @AppStorage(SettingsKeys.recurringHolidayCountry) private var storedCountryCode = ""
    @AppStorage(SettingsKeys.recurringCategories) private var recurringCategoriesData = ""
    @AppStorage(SettingsKeys.recurringBirthdayCategoryDeleted) private var birthdayCategoryDeleted = false
    @AppStorage(SettingsKeys.recurringOnlyLocalHolidays) private var onlyLocalHolidays = true
    @State private var country = HolidayCountry.localeDefault
    @State private var selectedHolidayIDs: Set<String> = []
    @State private var pendingCountry: HolidayCountry?
    @State private var showingCountryWarning = false
    @State private var showingCustomHoliday = false

    private var options: [HolidayOption] {
        HolidayCatalog.options(for: country, onlyLocal: onlyLocalHolidays)
    }

    private var categories: [RecurringCategory] {
        RecurringCategoryStore.decode(recurringCategoriesData).filter {
            !birthdayCategoryDeleted || $0.id != RecurringCategoryStore.birthdayID
        }
    }

    private var managedItems: [RecurringItem] {
        recurringItems.filter { HolidayCatalog.managedHoliday(from: $0.notes) != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Standaardland", selection: countryBinding) {
                        ForEach(HolidayCountry.allCases) { option in
                            Text(option.title(for: locale)).tag(option)
                        }
                    }
                    .tint(.primary)
                    Toggle("Laat alleen lokale feestdagen zien", isOn: $onlyLocalHolidays)
                        .tint(.brandHardBlue)
                } footer: {
                    Text("Je land is automatisch gekozen op basis van je regio. Zet de schakelaar uit om ook feestdagen en vieringen uit andere landen te zien.")
                }

                Section {
                    Button(visibleSelectionCount == options.count ? "Deselecteer alles" : "Selecteer alles") {
                        let visibleIDs = Set(options.map(\.id))
                        if visibleSelectionCount == options.count {
                            selectedHolidayIDs.subtract(visibleIDs)
                        } else {
                            selectedHolidayIDs.formUnion(visibleIDs)
                        }
                    }

                    ForEach(options) { option in
                        Toggle(isOn: selectionBinding(for: option.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(onlyLocalHolidays
                                    ? option.definition.title
                                    : "\(option.definition.title) (\(option.country.title(for: locale)))")
                                Text(option.definition.recurrenceDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.brandHardBlue)
                    }
                } header: {
                    Text("Selectie")
                } footer: {
                    Text("Een landwissel vervangt deze selectie. Eigen feestdagen blijven bewaard. Data uit de islamitische kalender kunnen door lokale maanwaarneming één dag verschillen.")
                }

                Section {
                    Button("Eigen feestdag toevoegen", systemImage: "plus") {
                        showingCustomHoliday = true
                    }
                } footer: {
                    Text("Eigen feestdagen kun je ook toevoegen met de plusknop bij de oranje categorie.")
                }
            }
            .navigationTitle("Feestdagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { applySelection() }
                }
            }
            .onAppear(perform: loadSelection)
            .alert(locale.localized("Huidige selectie overschrijven?"), isPresented: $showingCountryWarning) {
                Button(locale.localized("Annuleer"), role: .cancel) {
                    pendingCountry = nil
                }
                Button(locale.localized("Overschrijf"), role: .destructive) {
                    confirmCountryChange()
                }
            } message: {
                Text(locale.localized("De standaardselectie van het nieuwe land vervangt je huidige geselecteerde feestdagen. Eigen feestdagen worden niet verwijderd."))
            }
            .sheet(isPresented: $showingCustomHoliday) {
                RecurringEditorView(
                    item: nil,
                    categories: categories,
                    initialCategoryID: RecurringCategoryStore.holidayID
                )
            }
        }
    }

    private var countryBinding: Binding<HolidayCountry> {
        Binding(
            get: { country },
            set: { newCountry in
                guard newCountry != country else { return }
                pendingCountry = newCountry
                showingCountryWarning = true
            }
        )
    }

    private var visibleSelectionCount: Int {
        selectedHolidayIDs.intersection(Set(options.map(\.id))).count
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedHolidayIDs.contains(id) },
            set: { isSelected in
                if isSelected { selectedHolidayIDs.insert(id) }
                else { selectedHolidayIDs.remove(id) }
            }
        )
    }

    private func loadSelection() {
        country = HolidayCountry(rawValue: storedCountryCode) ?? .localeDefault

        let selected = managedItems.compactMap { item -> String? in
            guard let managed = HolidayCatalog.managedHoliday(from: item.notes) else { return nil }
            return "\(managed.country.rawValue):\(managed.definition.id)"
        }
        selectedHolidayIDs = selected.isEmpty
            ? HolidayCatalog.defaultSelectionIDs(for: country, onlyLocal: onlyLocalHolidays)
            : Set(selected)
    }

    private func confirmCountryChange() {
        guard let pendingCountry else { return }
        country = pendingCountry
        selectedHolidayIDs = HolidayCatalog.defaultSelectionIDs(
            for: pendingCountry,
            onlyLocal: onlyLocalHolidays
        )
        self.pendingCountry = nil
    }

    private func applySelection() {
        for item in managedItems {
            modelContext.delete(item)
        }

        for option in options where selectedHolidayIDs.contains(option.id) {
            let definition = option.definition
            let item = RecurringItem(
                title: definition.title,
                nextDate: HolidayCatalog.nextDate(for: definition),
                theme: .general,
                recurrenceKind: .annualFixed,
                notes: HolidayCatalog.marker(country: option.country, holidayID: definition.id)
            )
            item.themeRawValue = RecurringCategoryStore.holidayID
            item.frequencyText = definition.recurrenceDescription
            modelContext.insert(item)
        }

        storedCountryCode = country.rawValue
        _ = PersistenceSafety.save(modelContext)
        dismiss()
    }
}

private final class EndAlignedNumberTextField: UITextField {
    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        endOfDocument
    }
}

private struct CompactNumberField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isDisabled = false
    var accessibilityLabel: String
    var textAlignment: NSTextAlignment = .right
    var textChanged: () -> Void = {}
    var editingChanged: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextField {
        let textField = EndAlignedNumberTextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.borderStyle = .none
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = placeholder
        textField.text = text
        textField.textAlignment = textAlignment
        textField.accessibilityLabel = accessibilityLabel
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder
        textField.textAlignment = textAlignment
        textField.textColor = isDisabled ? .secondaryLabel : .label
        textField.isEnabled = true
        textField.accessibilityLabel = accessibilityLabel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CompactNumberField

        init(parent: CompactNumberField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.textChanged()
            parent.text = textField.text ?? ""
            textField.textAlignment = parent.textAlignment
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.editingChanged(true)
            textField.textAlignment = parent.textAlignment
            let targetPosition = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: targetPosition, to: targetPosition)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.editingChanged(false)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            string.allSatisfy(\.isNumber)
        }
    }
}

private struct RecurringEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    let item: RecurringItem?
    let categories: [RecurringCategory]
    let deleted: (RecurringItem) -> Void
    @State private var draft: RecurringDraft
    @State private var editingLinkNameIndex: Int?
    @State private var datePickerResetID = UUID()
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case title
        case notes
        case reminderDays
        case birthdayYear
        case currentAge
        case link(Int)
        case linkName(Int)
    }

    init(
        item: RecurringItem?,
        categories: [RecurringCategory],
        initialCategoryID: String? = nil,
        deleted: @escaping (RecurringItem) -> Void = { _ in }
    ) {
        self.item = item
        self.categories = RecurringCategoryStore.normalize(categories)
        self.deleted = deleted
        _draft = State(initialValue: RecurringDraft(
            item: item,
            initialCategoryID: initialCategoryID
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                editorSections
            }
            .font(.body)
            // Keep the rows at their final iOS form height from the first layout
            // pass, so controls resolving their intrinsic size do not cause a
            // small vertical jump while the sheet is appearing.
            .environment(\.defaultMinListRowHeight, 44)
            .navigationTitle(item == nil
                ? locale.localized("Nieuwe herhaling")
                : locale.localized("Wijzig herhaling"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { save() }.disabled(!draft.canSave)
                }
            }
            .onAppear {
                if !categories.contains(where: { $0.id == draft.categoryID }) {
                    draft.categoryID = categories.first { !$0.isFixed }?.id
                        ?? RecurringCategoryStore.generalID
                }
                if draft.categoryID == RecurringCategoryStore.birthdayID {
                    draft.kind = .birthday
                } else if draft.categoryID == RecurringCategoryStore.holidayID,
                          draft.kind != .annualFixed,
                          draft.kind != .annualOrdinalWeekday {
                    draft.kind = .annualFixed
                } else if draft.kind == .birthday {
                    // Older versions used the birthday kind for the generic yearly option.
                    draft.kind = .yearly
                }
                if item == nil {
                    Task { @MainActor in
                        // Wait until the presented sheet has installed its text
                        // field, then make it first responder. Its height is fixed
                        // below, so this no longer changes the Form row layout.
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        focusedField = .title
                    }
                }
            }
            .onChange(of: draft.categoryID) { _, categoryID in
                if categoryID == RecurringCategoryStore.birthdayID {
                    draft.kind = .birthday
                } else if categoryID == RecurringCategoryStore.holidayID {
                    if draft.kind != .annualFixed,
                       draft.kind != .annualOrdinalWeekday {
                        draft.kind = .annualFixed
                    }
                } else if draft.kind == .birthday {
                    draft.kind = .yearly
                } else if draft.kind == .annualFixed || draft.kind == .annualOrdinalWeekday {
                    draft.kind = .interval
                }
            }
            .onChange(of: draft.kind) { _, kind in
                if kind == .birthday {
                    draft.categoryID = RecurringCategoryStore.birthdayID
                } else if draft.categoryID == RecurringCategoryStore.birthdayID {
                    draft.categoryID = categories.first { !$0.isFixed }?.id
                        ?? RecurringCategoryStore.generalID
                }
            }
            .onChange(of: draft.birthdayMonth) { _, _ in
                draft.birthdayDay = min(draft.birthdayDay, draft.daysInBirthdayMonth)
                if !draft.currentAgeText.isEmpty {
                    draft.updateBirthdayYearFromCurrentAge()
                }
            }
            .onChange(of: draft.birthdayDay) { _, _ in
                if !draft.currentAgeText.isEmpty {
                    draft.updateBirthdayYearFromCurrentAge()
                }
            }
            .onChange(of: draft.birthdayYearText) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(4))
                if digits != newValue {
                    draft.birthdayYearText = digits
                    return
                }
                draft.birthdayYearUncertain = digits.isEmpty
                draft.birthdayDay = min(draft.birthdayDay, draft.daysInBirthdayMonth)
                draft.updateCurrentAgeFromCompleteBirthdayYear()
            }
            .onChange(of: draft.currentAgeText) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(3))
                if digits != newValue {
                    draft.currentAgeText = digits
                    return
                }
                draft.updateBirthdayYearFromCurrentAge()
            }
            .onChange(of: draft.reminderDaysText) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(3))
                if digits != newValue {
                    draft.reminderDaysText = digits
                    return
                }
                draft.updateReminderDaysFromText()
            }
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var birthdayYearUncertainBinding: Binding<Bool> {
        Binding(
            get: { draft.birthdayYearUncertain },
            set: { newValue in
                dismissKeyboard()
                draft.birthdayYearUncertain = newValue
            }
        )
    }

    @ViewBuilder private var editorSections: some View {
        whatSection
        frequencySection

        Section {
            linkEditors
        } header: {
            Text(locale.localized("Links"))
        } footer: {
            Text(locale.localized("De bovenste link verschijnt klikbaar in het overzicht. Na het invullen verschijnt automatisch een volgend veld, tot maximaal vijf links."))
            .font(.caption)
        }

        Section("Notitie") {
            noteEditor
        }
    }

    private var whatSection: some View {
        Section {
            titleEditor
            Picker("Categorie", selection: $draft.categoryID) {
                ForEach(categories) { category in
                    Label(
                        category.title,
                        systemImage: category.id == RecurringCategoryStore.birthdayID
                            ? "birthday.cake"
                            : "folder"
                    )
                    .tag(category.id)
                }
            }
            .font(.body)
            .tint(.primary)
            if let item {
                Button("Verwijder herhaling", role: .destructive) {
                    item.isRemoved = true
                    item.completedAt = .now
                    _ = PersistenceSafety.save(modelContext)
                    deleted(item)
                    dismiss()
                }
            }
        } header: {
            Text(draft.categoryID == RecurringCategoryStore.birthdayID
                ? locale.localized("Wie")
                : locale.localized("Wat"))
        }
    }

    @ViewBuilder private var titleEditor: some View {
        titleTextField
    }

    private var titleTextField: some View {
        TextField(titlePlaceholder, text: $draft.title)
            .font(.body)
            .focused($focusedField, equals: .title)
            // A UITextField's intrinsic height can change when it becomes first
            // responder. Keep the Form row content at its final body-text size.
            .frame(height: 22)
    }

    @ViewBuilder private var frequencySection: some View {
        Section {
            if draft.categoryID == RecurringCategoryStore.holidayID {
                holidayFrequencyFields
            } else if draft.categoryID == RecurringCategoryStore.birthdayID {
                birthdayFields
            } else {
                compactClosingDatePicker(
                    title: draft.kind == .yearly
                        ? locale.localized("Startdatum")
                        : locale.localized("Eerstvolgende datum")
                )

                recurrenceTypePicker
                nonBirthdayFrequencyFields
            }
        } header: {
            HStack(spacing: 6) {
                Text(locale.localized("Frequentie"))
                Spacer()
                if draft.categoryID == RecurringCategoryStore.birthdayID {
                    HStack(spacing: 5) {
                        Text(draft.zodiacSignTitle)
                        Text(draft.zodiacSignSymbol)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recurrenceTypePicker: some View {
        Picker("Type", selection: $draft.kind) {
            Text(locale.localized("Vaste regelmaat"))
                .tag(RecurrenceKind.interval)
            Text(locale.localized("Maandelijks op datum"))
                .tag(RecurrenceKind.monthlyDay)
            Text(locale.localized("Maandelijks op weekdag"))
                .tag(RecurrenceKind.monthlyOrdinalWeekday)
            Text(locale.localized("Elk kwartaal"))
                .tag(RecurrenceKind.quarterly)
            Text(locale.localized("Jaarlijks (jubileum)"))
                .tag(RecurrenceKind.yearly)
            Text(locale.localized("Flexibel (ongeveer)"))
                .tag(RecurrenceKind.approximateInterval)
        }
        .font(.body)
        .tint(.primary)
    }

    private var titlePlaceholder: String {
        draft.kind == .birthday
            ? locale.localized("Naam")
            : locale.localized("Titel")
    }

    private var notePlaceholder: String {
        draft.kind == .birthday
            ? locale.localized("Cadeau-idee of andere herinnering...")
            : locale.localized("Extra notitie...")
    }

    private var formattedStartDate: String {
        AppCalendar.localizedDate(draft.startDate, template: "dMMMyyyy")
    }

    private func compactClosingDatePicker(title: String) -> some View {
        ZStack {
            HStack {
                Text(title)
                Spacer()
                Text(formattedStartDate)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            DatePicker(
                title,
                selection: $draft.startDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .id(datePickerResetID)
            .opacity(0.02)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onChange(of: draft.startDate) { _, _ in
                datePickerResetID = UUID()
            }
        }
        .font(.body)
    }

    @ViewBuilder private var holidayFrequencyFields: some View {
        Picker("Regel", selection: $draft.kind) {
            Text("Feestdag op vaste dag").tag(RecurrenceKind.annualFixed)
            Text("Weekdag van een maand").tag(RecurrenceKind.annualOrdinalWeekday)
        }
        .tint(.primary)

        if draft.kind == .annualFixed {
            compactClosingDatePicker(title: "Datum")
        } else {
            Picker("Maand", selection: $draft.annualMonth) {
                ForEach(1...12, id: \.self) { month in
                    Text(AppCalendar.monthName(month)).tag(month)
                }
            }
            .tint(.primary)
            Picker("Welke", selection: $draft.monthlyOrdinal) {
                Text("Eerste").tag(1)
                Text("Tweede").tag(2)
                Text("Derde").tag(3)
                Text("Vierde").tag(4)
                Text("Laatste").tag(5)
            }
            .tint(.primary)
            Picker("Weekdag", selection: $draft.monthlyWeekday) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(RecurrenceEngine.weekdayName(weekday).capitalized).tag(weekday)
                }
            }
            .tint(.primary)
        }
    }

    @ViewBuilder private var nonBirthdayFrequencyFields: some View {
        if draft.kind == .yearly {
            Text(locale.localized("Wordt ieder jaar herhaald op de datum hierboven."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if draft.kind == .quarterly {
            Text("Wordt iedere drie maanden herhaald vanaf de eerstvolgende datum.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if draft.kind == .monthlyDay {
            Stepper("Elke \(draft.monthlyDay)e van de maand", value: $draft.monthlyDay, in: 1...31)
                .font(.body)
        } else if draft.kind == .monthlyOrdinalWeekday {
            Picker("Welke", selection: $draft.monthlyOrdinal) {
                ForEach(1...5, id: \.self) { Text("\($0)e").tag($0) }
            }
            .font(.body)
            .tint(.primary)
            Picker("Weekdag", selection: $draft.monthlyWeekday) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(RecurrenceEngine.weekdayName(weekday).capitalized).tag(weekday)
                }
            }
            .font(.body)
            .tint(.primary)
        } else {
            Stepper("Elke \(draft.intervalValue)", value: $draft.intervalValue, in: 1...99)
                .font(.body)
            Picker("Eenheid", selection: $draft.intervalUnit) {
                Text("Dagen").tag(RecurrenceUnit.day)
                Text("Weken").tag(RecurrenceUnit.week)
                Text("Maanden").tag(RecurrenceUnit.month)
                Text("Jaren").tag(RecurrenceUnit.year)
            }
            .font(.body)
            .tint(.primary)
            if draft.kind == .approximateInterval {
                Text(locale.localized("De app varieert de datum voorspelbaar rond deze gekozen periode. Zo blijft het spontaan, maar verspringt de planning niet bij iedere synchronisatie."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var birthdayFields: some View {
        HStack(spacing: 8) {
            Text(draft.dayMonthLabel)
            Spacer(minLength: 12)

            Picker("Dag", selection: $draft.birthdayDay) {
                ForEach(1...draft.daysInBirthdayMonth, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .tint(.primary)

            Picker("Maand", selection: $draft.birthdayMonth) {
                ForEach(1...12, id: \.self) { month in
                    Text(AppCalendar.monthName(month)).tag(month)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .tint(.primary)

        }
        .font(.body)
        .frame(height: RecurringDraft.birthdayRowHeight)
        .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })

        HStack(spacing: 8) {
            Text(draft.ageYearLabel)
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
            Spacer(minLength: 12)
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
            CompactNumberField(
                placeholder: draft.currentAgePlaceholder,
                text: $draft.currentAgeText,
                isDisabled: draft.shouldDimAgeYearFields,
                accessibilityLabel: draft.currentAgeAccessibilityLabel,
                textChanged: {
                    draft.birthdayYearUncertain = false
                }
            ) { isEditing in
                focusedField = isEditing ? .currentAge : nil
            }
            .frame(width: 40, height: 24)
            .padding(.horizontal, 9)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))

            CompactNumberField(
                placeholder: "2000",
                text: $draft.birthdayYearText,
                isDisabled: draft.shouldDimAgeYearFields,
                accessibilityLabel: locale.localized("Geboortejaar"),
                textChanged: {
                    draft.birthdayYearUncertain = false
                }
            ) { isEditing in
                focusedField = isEditing ? .birthdayYear : nil
            }
            .frame(width: 54, height: 24)
            .padding(.horizontal, 9)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .font(.body)
        .foregroundStyle(draft.shouldDimAgeYearFields ? .secondary : .primary)
        .frame(height: RecurringDraft.birthdayRowHeight)

        HStack(spacing: 10) {
            Text(draft.ageYearUncertainLabel)
            Spacer()
            Toggle("", isOn: birthdayYearUncertainBinding)
                .labelsHidden()
                .controlSize(.small)
            .fixedSize()
            .disabled(draft.birthdayYearText.isEmpty)
        }
        .font(.body)
        .frame(height: RecurringDraft.birthdayRowHeight)
        .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })

        if !draft.isBirthdayYearValid {
            Text(locale.localized("Vul een geldig geboortejaar in."))
            .font(.subheadline)
            .foregroundStyle(.red)
        }

        if draft.isLeapDayBirthday {
            Text("In niet-schrikkeljaren wordt de verjaardag op 28 februari getoond.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        HStack(spacing: 10) {
            Text("Reminder vooraf")
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
            Spacer()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
            Toggle("", isOn: $draft.hasReminder)
                .labelsHidden()
                .controlSize(.small)
        }
        .font(.body)
        .frame(height: RecurringDraft.birthdayRowHeight)
        if draft.hasReminder {
            HStack(spacing: 8) {
                Text("Dagen vooraf")
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }

                Button {
                    dismissKeyboard()
                    draft.reminderDays = max(1, draft.reminderDays - 1)
                    draft.reminderDaysText = String(draft.reminderDays)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(draft.reminderDays <= 1)
                .accessibilityLabel("Eén dag minder")

                CompactNumberField(
                    placeholder: "7",
                    text: $draft.reminderDaysText,
                    accessibilityLabel: "Aantal dagen vooraf",
                    textAlignment: .center,
                    editingChanged: { isEditing in
                        focusedField = isEditing ? .reminderDays : nil
                    }
                )
                .frame(width: draft.reminderDaysFieldWidth, height: 24)
                .padding(.horizontal, 9)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    dismissKeyboard()
                    draft.reminderDays = min(365, draft.reminderDays + 1)
                    draft.reminderDaysText = String(draft.reminderDays)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(draft.reminderDays >= 365)
                .accessibilityLabel("Eén dag meer")
            }
            .font(.body)
            .frame(height: RecurringDraft.birthdayRowHeight)
        }
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            if draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notePlaceholder)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft.notes)
                .font(.body)
                .focused($focusedField, equals: .notes)
                .frame(minHeight: 92)
                .scrollContentBackground(.hidden)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var linkEditors: some View {
        ForEach(draft.links.indices, id: \.self) { index in
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    TextField(
                        locale.localized("Plak link"),
                        text: linkURLBinding(at: index)
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .link(index))
                    .submitLabel(.done)
                    .onSubmit {
                        draft.ensureTrailingLinkField()
                        focusedField = nil
                    }

                    Group {
                        if !draft.links[index].url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                removeLink(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(locale.localized("Link verwijderen"))
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 22, height: 24)
                }
                .frame(maxWidth: .infinity)

                Divider()

                HStack(spacing: 6) {
                    if editingLinkNameIndex == index {
                        TextField(
                            draft.defaultLinkName(at: index),
                            text: linkNameBinding(at: index)
                        )
                        .focused($focusedField, equals: .linkName(index))
                        .submitLabel(.done)
                        .onSubmit { finishEditingLinkName(at: index) }
                    } else if let destination = draft.linkDestination(at: index) {
                        Link(draft.displayLinkName(at: index), destination: destination)
                            .lineLimit(1)
                    } else {
                        Text(draft.displayLinkName(at: index))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    let linkIsEmpty = draft.links[index].url
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    Button {
                        if linkIsEmpty {
                            removeLink(at: index)
                        } else {
                            editingLinkNameIndex = index
                            Task { @MainActor in focusedField = .linkName(index) }
                        }
                    } label: {
                        Image(systemName: linkIsEmpty ? "xmark" : "pencil")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(linkIsEmpty
                        ? locale.localized("Leeg linkveld verwijderen")
                        : locale.localized("Linknaam aanpassen"))
                    .disabled(linkIsEmpty && draft.links.count == 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func linkURLBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { draft.links.indices.contains(index) ? draft.links[index].url : "" },
            set: { newValue in
                guard draft.links.indices.contains(index) else { return }
                draft.links[index].url = newValue
                draft.ensureTrailingLinkField()
            }
        )
    }

    private func linkNameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { draft.links.indices.contains(index) ? draft.links[index].name : "" },
            set: { newValue in
                guard draft.links.indices.contains(index) else { return }
                draft.links[index].name = newValue
            }
        )
    }

    private func finishEditingLinkName(at index: Int) {
        guard editingLinkNameIndex == index else { return }
        editingLinkNameIndex = nil
        focusedField = nil
    }

    private func removeLink(at index: Int) {
        guard draft.links.indices.contains(index) else { return }
        if editingLinkNameIndex == index { editingLinkNameIndex = nil }
        focusedField = nil
        draft.removeLink(at: index)
    }

    private func save() {
        let target = item ?? RecurringItem()
        let isNewItem = item == nil
        draft.normalizeBeforeSaving()
        draft.apply(to: target)
        if isNewItem { modelContext.insert(target) }
        let didSave = PersistenceSafety.save(modelContext)
        if didSave && isNewItem {
            NotificationCenter.default.post(name: .recurringSyncRequested, object: target.id)
        }
        dismiss()
    }
}

private struct RecurringLinkDraft: Codable {
    var url = ""
    var name = ""

    var destination: URL? {
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: "https://\(value)")
    }

    static func decode(_ data: String) -> [RecurringLinkDraft] {
        guard let encoded = data.data(using: .utf8) else { return [] }

        if let decoded = try? JSONDecoder().decode([RecurringLinkDraft].self, from: encoded) {
            return Array(decoded.filter {
                !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.prefix(5))
        }

        // Older versions stored links as a plain array of URL strings.
        if let decoded = try? JSONDecoder().decode([String].self, from: encoded) {
            return Array(decoded.compactMap { value in
                let url = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return url.isEmpty ? nil : RecurringLinkDraft(url: url)
            }.prefix(5))
        }
        return []
    }
}

private struct RecurringDraft {
    static let birthdayRowHeight: CGFloat = 28

    var title = ""
    var categoryID = RecurringCategoryStore.generalID
    var kind = RecurrenceKind.interval
    var startDate = AppCalendar.startOfDay(.now)
    var intervalValue = 1
    var intervalUnit = RecurrenceUnit.week
    var monthlyDay = 1
    var monthlyOrdinal = 1
    var monthlyWeekday = 2
    var annualMonth = 1
    var notes = ""
    var birthdayYearUncertain = true
    var birthdayYearText = ""
    var currentAgeText = ""
    var birthdayMonth = 1
    var birthdayDay = 1
    var hasReminder = false
    var reminderDays = 7
    var reminderDaysText = "7"
    var links = [RecurringLinkDraft()]

    init(item: RecurringItem?, initialCategoryID: String? = nil) {
        if let initialCategoryID {
            categoryID = initialCategoryID
            if initialCategoryID == RecurringCategoryStore.birthdayID {
                kind = .birthday
            } else if initialCategoryID == RecurringCategoryStore.holidayID {
                kind = .annualFixed
            }
        }

        guard let item else { return }
        title = item.title
        categoryID = item.themeRawValue
        kind = item.recurrenceKind
        startDate = item.nextDate
        intervalValue = item.intervalValue
        intervalUnit = item.intervalUnit
        monthlyDay = item.monthlyDay
        monthlyOrdinal = item.monthlyOrdinal
        monthlyWeekday = item.monthlyWeekday
        annualMonth = item.annualMonth
        notes = item.notes
        links = RecurringLinkDraft.decode(item.linksData)
        ensureTrailingLinkField()
        birthdayYearUncertain = item.birthdayYearUncertain
        if let storedBirthDate = item.birthDate {
            birthdayMonth = AppCalendar.calendar.component(.month, from: storedBirthDate)
            birthdayDay = AppCalendar.calendar.component(.day, from: storedBirthDate)
            birthdayYearText = String(AppCalendar.calendar.component(.year, from: storedBirthDate))
            currentAgeText = String(RecurrenceEngine.currentAge(for: storedBirthDate))
        }
        hasReminder = item.reminderDaysBefore != nil
        reminderDays = item.reminderDaysBefore ?? 7
        reminderDaysText = String(reminderDays)
    }

    var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return kind != .birthday || (isBirthdayYearValid && resolvedBirthDate != nil)
    }

    var resolvedBirthDate: Date? {
        guard kind == .birthday, isBirthdayYearValid else { return nil }
        let year = Int(birthdayYearText) ?? 2000
        let calendar = AppCalendar.calendar
        guard let date = calendar.date(from: DateComponents(
            year: year,
            month: birthdayMonth,
            day: birthdayDay
        )) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year,
              components.month == birthdayMonth,
              components.day == birthdayDay else { return nil }
        return AppCalendar.startOfDay(date)
    }

    var isLeapDayBirthday: Bool {
        birthdayMonth == 2 && birthdayDay == 29
    }

    var isBirthdayYearValid: Bool {
        guard !birthdayYearText.isEmpty else { return true }
        guard let year = Int(birthdayYearText) else { return false }
        let currentYear = AppCalendar.calendar.component(.year, from: .now)
        return (1...currentYear).contains(year)
    }

    var daysInBirthdayMonth: Int {
        let year = Int(birthdayYearText) ?? 2000
        let calendar = AppCalendar.calendar
        guard let date = calendar.date(from: DateComponents(year: year, month: birthdayMonth, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    var ageYearLabel: String {
        AppCalendar.locale.localized("Leeftijd/jaar")
    }

    var dayMonthLabel: String {
        AppCalendar.locale.localized("Dag/Maand")
    }

    var ageYearUncertainLabel: String {
        AppCalendar.locale.localized("Leeftijd/jaar onzeker")
    }

    var currentAgeAccessibilityLabel: String {
        AppCalendar.locale.localized("Huidige leeftijd")
    }

    var shouldDimAgeYearFields: Bool {
        birthdayYearUncertain && !birthdayYearText.isEmpty
    }

    var reminderDaysFieldWidth: CGFloat {
        reminderDaysText.count >= 3 ? 32 : 22
    }

    var currentAgePlaceholder: String {
        let calendar = AppCalendar.calendar
        let placeholderYear: Int
        if birthdayYearText.count == 4,
           let year = Int(birthdayYearText),
           (1...calendar.component(.year, from: .now)).contains(year) {
            placeholderYear = year
        } else {
            placeholderYear = 2000
        }
        guard let date = calendar.date(from: DateComponents(
            year: placeholderYear,
            month: birthdayMonth,
            day: min(birthdayDay, daysInBirthdayMonth)
        )) else {
            return String(max(0, calendar.component(.year, from: .now) - 2000))
        }
        return String(RecurrenceEngine.currentAge(for: AppCalendar.startOfDay(date)))
    }

    var zodiacSignTitle: String {
        zodiacSign.title
    }

    var zodiacSignSymbol: String {
        zodiacSign.symbol
    }

    private var zodiacSign: (symbol: String, title: String) {
        let signs: [(month: Int, day: Int, symbol: String, key: String)] = [
            (1, 20, "♒", "zodiac.aquarius"),
            (2, 19, "♓", "zodiac.pisces"),
            (3, 21, "♈", "zodiac.aries"),
            (4, 20, "♉", "zodiac.taurus"),
            (5, 21, "♊", "zodiac.gemini"),
            (6, 21, "♋", "zodiac.cancer"),
            (7, 23, "♌", "zodiac.leo"),
            (8, 23, "♍", "zodiac.virgo"),
            (9, 23, "♎", "zodiac.libra"),
            (10, 23, "♏", "zodiac.scorpio"),
            (11, 22, "♐", "zodiac.sagittarius"),
            (12, 22, "♑", "zodiac.capricorn")
        ]

        let sign = signs.last {
            birthdayMonth > $0.month || (birthdayMonth == $0.month && birthdayDay >= $0.day)
        } ?? signs[11]
        return (sign.symbol, AppCalendar.locale.localized(sign.key))
    }

    mutating func updateBirthdayYearFromCurrentAge() {
        guard let age = Int(currentAgeText), age >= 0 else { return }
        guard let birthDate = RecurrenceEngine.birthDate(
            month: birthdayMonth,
            day: birthdayDay,
            currentAge: age
        ) else { return }
        birthdayYearText = String(AppCalendar.calendar.component(.year, from: birthDate))
        birthdayYearUncertain = false
        birthdayDay = min(birthdayDay, daysInBirthdayMonth)
    }

    mutating func updateCurrentAgeFromCompleteBirthdayYear() {
        guard birthdayYearText.count == 4 else { return }
        guard let birthDate = resolvedBirthDate else { return }
        currentAgeText = String(RecurrenceEngine.currentAge(for: birthDate))
    }

    mutating func updateReminderDaysFromText() {
        guard let days = Int(reminderDaysText) else { return }
        let clampedDays = min(max(days, 1), 365)
        reminderDays = clampedDays
        if clampedDays != days {
            reminderDaysText = String(clampedDays)
        }
    }

    mutating func normalizeBeforeSaving() {
        if reminderDaysText.isEmpty {
            reminderDaysText = String(reminderDays)
        }
        updateReminderDaysFromText()
    }

    mutating func ensureTrailingLinkField() {
        if links.isEmpty {
            links = [RecurringLinkDraft()]
        } else if links.count < 5,
                  !links[links.count - 1].url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            links.append(RecurringLinkDraft())
        }
        if links.count > 5 {
            links = Array(links.prefix(5))
        }
    }

    mutating func removeLink(at index: Int) {
        guard links.indices.contains(index) else { return }
        links.remove(at: index)
        ensureTrailingLinkField()
    }

    private var encodedLinks: String {
        let normalizedLinks = links
            .map {
                RecurringLinkDraft(
                    url: $0.url.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.url.isEmpty }
            .prefix(5)
        guard let data = try? JSONEncoder().encode(Array(normalizedLinks)),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    func defaultLinkName(at index: Int) -> String {
        "Link \(index + 1)"
    }

    func displayLinkName(at index: Int) -> String {
        guard links.indices.contains(index) else { return defaultLinkName(at: index) }
        let name = links[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? defaultLinkName(at: index) : name
    }

    func linkDestination(at index: Int) -> URL? {
        guard links.indices.contains(index) else { return nil }
        return links[index].destination
    }

    func apply(to item: RecurringItem) {
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.themeRawValue = categoryID
        item.recurrenceKind = kind
        item.nextDate = AppCalendar.startOfDay(startDate)
        item.intervalValue = max(1, intervalValue)
        item.intervalUnit = intervalUnit
        item.monthlyDay = monthlyDay
        item.monthlyOrdinal = monthlyOrdinal
        item.monthlyWeekday = monthlyWeekday
        item.annualMonth = annualMonth
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.linksData = encodedLinks
        item.scheduleShiftsData = ""
        item.reminderDaysBefore = kind == .birthday && hasReminder ? reminderDays : nil
        item.birthdayYearUncertain = kind == .birthday && birthdayYearUncertain
        item.recurrenceConfigurationVersion = 1

        if kind == .birthday {
            item.birthDate = resolvedBirthDate.map { AppCalendar.startOfDay($0) }
            item.nextDate = item.birthDate ?? startDate
        } else {
            item.birthDate = nil
        }
        item.frequencyText = RecurrenceEngine.description(for: item)
    }
}

private extension RecurringTheme {
    var color: Color {
        switch self {
        case .birthday: .blue
        case .general: .yellow
        case .personal: .green
        }
    }

    var icon: String {
        switch self {
        case .birthday: "birthday.cake"
        case .general: "sun.max"
        case .personal: "person"
        }
    }
}
