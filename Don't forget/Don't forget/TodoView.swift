import SwiftUI
import SwiftData

struct TodoGroup: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var icon: String
    var colorRawValue: String? = nil

    var color: Color {
        RecurringThemeColorOption(rawValue: colorRawValue ?? "")?.color ?? .blue
    }

    var backgroundColor: Color {
        RecurringThemeColorOption(rawValue: colorRawValue ?? "")?.backgroundColor ?? Color.blue.opacity(0.18)
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    @ViewBuilder
    func todoScrollCompatibility(isScrolled: Binding<Bool>) -> some View {
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
    func compatibleCircularGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

enum TodoGroupStore {
    static let maxCount = 10
    static let todayID = TodoBucket.today.rawValue
    static let asSoonAsPossibleID = "asSoonAsPossible"
    static let shortTermID = TodoBucket.shortTerm.rawValue
    static let longTermID = TodoBucket.longTerm.rawValue
    static let shoppingID = "shopping"

    static var defaults: [TodoGroup] {
        defaults(for: AppCalendar.locale)
    }

    static func defaults(for locale: Locale) -> [TodoGroup] {
        [
            TodoGroup(
                id: shortTermID,
                title: String(localized: "category.todo.soon", locale: locale),
                icon: "bolt.fill",
                colorRawValue: RecurringThemeColorOption.orange.rawValue
            ),
            TodoGroup(
                id: longTermID,
                title: String(localized: "category.todo.longTerm", locale: locale),
                icon: "mountain.2.fill",
                colorRawValue: RecurringThemeColorOption.indigo.rawValue
            ),
            TodoGroup(
                id: shoppingID,
                title: String(localized: "category.todo.groceries", locale: locale),
                icon: "cart.fill",
                colorRawValue: RecurringThemeColorOption.green.rawValue
            )
        ]
    }

    static func decode(_ data: String) -> [TodoGroup] {
        guard let encoded = data.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TodoGroup].self, from: encoded) else {
            return defaults
        }

        return normalize(decoded)
    }

    static func encode(_ groups: [TodoGroup]) -> String {
        let normalized = normalize(groups)
        guard let data = try? JSONEncoder().encode(normalized),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func normalize(_ groups: [TodoGroup]) -> [TodoGroup] {
        let localizedDefaults = defaults
        if isLegacyDefaultConfiguration(groups) {
            return localizedDefaults
        }

        var result: [TodoGroup] = []
        var seen: Set<String> = []

        for group in groups {
            let id = group.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id), result.count < maxCount else {
                continue
            }

            let fallback = localizedDefaults.first { $0.id == id }
            let title: String
            if group.trimmedTitle.isEmpty {
                title = fallback?.title ?? AppCalendar.locale.localized("Nieuw")
            } else if let fallback, isDefaultTitle(group.trimmedTitle, for: id) {
                // Untouched built-in names follow the selected app language.
                title = fallback.title
            } else {
                title = group.trimmedTitle
            }
            let icon = group.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback?.icon ?? "list.bullet"
                : group.icon

            let colorRawValue = RecurringThemeColorOption(rawValue: group.colorRawValue ?? "")?.rawValue
                ?? fallback?.colorRawValue
                ?? RecurringThemeColorOption.blue.rawValue

            result.append(TodoGroup(id: id, title: title, icon: icon, colorRawValue: colorRawValue))
            seen.insert(id)
        }

        if result.isEmpty {
            result = [localizedDefaults[0]]
        }

        return result
    }

    private static func isDefaultTitle(_ title: String, for id: String) -> Bool {
        let knownTitles: [String: Set<String>] = [
            todayID: ["Today", "Vandaag"],
            asSoonAsPossibleID: ["As soon as possible!", "Zo snel mogelijk!"],
            shortTermID: ["Short term", "Soon", "Binnenkort"],
            longTermID: ["Long term", "For later", "Voor later", "Lange termijn"],
            shoppingID: ["Boodschappen", "Groceries"]
        ]
        return knownTitles[id]?.contains(title) == true
    }

    private static func isLegacyDefaultConfiguration(_ groups: [TodoGroup]) -> Bool {
        let legacyThree = [
            (todayID, "sun.max", RecurringThemeColorOption.yellow.rawValue),
            (shortTermID, "bolt", RecurringThemeColorOption.blue.rawValue),
            (longTermID, "mountain.2", RecurringThemeColorOption.green.rawValue)
        ]
        let legacyFour = [
            (todayID, "sun.max", RecurringThemeColorOption.yellow.rawValue),
            (asSoonAsPossibleID, "bolt", RecurringThemeColorOption.red.rawValue),
            (shortTermID, "clock", RecurringThemeColorOption.blue.rawValue),
            (longTermID, "mountain.2", RecurringThemeColorOption.green.rawValue)
        ]

        func matches(_ expected: [(String, String, String)]) -> Bool {
            guard groups.count == expected.count else { return false }
            return zip(groups, expected).allSatisfy { group, expectedGroup in
                group.id == expectedGroup.0
                    && isDefaultTitle(group.trimmedTitle, for: expectedGroup.0)
                    && group.icon == expectedGroup.1
                    && group.colorRawValue == expectedGroup.2
            }
        }

        return matches(legacyThree) || matches(legacyFour)
    }
}

private enum TodoGroupIcons {
    static let all = [
        "checklist", "list.bullet", "checkmark.circle.fill", "flag.fill",
        "sun.max.fill", "moon.stars.fill", "bolt.fill", "mountain.2.fill",
        "star.fill", "heart.fill", "person.fill", "figure.2",
        "house.fill", "building.2.fill", "briefcase.fill", "graduationcap.fill",
        "book.fill", "pencil", "bell.fill", "clock.fill",
        "timer", "hourglass", "leaf.fill", "tree.fill",
        "pawprint.fill", "car.fill", "airplane", "bicycle",
        "fork.knife", "cup.and.saucer.fill", "cart.fill", "creditcard.fill",
        "eurosign.circle.fill", "cross.case.fill", "pills.fill", "dumbbell.fill",
        "music.note", "camera.fill", "gamecontroller.fill", "wrench.and.screwdriver.fill"
    ]
}

private struct TodoAgendaMoveUndo {
    let entryID: UUID
    let destinationDate: Date
    let text: String
    let bucketRawValue: String
    let showOnWidget: Bool
    let createdAt: Date
}

private struct TodoTutorialInputCommand: Equatable {
    let id: Int
    let text: String?
    let submitsCurrentText: Bool
    let focusesField: Bool
}

struct TodoView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.undoManager)
    private var undoManager

    @Environment(\.locale)
    private var locale

    @Query(
        filter: #Predicate<TodoItem> { todo in
            !todo.isDone && !todo.isRemoved
        },
        sort: \TodoItem.createdAt,
        order: .forward
    )
    private var todos: [TodoItem]

    @State private var isScrolled = false
    @State private var isKeyboardVisible = false
    @State private var newGroupTitle = ""
    @State private var recentlyCompletedTodo: TodoItem?
    @State private var dismissUndoTask: Task<Void, Never>?
    @State private var recentlyRemovedTodo: TodoItem?
    @State private var recentlyRemovedTodoTitle = ""
    @State private var recentlyMovedToAgenda: TodoAgendaMoveUndo?
    @State private var activeReorderHintIDs: Set<UUID> = []
    @State private var isHelpExpanded = false
    @State private var onboardingTodoID: UUID?
    @State private var todoTutorialDraftText = ""
    @State private var todoTutorialInputCommand: TodoTutorialInputCommand?
    @State private var todoTutorialInputCommandID = 0

    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""

    @AppStorage(SettingsKeys.hasOpenedTodoHelp)
    private var hasOpenedTodoHelp = false

    @AppStorage(SettingsKeys.todoTutorialStep)
    private var todoTutorialStep = 0

    @AppStorage(SettingsKeys.hasCompletedTodoTutorial)
    private var hasCompletedTodoTutorial = false

    private var groups: [TodoGroup] {
        get { TodoGroupStore.decode(todoGroupsData) }
        nonmutating set { todoGroupsData = TodoGroupStore.encode(newValue) }
    }

    private var visibleOnboardingStep: Int? {
        isHelpExpanded && !hasCompletedTodoTutorial ? todoTutorialStep : nil
    }

    var body: some View {
        let activeTodosByGroup = Dictionary(
            grouping: todos,
            by: \.bucketRawValue
        )
        let hintSequence = groups.flatMap { activeTodosByGroup[$0.id] ?? [] }

        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 12) {
                    if isHelpExpanded {
                        TodoHelpCard(
                            locale: locale,
                            step: todoTutorialStep,
                            isCompleted: hasCompletedTodoTutorial,
                            previous: showPreviousTodoTutorialStep,
                            next: showNextTodoTutorialStep,
                            replay: replayTodoTutorial,
                            close: { isHelpExpanded = false }
                        )
                        .padding(.bottom, 2)
                    }

                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        let groupTodos = activeTodosByGroup[group.id] ?? []
                        todoBucketCard(group: group, index: index, groupTodos: groupTodos)
                    }

                    if groups.count < TodoGroupStore.maxCount {
                        NewTodoGroupLine(
                            text: $newGroupTitle,
                            add: addGroup
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .adaptiveReadableWidth()
            }
            .todoScrollCompatibility(isScrolled: $isScrolled)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    TodoTopTitle(
                        locale: locale,
                        showsInfoHint: !hasOpenedTodoHelp,
                        isHelpExpanded: isHelpExpanded,
                        toggleHelp: toggleHelp
                    )
                    .opacity(isScrolled ? 0 : 1)
                    .animation(.easeOut(duration: 0.18), value: isScrolled)

                    HStack {
                        Button {
                            undoManager?.undo()
                            completeTodoTutorialAction(for: 3)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .compatibleCircularGlassEffect()
                        .background(
                            visibleOnboardingStep == 3 ? Color.brandLightBlue : Color.clear,
                            in: Circle()
                        )
                        .disabled(!(undoManager?.canUndo ?? false))
                        .accessibilityLabel("Laatste wijziging terugdraaien")
                        .overlay {
                            if visibleOnboardingStep == 3 {
                                Circle()
                                    .stroke(Color.brandHardBlue, lineWidth: 3)
                                    .padding(-4)
                                    .allowsHitTesting(false)
                            }
                        }

                        Spacer()

                        Button {
                            completeTodoTutorialAction(for: 2)
                            AppKeyboard.dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .compatibleCircularGlassEffect()
                        .background(
                            visibleOnboardingStep == 2 ? Color.brandLightBlue : Color.clear,
                            in: Circle()
                        )
                        .disabled(!isKeyboardVisible)
                        .accessibilityLabel("Toetsenbord sluiten")
                        .overlay {
                            if visibleOnboardingStep == 2 {
                                Circle()
                                    .stroke(Color.brandHardBlue, lineWidth: 3)
                                    .padding(-4)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 18)
                .padding(.vertical, 6)
                .adaptiveReadableWidth()
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                Group {
                    if recentlyMovedToAgenda != nil {
                        moveToAgendaUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if recentlyRemovedTodo != nil {
                        removalUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if recentlyCompletedTodo != nil {
                        completionUndoBar
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .adaptiveReadableWidth()
                .padding(.bottom, 4)
            }
            .onAppear {
                modelContext.undoManager = undoManager
                moveTodosFromRemovedDefaultGroups()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .task {
                await runReorderHintWave(itemIDs: hintSequence.map(\.id))
            }
        }
    }

    private func todoBucketCard(
        group: TodoGroup,
        index: Int,
        groupTodos: [TodoItem]
    ) -> some View {
        let isFirstGroup = index == 0
        let step = visibleOnboardingStep
        let highlightsInput = isFirstGroup && (step == 0 || step == 2)
        let usesFourCharacterMinimum = isFirstGroup && (step == 0 || step == 1)

        return TodoBucketCard(
            group: group,
            groups: groups,
            todos: groupTodos,
            canMoveUp: index > 0,
            canMoveDown: index < groups.count - 1,
            canDeleteGroup: groups.count > 1 && !todos.contains { $0.bucketRawValue == group.id },
            rename: { renameGroup(group.id, to: $0) },
            changeColor: { changeGroupColor(group.id, to: $0) },
            changeIcon: { changeGroupIcon(group.id, to: $0) },
            delete: { deleteGroup(group.id) },
            moveUp: { moveGroup(from: index, direction: -1) },
            moveDown: { moveGroup(from: index, direction: 1) },
            highlightsNewTodoField: highlightsInput,
            highlightsNewTodoPlus: isFirstGroup && step == 1,
            highlightedTodoID: step == 4 ? onboardingTargetTodoID : nil,
            highlightsCategoryReorder: isFirstGroup && step == 5,
            newTodoTextChanged: { text in
                if isFirstGroup {
                    handleOnboardingTodoTextChanged(text)
                }
            },
            newTodoAdded: handleOnboardingTodoAdded,
            todoMovePerformed: handleOnboardingTodoMove,
            categoryReordered: handleOnboardingCategoryReorder,
            tutorialInputCommand: isFirstGroup ? todoTutorialInputCommand : nil,
            minimumTodoLength: usesFourCharacterMinimum ? 4 : 1,
            requiresPlusToSubmit: isFirstGroup && step == 1,
            activeReorderHintIDs: activeReorderHintIDs,
            completed: showCompletionUndo,
            removed: showRemovalUndo,
            movedToAgenda: showMoveToAgendaUndo
        )
    }

    private var onboardingTargetTodoID: UUID? {
        if let onboardingTodoID, todos.contains(where: { $0.id == onboardingTodoID }) {
            return onboardingTodoID
        }
        return todos.first?.id
    }

    private func toggleHelp() {
        hasOpenedTodoHelp = true
        isHelpExpanded.toggle()
    }

    private func showPreviousTodoTutorialStep() {
        if hasCompletedTodoTutorial {
            hasCompletedTodoTutorial = false
            showTodoTutorialStep(TodoHelpCard.stepCount - 1)
            return
        }
        if todoTutorialStep == 2 {
            restoreOnboardingTodoToInput()
        } else if todoTutorialStep == 3 {
            showTodoTutorialStep(2)
            sendTodoTutorialInputCommand(
                text: nil,
                submitsCurrentText: false,
                focusesField: true
            )
        } else {
            showTodoTutorialStep(todoTutorialStep - 1)
        }
    }

    private func showNextTodoTutorialStep() {
        switch todoTutorialStep {
        case 0:
            if todoTutorialDraftText.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 {
                sendTodoTutorialInputCommand(text: "Example", submitsCurrentText: false)
            }
            showTodoTutorialStep(1)
        case 1:
            let draft = todoTutorialDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
            sendTodoTutorialInputCommand(
                text: draft.count >= 4 ? nil : "Example",
                submitsCurrentText: true
            )
        case 2:
            showTodoTutorialStep(3)
            sendTodoTutorialInputCommand(
                text: nil,
                submitsCurrentText: false,
                focusesField: false
            )
        case 3:
            undoManager?.undo()
            _ = PersistenceSafety.save(modelContext)
            showTodoTutorialStep(4)
        case TodoHelpCard.stepCount - 1:
            if groups.count > 1 {
                moveGroup(from: 0, direction: 1)
            }
            finishTodoTutorial()
        default:
            showTodoTutorialStep(todoTutorialStep + 1)
        }
    }

    private func showTodoTutorialStep(_ requestedStep: Int) {
        let targetStep = min(max(requestedStep, 0), TodoHelpCard.stepCount - 1)
        if targetStep == 4 {
            ensureOnboardingTodoExists()
        }
        todoTutorialStep = targetStep
    }

    private func completeTodoTutorialAction(for step: Int) {
        guard isHelpExpanded,
              !hasCompletedTodoTutorial,
              todoTutorialStep == step else { return }

        if step == TodoHelpCard.stepCount - 1 {
            finishTodoTutorial()
        } else {
            showTodoTutorialStep(todoTutorialStep + 1)
        }
    }

    private func handleOnboardingTodoTextChanged(_ text: String) {
        todoTutorialDraftText = text
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 else { return }
        completeTodoTutorialAction(for: 0)
    }

    private func handleOnboardingTodoAdded(_ id: UUID) {
        onboardingTodoID = id
        if todoTutorialStep == 1 {
            completeTodoTutorialAction(for: 1)
        } else {
            completeTodoTutorialAction(for: 2)
        }
    }

    private func handleOnboardingTodoMove(_ id: UUID) {
        onboardingTodoID = id
        completeTodoTutorialAction(for: 4)
    }

    private func handleOnboardingCategoryReorder() {
        completeTodoTutorialAction(for: 5)
    }

    private func finishTodoTutorial() {
        hasCompletedTodoTutorial = true
    }

    private func replayTodoTutorial() {
        hasCompletedTodoTutorial = false
        todoTutorialStep = 0
        onboardingTodoID = nil
        todoTutorialDraftText = ""
    }

    private func sendTodoTutorialInputCommand(
        text: String?,
        submitsCurrentText: Bool,
        focusesField: Bool = true
    ) {
        todoTutorialInputCommandID += 1
        if let text {
            todoTutorialDraftText = text
        }
        todoTutorialInputCommand = TodoTutorialInputCommand(
            id: todoTutorialInputCommandID,
            text: text,
            submitsCurrentText: submitsCurrentText,
            focusesField: focusesField
        )
    }

    private func ensureOnboardingTodoExists() {
        let fetchedTodos = (try? modelContext.fetch(FetchDescriptor<TodoItem>())) ?? todos
        let activeTodos = fetchedTodos.filter { !$0.isDone && !$0.isRemoved }

        if let onboardingTodoID,
           activeTodos.contains(where: { $0.id == onboardingTodoID }) {
            return
        }

        if let existing = activeTodos.first {
            onboardingTodoID = existing.id
            return
        }

        guard let groupID = groups.first?.id else { return }
        let todo = TodoItem(text: "Example")
        todo.bucketRawValue = groupID
        modelContext.insert(todo)
        _ = PersistenceSafety.save(modelContext)
        onboardingTodoID = todo.id
    }

    private func restoreOnboardingTodoToInput() {
        let fetchedTodos = (try? modelContext.fetch(FetchDescriptor<TodoItem>())) ?? todos
        let activeTodos = fetchedTodos.filter { !$0.isDone && !$0.isRemoved }
        let candidate = onboardingTodoID.flatMap { id in
            activeTodos.first(where: { $0.id == id })
        } ?? activeTodos.last
        let restoredText = candidate?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inputText = restoredText.count >= 4 ? restoredText : "Example"

        if let candidate {
            modelContext.delete(candidate)
            _ = PersistenceSafety.save(modelContext)
        }

        onboardingTodoID = nil
        todoTutorialDraftText = inputText
        showTodoTutorialStep(1)
        sendTodoTutorialInputCommand(
            text: inputText,
            submitsCurrentText: false,
            focusesField: true
        )
    }

    private func runReorderHintWave(itemIDs: [UUID]) async {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeReorderHintIDs.removeAll()
        }
        guard !itemIDs.isEmpty else { return }

        do {
            try await Task.sleep(for: .seconds(6))
            var previousID: UUID?

            for id in itemIDs {
                try Task.checkCancellation()
                withAnimation(.smooth(duration: 0.34, extraBounce: 0)) {
                    _ = activeReorderHintIDs.insert(id)
                }
                try await Task.sleep(for: .milliseconds(160))

                if let previousID {
                    withAnimation(.smooth(duration: 0.38, extraBounce: 0)) {
                        _ = activeReorderHintIDs.remove(previousID)
                    }
                }
                previousID = id
                try await Task.sleep(for: .milliseconds(100))
            }

            try await Task.sleep(for: .milliseconds(160))
            withAnimation(.smooth(duration: 0.38, extraBounce: 0)) {
                activeReorderHintIDs.removeAll()
            }
        } catch {
            withTransaction(transaction) {
                activeReorderHintIDs.removeAll()
            }
        }
    }

    private func moveTodosFromRemovedDefaultGroups() {
        guard let destinationID = groups.first?.id else { return }
        let validGroupIDs = Set(groups.map(\.id))
        var changed = false

        for todo in todos where !validGroupIDs.contains(todo.bucketRawValue) {
            todo.bucketRawValue = destinationID
            changed = true
        }

        if changed {
            _ = PersistenceSafety.save(modelContext)
        }
    }

    private func renameGroup(_ id: String, to title: String) {
        var updated = groups
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].title = title
        groups = updated
    }

    private func changeGroupColor(_ id: String, to colorRawValue: String) {
        var updated = groups
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].colorRawValue = colorRawValue
        groups = updated
    }

    private func changeGroupIcon(_ id: String, to iconName: String) {
        var updated = groups
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].icon = iconName
        groups = updated
    }

    private func moveGroup(from index: Int, direction: Int) {
        var updated = groups
        let target = index + direction
        guard updated.indices.contains(index), updated.indices.contains(target) else { return }

        updated.swapAt(index, target)

        withAnimation(.easeOut(duration: 0.13)) {
            groups = updated
        }
    }

    private func addGroup() {
        let title = newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, groups.count < TodoGroupStore.maxCount else { return }

        var updated = groups
        updated.append(TodoGroup(
            id: UUID().uuidString,
            title: title,
            icon: "list.bullet",
            colorRawValue: RecurringThemeColorOption.blue.rawValue
        ))
        groups = updated
        newGroupTitle = ""
    }

    private func deleteGroup(_ id: String) {
        var updated = groups
        guard updated.count > 1,
              let index = updated.firstIndex(where: { $0.id == id }),
              !todos.contains(where: { $0.bucketRawValue == id }) else {
            return
        }

        updated.remove(at: index)
        guard let destinationID = updated.first?.id else { return }
        for todo in todos where todo.bucketRawValue == id {
            todo.bucketRawValue = destinationID
        }
        groups = updated
        _ = PersistenceSafety.save(modelContext)
    }

    private func showCompletionUndo(_ todo: TodoItem) {
        dismissUndoTask?.cancel()
        recentlyRemovedTodo = nil
        recentlyMovedToAgenda = nil
        withAnimation(.snappy(duration: 0.25)) {
            recentlyCompletedTodo = todo
        }
        dismissUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyCompletedTodo = nil
            }
        }
    }

    private func showRemovalUndo(_ todo: TodoItem) {
        dismissUndoTask?.cancel()
        recentlyCompletedTodo = nil
        recentlyMovedToAgenda = nil
        recentlyRemovedTodo = todo
        recentlyRemovedTodoTitle = todo.text
        dismissUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyRemovedTodo = nil
            }
        }
    }

    private func undoRemoval() {
        guard let todo = recentlyRemovedTodo else { return }
        todo.isDone = false
        todo.isRemoved = false
        todo.completedAt = nil
        _ = PersistenceSafety.save(modelContext)
        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyRemovedTodo = nil
        }
    }

    private var removalUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "trash.fill",
            iconColor: .red,
            message: locale.localizedFormat("feedback.deleted", recentlyRemovedTodoTitle),
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoRemoval
        )
    }

    private func showMoveToAgendaUndo(_ move: TodoAgendaMoveUndo) {
        dismissUndoTask?.cancel()
        recentlyCompletedTodo = nil
        recentlyRemovedTodo = nil
        recentlyMovedToAgenda = move
        dismissUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyMovedToAgenda = nil
            }
        }
    }

    private func undoMoveToAgenda() {
        guard let move = recentlyMovedToAgenda else { return }

        let entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        if let entry = entries.first(where: { $0.id == move.entryID }) {
            modelContext.delete(entry)
        }

        let restoredTodo = TodoItem(text: move.text)
        restoredTodo.bucketRawValue = move.bucketRawValue
        restoredTodo.showOnWidget = move.showOnWidget
        restoredTodo.createdAt = move.createdAt
        modelContext.insert(restoredTodo)
        _ = PersistenceSafety.save(modelContext)

        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyMovedToAgenda = nil
        }
    }

    private var moveToAgendaUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "calendar.badge.checkmark",
            iconColor: .blue,
            message: moveToAgendaUndoText,
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoMoveToAgenda
        )
    }

    private var moveToAgendaUndoText: String {
        guard let move = recentlyMovedToAgenda else { return "" }
        let date = AppCalendar.localizedDate(move.destinationDate, template: "dMMM")
        return locale.localizedFormat("todo.movedToDate", move.text, date)
    }

    private func undoCompletion() {
        guard let todo = recentlyCompletedTodo else { return }
        todo.isDone = false
        todo.completedAt = nil
        _ = PersistenceSafety.save(modelContext)
        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyCompletedTodo = nil
        }
    }

    private var completionUndoBar: some View {
        UndoFeedbackBar(
            iconSystemName: "checkmark.circle.fill",
            iconColor: .blue,
            message: completionUndoText,
            undoTitle: locale.localized("Ongedaan maken"),
            action: undoCompletion
        )
    }

    private var completionUndoText: String {
        guard let todo = recentlyCompletedTodo else { return "" }
        return locale.localizedFormat("feedback.movedToFinished", todo.text)
    }

}

private struct TodoTopTitle: View {
    let locale: Locale
    let showsInfoHint: Bool
    let isHelpExpanded: Bool
    let toggleHelp: () -> Void

    var body: some View {
        Button(action: toggleHelp) {
            HStack(spacing: 6) {
                Text(AppSection.todo.title(for: locale))
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
        .accessibilityLabel(locale.localized("Uitleg over Taken"))
        .accessibilityValue(isHelpExpanded
            ? locale.localized("Uitgeklapt")
            : locale.localized("Ingeklapt"))
        .accessibilityHint(locale.localized("Tik om de uitleg in of uit te klappen"))
    }
}

private struct TodoHelpStep: Identifiable {
    let id: Int
    let icon: String
    let key: String

    func text(for locale: Locale) -> String {
        locale.localized(key)
    }
}

private struct TodoHelpCard: View {
    static let stepCount = 6

    let locale: Locale
    let step: Int
    let isCompleted: Bool
    let previous: () -> Void
    let next: () -> Void
    let replay: () -> Void
    let close: () -> Void

    private let steps = [
        TodoHelpStep(
            id: 0,
            icon: "text.cursor",
            key: "Maak een taak in een categorie door in het invoerveld iets te schrijven.",
        ),
        TodoHelpStep(
            id: 1,
            icon: "plus",
            key: "Tik op het plusje om direct nog een taak aan te maken.",
        ),
        TodoHelpStep(
            id: 2,
            icon: "checkmark",
            key: "Beschrijf nog een taak, of tik rechtsboven op het vinkje om de invoer af te ronden.",
        ),
        TodoHelpStep(
            id: 3,
            icon: "arrow.uturn.backward",
            key: "Tik op de pijl linksboven om je laatste invoer ongedaan te maken. Dit kan voor maximaal drie invoeren.",
        ),
        TodoHelpStep(
            id: 4,
            icon: "arrow.left.arrow.right",
            key: "Voor elke taak staat hoe lang die openstaat. Tik hierop om de taak naar een andere categorie of de kalender te verplaatsen.",
        ),
        TodoHelpStep(
            id: 5,
            icon: "chevron.up.chevron.down",
            key: "Pas de volgorde van categorieën aan via de chevrons.",
        )
    ]

    private var currentStep: TodoHelpStep {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .tutorialCardStyle(isCompleted: isCompleted, close: close)
    }

    private var stepContent: some View {
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
            .id(step)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var completedContent: some View {
        TutorialCompletionContent(
            message: locale.localized("Je hebt je taken helemaal in de hand."),
            replayTitle: locale.localized("Opnieuw"),
            backAccessibilityLabel: locale.localized("Vorige stap"),
            closeAccessibilityLabel: locale.localized("Sluiten"),
            back: previous,
            replay: replay,
            close: close
        )
    }
}

private struct TodoBucketCard: View {
    let group: TodoGroup
    let groups: [TodoGroup]
    let todos: [TodoItem]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDeleteGroup: Bool
    let rename: (String) -> Void
    let changeColor: (String) -> Void
    let changeIcon: (String) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let highlightsNewTodoField: Bool
    let highlightsNewTodoPlus: Bool
    let highlightedTodoID: UUID?
    let highlightsCategoryReorder: Bool
    let newTodoTextChanged: (String) -> Void
    let newTodoAdded: (UUID) -> Void
    let todoMovePerformed: (UUID) -> Void
    let categoryReordered: () -> Void
    let tutorialInputCommand: TodoTutorialInputCommand?
    let minimumTodoLength: Int
    let requiresPlusToSubmit: Bool
    let activeReorderHintIDs: Set<UUID>
    let completed: (TodoItem) -> Void
    let removed: (TodoItem) -> Void
    let movedToAgenda: (TodoAgendaMoveUndo) -> Void
    @State private var showingAppearancePicker = false
    @State private var showingCategoryActions = false
    @State private var isNewTodoFieldFocused = false

    private var canDelete: Bool {
        canDeleteGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Button {
                    showingAppearancePicker = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(group.backgroundColor)
                        Image(systemName: group.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(group.color)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kleur en icoon van \(group.title) aanpassen")

                VStack(alignment: .leading, spacing: 2) {
                    DeferredCommitTextField(
                        "Groep",
                        value: group.title,
                        commit: rename
                    )
                    .font(.system(size: 17, weight: .semibold))
                    .textFieldStyle(.plain)

                    Text(openCountText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 36, alignment: .center)
                .offset(y: -2)

                Spacer()

                actionToolbar
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 14)

            Divider()
                .overlay(Color.primary.opacity(0.07))
                .padding(.leading, 62)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                    TodoLine(
                        todo: todo,
                        groups: groups,
                        color: group.color,
                        backgroundColor: group.backgroundColor,
                        isReorderHintActive: activeReorderHintIDs.contains(todo.id),
                        isOnboardingHighlighted: highlightedTodoID == todo.id,
                        isCompletionEnabled: !(isNewTodoFieldFocused && index == todos.count - 1),
                        movePerformed: todoMovePerformed,
                        completed: completed,
                        removed: removed,
                        movedToAgenda: movedToAgenda
                    )
                }

                NewTodoLine(
                    groupID: group.id,
                    highlightsField: highlightsNewTodoField,
                    highlightsPlus: highlightsNewTodoPlus,
                    tutorialInputCommand: tutorialInputCommand,
                    minimumCharacterCount: minimumTodoLength,
                    requiresPlusToSubmit: requiresPlusToSubmit,
                    textChanged: newTodoTextChanged,
                    todoAdded: newTodoAdded,
                    focusChanged: { isNewTodoFieldFocused = $0 }
                )
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        }
        .sheet(isPresented: $showingAppearancePicker) {
            TodoGroupAppearancePicker(
                groupTitle: group.title,
                selectedColorRawValue: group.colorRawValue ?? RecurringThemeColorOption.blue.rawValue,
                selectedIconName: group.icon,
                changeColor: changeColor,
                changeIcon: changeIcon
            )
        }
    }

    private var actionToolbar: some View {
        Button {
            AppKeyboard.dismiss()
            showingCategoryActions = true
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(group.color)
        .accessibilityLabel("Volgorde van \(group.title) aanpassen")
        .overlay {
            if highlightsCategoryReorder {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.brandHardBlue, lineWidth: 3)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
        .popover(
            isPresented: $showingCategoryActions,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            categoryActionsPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var categoryActionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryActionButton("Omhoog verplaatsen", systemImage: "arrow.up", enabled: canMoveUp) {
                moveUp()
                categoryReordered()
            }
            categoryActionButton("Omlaag verplaatsen", systemImage: "arrow.down", enabled: canMoveDown) {
                moveDown()
                categoryReordered()
            }

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
        AppKeyboard.dismiss()
        showingCategoryActions = false
        action()
    }

    private var openCountText: String {
        todos.count == 1 ? "1 open" : "\(todos.count) open"
    }
}

private struct TodoGroupAppearancePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let groupTitle: String
    let changeColor: (String) -> Void
    let changeIcon: (String) -> Void
    @State private var selectedColorRawValue: String
    @State private var selectedIconName: String

    init(
        groupTitle: String,
        selectedColorRawValue: String,
        selectedIconName: String,
        changeColor: @escaping (String) -> Void,
        changeIcon: @escaping (String) -> Void
    ) {
        self.groupTitle = groupTitle
        self.changeColor = changeColor
        self.changeIcon = changeIcon
        _selectedColorRawValue = State(initialValue: selectedColorRawValue)
        _selectedIconName = State(initialValue: selectedIconName)
    }

    private var selectedColor: Color {
        RecurringThemeColorOption(rawValue: selectedColorRawValue)?.color ?? .blue
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
                            ForEach(TodoGroupIcons.all, id: \.self) { iconName in
                                Button {
                                    selectedIconName = iconName
                                    changeIcon(iconName)
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedIconName == iconName
                                                ? selectedColor.opacity(0.22)
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
            .navigationTitle(groupTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { dismiss() }
                }
            }
        }
    }
}

private struct TodoLine: View {
    @Bindable var todo: TodoItem
    let groups: [TodoGroup]
    let color: Color
    let backgroundColor: Color
    let isReorderHintActive: Bool
    let isOnboardingHighlighted: Bool
    let isCompletionEnabled: Bool
    let movePerformed: (UUID) -> Void
    let completed: (TodoItem) -> Void
    let removed: (TodoItem) -> Void
    let movedToAgenda: (TodoAgendaMoveUndo) -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var showMoveToAgenda = false
    @State private var agendaDate = AppCalendar.startOfDay(.now)
    @State private var isDeleting = false
    @State private var moveSelectionToEndToken = 0
    @State private var isProtectingInitialTap = false
    @State private var initialTapProtectionTask: Task<Void, Never>?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            moveMenu

            todoTextField
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? .secondary : .primary)
                .submitLabel(.done)
                .onChange(of: todo.text) { _, newValue in
                    let normalizedText = newValue.replacingOccurrences(of: "\n", with: "")
                    if normalizedText != newValue {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            todo.text = normalizedText
                        }
                        dismissKeyboard()
                    }
                    if normalizedText.isEmpty {
                        deleteTodo()
                    }
                }
                .onSubmit {
                    dismissKeyboard()
                }

            Spacer(minLength: 2)

            Button {
                todo.toggleDone()
                _ = PersistenceSafety.save(modelContext)
                if todo.isDone {
                    completed(todo)
                }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle().inset(by: -6))
            }
            // The header action is centered 40 pt from the readable edge. Move
            // only the control so the task text keeps its full layout width.
            .offset(x: -6)
            .buttonStyle(.plain)
            .allowsHitTesting(isCompletionEnabled)
        }
        .onDisappear {
            initialTapProtectionTask?.cancel()
        }
        .sheet(isPresented: $showMoveToAgenda) {
            NavigationStack {
                VStack(spacing: 0) {
                    DatePicker(
                        "Datum",
                        selection: $agendaDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }
                .navigationTitle("Kies datum")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") {
                            showMoveToAgenda = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verplaats") {
                            moveToAgenda(on: agendaDate)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func dismissKeyboard() {
        isTextFieldFocused = false
        AppKeyboard.dismiss()
    }

    private var todoTextField: some View {
        Text(todo.text.isEmpty ? " " : todo.text)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    compatibleTodoTextField
                        .focused($isTextFieldFocused)

                    if !isTextFieldFocused || isProtectingInitialTap {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: beginEditingAtEnd)
                            .accessibilityLabel("Taak bewerken")
                    }
                }
            }
    }

    @ViewBuilder private var compatibleTodoTextField: some View {
        if #available(iOS 18.0, *) {
            TodoSelectionTextField(
                text: $todo.text,
                moveSelectionToEndToken: moveSelectionToEndToken
            )
        } else {
            TextField("", text: $todo.text, axis: .vertical)
        }
    }

    private func beginEditingAtEnd() {
        moveSelectionToEndToken &+= 1
        if !isTextFieldFocused {
            protectInitialTap()
            isTextFieldFocused = true
        }
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

    private var moveMenu: some View {
        Menu {
            ForEach(destinationGroups) { group in
                Button {
                    dismissKeyboard()
                    todo.bucketRawValue = group.id
                    _ = PersistenceSafety.save(modelContext)
                    movePerformed(todo.id)
                } label: {
                    Label(group.title, systemImage: group.icon)
                }
            }

            if destinationGroups.isEmpty {
                Button {} label: {
                    Label("Geen andere categorieën", systemImage: "tray")
                }
                .disabled(true)
            }

            Divider()

            Button {
                dismissKeyboard()
                moveToAgenda(on: AppCalendar.startOfDay(.now))
            } label: {
                Label("Naar vandaag \(todayDateText)", systemImage: "calendar.badge.checkmark")
            }

            Button {
                dismissKeyboard()
                let today = AppCalendar.startOfDay(.now)
                agendaDate = AppCalendar.calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: today
                ) ?? today
                Task { @MainActor in
                    // Let the menu finish dismissing before presenting the sheet.
                    try? await Task.sleep(for: .milliseconds(120))
                    showMoveToAgenda = true
                }
            } label: {
                Label("Andere datum in agenda...", systemImage: "calendar.badge.plus")
            }

            Divider()

            Button(role: .destructive) {
                dismissKeyboard()
                removeTodo()
            } label: {
                Label("Verwijderen", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .tint(.red)
        } label: {
            Group {
                if isReorderHintActive {
                    ZStack {
                        Capsule()
                            .fill(backgroundColor)
                            .frame(width: 30, height: 20)

                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.72)),
                            removal: .opacity.combined(with: .scale(scale: 1.12))
                        )
                    )
                } else {
                    Text(ageBadgeText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(backgroundColor, in: Capsule())
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.88)),
                                removal: .opacity.combined(with: .scale(scale: 0.82))
                            )
                        )
                }
            }
            .foregroundStyle(color)
            .frame(width: 36, height: 24, alignment: .center)
            .overlay {
                if isOnboardingHighlighted {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.brandHardBlue, lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel("\(accessibleAgeText), taak verplaatsen")
        .simultaneousGesture(TapGesture().onEnded {
            dismissKeyboard()
        })
    }

    private var destinationGroups: [TodoGroup] {
        groups.filter { $0.id != todo.bucketRawValue }
    }

    private var ageBadgeText: String {
        let days = TodoAge.daysOpen(since: todo.createdAt)
        if days == 0 { return AppCalendar.locale.localized("todo.age.now") }
        if days < 14 { return AppCalendar.locale.localizedFormat("todo.age.daysShort", days) }
        if days < 70 { return AppCalendar.locale.localizedFormat("todo.age.weeksShort", days / 7) }
        return AppCalendar.locale.localizedFormat("todo.age.monthsShort", days / 30)
    }

    private var accessibleAgeText: String {
        let days = TodoAge.daysOpen(since: todo.createdAt)
        return days == 0
            ? AppCalendar.locale.localized("todo.age.createdToday")
            : AppCalendar.locale.localizedFormat("todo.age.daysOpen", days)
    }

    private var todayDateText: String {
        AppCalendar.localizedDate(.now, template: "Md")
    }

    private func deleteTodo() {
        guard !isDeleting else { return }
        isDeleting = true
        modelContext.delete(todo)
        _ = PersistenceSafety.save(modelContext)
    }

    private func removeTodo() {
        guard !isDeleting else { return }
        isDeleting = true
        todo.isDone = false
        todo.isRemoved = true
        todo.completedAt = .now
        _ = PersistenceSafety.save(modelContext)
        removed(todo)
    }

    private func moveToAgenda(on date: Date) {
        let cleanText = todo.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            showMoveToAgenda = false
            return
        }

        let agendaEntry = DayEntry(
            date: date,
            rawText: cleanText,
            source: .todo
        )
        let undo = TodoAgendaMoveUndo(
            entryID: agendaEntry.id,
            destinationDate: AppCalendar.startOfDay(date),
            text: cleanText,
            bucketRawValue: todo.bucketRawValue,
            showOnWidget: todo.showOnWidget,
            createdAt: todo.createdAt
        )

        modelContext.insert(agendaEntry)
        movePerformed(todo.id)
        modelContext.delete(todo)
        _ = PersistenceSafety.save(modelContext)
        movedToAgenda(undo)
        showMoveToAgenda = false
    }
}

private struct NewTodoLine: View {
    let groupID: String
    let highlightsField: Bool
    let highlightsPlus: Bool
    let tutorialInputCommand: TodoTutorialInputCommand?
    let minimumCharacterCount: Int
    let requiresPlusToSubmit: Bool
    let textChanged: (String) -> Void
    let todoAdded: (UUID) -> Void
    let focusChanged: (Bool) -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""
    @State private var textFieldResetToken = 0
    @State private var suppressFocusCommit = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                beginEditing()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nieuwe taak invoeren")

            TextField("typ iets", text: $text, axis: .vertical)
                .id(textFieldResetToken)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: text.isEmpty ? 24 : nil, alignment: .top)
                .foregroundStyle(.primary)
                .submitLabel(.done)
                .onChange(of: text) { _, newValue in
                    textChanged(newValue)
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    guard !requiresPlusToSubmit else { return }
                    finishTodoAndDismissKeyboard()
                }
                .onSubmit {
                    guard !requiresPlusToSubmit else { return }
                    finishTodoAndDismissKeyboard()
                }
                .onChange(of: isTextFieldFocused) { wasFocused, isFocused in
                    focusChanged(isFocused)
                    guard wasFocused,
                          !isFocused,
                          !requiresPlusToSubmit,
                          !suppressFocusCommit else { return }
                    addTodo()
                }
                .onChange(of: tutorialInputCommand) { _, command in
                    guard let command else { return }
                    if let commandText = command.text {
                        text = commandText
                    }
                    if command.submitsCurrentText {
                        addTodo()
                    }
                    if command.focusesField {
                        beginEditing()
                    } else {
                        isTextFieldFocused = false
                        AppKeyboard.dismiss()
                    }
                }

            Button {
                addTodo()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .offset(x: -6)
            .opacity(cleanText.count >= minimumCharacterCount ? 1 : 0)
            .overlay {
                if highlightsPlus {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.brandHardBlue, lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay {
            if highlightsField {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.brandHardBlue, lineWidth: 3)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            focusChanged(false)
        }
    }

    private func addTodo() {
        let normalizedText = cleanText

        guard normalizedText.count >= minimumCharacterCount else {
            return
        }

        suppressFocusCommit = true
        let shouldRestoreFocus = isTextFieldFocused
        let todo = TodoItem(text: normalizedText)
        todo.bucketRawValue = groupID

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            text = ""
            textFieldResetToken &+= 1
            modelContext.insert(todo)
            _ = PersistenceSafety.save(modelContext)
        }
        todoAdded(todo.id)

        Task { @MainActor in
            await Task.yield()
            text = ""
            if shouldRestoreFocus {
                isTextFieldFocused = true
            }
            suppressFocusCommit = false
        }
    }

    private var cleanText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishTodoAndDismissKeyboard() {
        isTextFieldFocused = false
        AppKeyboard.dismiss()
        addTodo()
    }

    private func beginEditing() {
        Task { @MainActor in
            await Task.yield()
            isTextFieldFocused = true
        }
    }
}

@available(iOS 18.0, *)
private struct TodoSelectionTextField: View {
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

private struct NewTodoGroupLine: View {
    @Binding var text: String
    let add: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                beginEditing()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nieuwe categorie invoeren")

            TextField("Nieuwe groep", text: $text, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1...)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    addAndDismissKeyboard()
                }
                .onSubmit {
                    addAndDismissKeyboard()
                }

            Button(action: addAndDismissKeyboard) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
        .padding(.leading, 18)
        .padding(.trailing, 13)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func beginEditing() {
        Task { @MainActor in
            await Task.yield()
            isTextFieldFocused = true
        }
    }

    private func addAndDismissKeyboard() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        add()
        isTextFieldFocused = false
        AppKeyboard.dismiss()
    }
}

private enum TodoAge {
    static func daysOpen(since date: Date) -> Int {
        daysBetween(date, .now)
    }

    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        let startOfStart = AppCalendar.startOfDay(start)
        let startOfEnd = AppCalendar.startOfDay(end)
        return max(0, AppCalendar.calendar.dateComponents(
            [.day],
            from: startOfStart,
            to: startOfEnd
        ).day ?? 0)
    }
}
