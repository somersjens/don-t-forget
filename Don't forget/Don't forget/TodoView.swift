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

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
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
                title = fallback?.title ?? AppCalendar.locale.localized("Nieuw", "New")
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

    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""

    private var groups: [TodoGroup] {
        get { TodoGroupStore.decode(todoGroupsData) }
        nonmutating set { todoGroupsData = TodoGroupStore.encode(newValue) }
    }

    var body: some View {
        let activeTodosByGroup = Dictionary(
            grouping: todos,
            by: \.bucketRawValue
        )
        let hintSequence = groups.flatMap { activeTodosByGroup[$0.id] ?? [] }

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        let groupTodos = activeTodosByGroup[group.id] ?? []
                        TodoBucketCard(
                            group: group,
                            groups: groups,
                            todos: groupTodos,
                            canMoveUp: index > 0,
                            canMoveDown: index < groups.count - 1,
                            canDeleteGroup: groups.count > 1 && !todos.contains(where: {
                                $0.bucketRawValue == group.id
                            }),
                            rename: { renameGroup(group.id, to: $0) },
                            changeColor: { changeGroupColor(group.id, to: $0) },
                            changeIcon: { changeGroupIcon(group.id, to: $0) },
                            delete: { deleteGroup(group.id) },
                            moveUp: { moveGroup(from: index, direction: -1) },
                            moveDown: { moveGroup(from: index, direction: 1) },
                            activeReorderHintIDs: activeReorderHintIDs,
                            completed: showCompletionUndo,
                            removed: showRemovalUndo,
                            movedToAgenda: showMoveToAgendaUndo
                        )
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
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 12
            } action: { _, newValue in
                isScrolled = newValue
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    Text(AppSection.todo.title(for: locale))
                        .font(.system(size: 26, weight: .bold))
                        .opacity(isScrolled ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: isScrolled)

                    HStack {
                        Button {
                            undoManager?.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(!(undoManager?.canUndo ?? false))
                        .accessibilityLabel("Laatste wijziging terugdraaien")

                        Spacer()

                        Button {
                            AppKeyboard.dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(!isKeyboardVisible)
                        .accessibilityLabel("Toetsenbord sluiten")
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 18)
                .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
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
            try? modelContext.save()
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
        try? modelContext.save()
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
        try? modelContext.save()
        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyRemovedTodo = nil
        }
    }

    private var removalUndoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)
            Text("‘\(recentlyRemovedTodoTitle)’ verwijderd")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Ongedaan maken", action: undoRemoval)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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
        try? modelContext.save()

        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyMovedToAgenda = nil
        }
    }

    private var moveToAgendaUndoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.blue)
            Text(moveToAgendaUndoText)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Ongedaan maken", action: undoMoveToAgenda)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var moveToAgendaUndoText: String {
        guard let move = recentlyMovedToAgenda else { return "" }
        let date = AppCalendar.localizedDate(move.destinationDate, template: "dMMM")
        return "‘\(move.text)’ verplaatst naar \(date)"
    }

    private func undoCompletion() {
        guard let todo = recentlyCompletedTodo else { return }
        todo.isDone = false
        todo.completedAt = nil
        try? modelContext.save()
        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyCompletedTodo = nil
        }
    }

    private var completionUndoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Taak verplaatst\nnaar History")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Button("Ongedaan maken", action: undoCompletion)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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
    let activeReorderHintIDs: Set<UUID>
    let completed: (TodoItem) -> Void
    let removed: (TodoItem) -> Void
    let movedToAgenda: (TodoAgendaMoveUndo) -> Void
    @State private var showingAppearancePicker = false
    @State private var showingCategoryActions = false

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
                            .fill(group.color.opacity(0.18))
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
                        isReorderHintActive: activeReorderHintIDs.contains(todo.id),
                        completed: completed,
                        removed: removed,
                        movedToAgenda: movedToAgenda
                    )
                }

                NewTodoLine(groupID: group.id)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
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
    let isReorderHintActive: Bool
    let completed: (TodoItem) -> Void
    let removed: (TodoItem) -> Void
    let movedToAgenda: (TodoAgendaMoveUndo) -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var showMoveToAgenda = false
    @State private var agendaDate = AppCalendar.startOfDay(.now)
    @State private var isDeleting = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            moveMenu

            TextField("", text: $todo.text, axis: .vertical)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? .secondary : .primary)
                .submitLabel(.done)
                .onChange(of: todo.text) { _, newValue in
                    let normalizedText = newValue.replacingOccurrences(of: "\n", with: "")
                    if normalizedText != newValue {
                        todo.text = normalizedText
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
                try? modelContext.save()
                if todo.isDone {
                    completed(todo)
                }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .frame(width: 36, height: 24)
            }
            .buttonStyle(.plain)
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

    private var moveMenu: some View {
        Menu {
            ForEach(groups) { group in
                Button {
                    todo.bucketRawValue = group.id
                } label: {
                    Label(group.title, systemImage: group.icon)
                }
            }

            Divider()

            Button {
                moveToAgenda(on: AppCalendar.startOfDay(.now))
            } label: {
                Label("Naar vandaag \(todayDateText)", systemImage: "calendar.badge.checkmark")
            }

            Button {
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
                            .fill(color.opacity(0.14))
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
                        .background(color.opacity(0.14), in: Capsule())
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
        }
        .accessibilityLabel("\(accessibleAgeText), taak verplaatsen")
    }

    private var ageBadgeText: String {
        let days = TodoAge.daysOpen(since: todo.createdAt)
        if days == 0 { return "nu" }
        if days < 14 { return "\(days)d" }
        if days < 70 { return "\(days / 7)w" }
        return "\(days / 30)m"
    }

    private var accessibleAgeText: String {
        let days = TodoAge.daysOpen(since: todo.createdAt)
        return days == 0 ? "Vandaag aangemaakt" : "\(days) dagen open"
    }

    private var todayDateText: String {
        let formatter = DateFormatter()
        formatter.calendar = AppCalendar.calendar
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: .now)
    }

    private func deleteTodo() {
        guard !isDeleting else { return }
        isDeleting = true
        modelContext.delete(todo)
        try? modelContext.save()
    }

    private func removeTodo() {
        guard !isDeleting else { return }
        isDeleting = true
        todo.isDone = false
        todo.isRemoved = true
        todo.completedAt = .now
        try? modelContext.save()
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
        modelContext.delete(todo)
        try? modelContext.save()
        movedToAgenda(undo)
        showMoveToAgenda = false
    }
}

private struct NewTodoLine: View {
    let groupID: String

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""
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
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
                .submitLabel(.done)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    addTodoAndDismissKeyboard()
                }
                .onSubmit {
                    addTodoAndDismissKeyboard()
                }
                .onChange(of: isTextFieldFocused) { wasFocused, isFocused in
                    guard wasFocused, !isFocused else { return }
                    addTodo()
                }

            Button {
                addTodo()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 24)
            }
            .buttonStyle(.plain)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
    }

    private func addTodo() {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            return
        }

        let todo = TodoItem(text: cleanText)
        todo.bucketRawValue = groupID

        modelContext.insert(todo)
        try? modelContext.save()
        text = ""
    }

    private func addTodoAndDismissKeyboard() {
        addTodo()
        isTextFieldFocused = false
        AppKeyboard.dismiss()
    }

    private func beginEditing() {
        Task { @MainActor in
            await Task.yield()
            isTextFieldFocused = true
        }
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
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
