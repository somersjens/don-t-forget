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
    static let shortTermID = TodoBucket.shortTerm.rawValue
    static let longTermID = TodoBucket.longTerm.rawValue

    static var defaults: [TodoGroup] {
        [
            TodoGroup(id: todayID, title: "Today", icon: "sun.max", colorRawValue: RecurringThemeColorOption.yellow.rawValue),
            TodoGroup(id: shortTermID, title: "Short term", icon: "bolt", colorRawValue: RecurringThemeColorOption.blue.rawValue),
            TodoGroup(id: longTermID, title: "Long term", icon: "mountain.2", colorRawValue: RecurringThemeColorOption.green.rawValue)
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
        var result: [TodoGroup] = []
        var seen: Set<String> = []

        for group in groups {
            let id = group.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id), result.count < maxCount else {
                continue
            }

            let fallback = defaults.first { $0.id == id }
            let title = group.trimmedTitle.isEmpty ? fallback?.title ?? "Nieuw" : group.trimmedTitle
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
            result = [defaults[0]]
        }

        return result
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

struct TodoView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.undoManager)
    private var undoManager

    @Query(sort: \TodoItem.createdAt, order: .forward)
    private var todos: [TodoItem]

    @State private var isScrolled = false
    @State private var isKeyboardVisible = false
    @State private var newGroupTitle = ""
    @State private var recentlyCompletedTodoID: UUID?
    @State private var dismissUndoTask: Task<Void, Never>?

    @AppStorage(SettingsKeys.todoGroups) private var todoGroupsData = ""

    private var groups: [TodoGroup] {
        get { TodoGroupStore.decode(todoGroupsData) }
        nonmutating set { todoGroupsData = TodoGroupStore.encode(newValue) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        let groupTodos = todosFor(group.id)
                        let firstNonemptyGroupID = groups.first {
                            !todosFor($0.id).isEmpty
                        }?.id
                        TodoBucketCard(
                            group: group,
                            groups: groups,
                            todos: groupTodos,
                            showsReorderHint: group.id == firstNonemptyGroupID,
                            canMoveUp: index > 0,
                            canMoveDown: index < groups.count - 1,
                            canDeleteGroup: groups.count > 1 && !todos.contains(where: {
                                $0.bucketRawValue == group.id && !$0.isDone
                            }),
                            rename: { renameGroup(group.id, to: $0) },
                            changeColor: { changeGroupColor(group.id, to: $0) },
                            changeIcon: { changeGroupIcon(group.id, to: $0) },
                            delete: { deleteGroup(group.id) },
                            moveUp: { moveGroup(from: index, direction: -1) },
                            moveDown: { moveGroup(from: index, direction: 1) },
                            completed: showCompletionUndo
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
                HStack {
                    Text("To-do")
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
                            AppKeyboard.dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .disabled(!isKeyboardVisible)
                        .accessibilityLabel("Toetsenbord sluiten")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if recentlyCompletedTodoID != nil {
                    completionUndoBar
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                modelContext.undoManager = undoManager
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
        }
    }

    private func todosFor(_ groupID: String) -> [TodoItem] {
        todos
            .filter { $0.bucketRawValue == groupID && !$0.isDone }
            .sorted { $0.createdAt < $1.createdAt }
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

        withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
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
              !todos.contains(where: { $0.bucketRawValue == id && !$0.isDone }) else {
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
        withAnimation(.snappy(duration: 0.25)) {
            recentlyCompletedTodoID = todo.id
        }
        dismissUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyCompletedTodoID = nil
            }
        }
    }

    private func undoCompletion() {
        guard let id = recentlyCompletedTodoID,
              let todo = todos.first(where: { $0.id == id }) else { return }
        todo.isDone = false
        todo.completedAt = nil
        try? modelContext.save()
        dismissUndoTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            recentlyCompletedTodoID = nil
        }
    }

    private var completionUndoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("To-do verplaatst naar History")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
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
    let showsReorderHint: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDeleteGroup: Bool
    let rename: (String) -> Void
    let changeColor: (String) -> Void
    let changeIcon: (String) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let completed: (TodoItem) -> Void
    @State private var showingAppearancePicker = false
    @State private var showingCategoryActions = false

    private var canDelete: Bool {
        canDeleteGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    TextField("Groep", text: Binding(
                        get: { group.title },
                        set: { rename($0) }
                    ))
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

            Divider()
                .overlay(Color.primary.opacity(0.07))
                .padding(.leading, 45)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                    TodoLine(
                        todo: todo,
                        groups: groups,
                        color: group.color,
                        showsReorderHint: showsReorderHint && index == 0,
                        completed: completed
                    )
                }

                NewTodoLine(groupID: group.id)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 14)
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
        .confirmationDialog(
            "Categorie aanpassen",
            isPresented: $showingCategoryActions,
            titleVisibility: .hidden
        ) {
            Button(action: moveUp) {
                Label("Omhoog verplaatsen", systemImage: "arrow.up")
            }
            .disabled(!canMoveUp)

            Button(action: moveDown) {
                Label("Omlaag verplaatsen", systemImage: "arrow.down")
            }
            .disabled(!canMoveDown)

            if canDelete {
                Button(role: .destructive, action: delete) {
                    Label("Categorie verwijderen", systemImage: "trash")
                }
            }

            Button("Annuleer", role: .cancel) {}
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
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .animation(nil, value: canMoveUp)
        .animation(nil, value: canMoveDown)
        .animation(nil, value: canDelete)
    }

    private var openCountText: String {
        todos.count == 1 ? "1 open" : "\(todos.count) open"
    }
}

private struct TodoGroupAppearancePicker: View {
    @Environment(\.dismiss) private var dismiss
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
                                        Text(option.title)
                                            .font(.caption)
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
    let showsReorderHint: Bool
    let completed: (TodoItem) -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State private var showMoveToAgenda = false
    @State private var agendaDate = AppCalendar.startOfDay(.now)
    @State private var showingReorderHint = false
    @State private var isDeleting = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            moveMenu

            TextField("", text: $todo.text, axis: .vertical)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? .secondary : .primary)
                .submitLabel(.done)
                .onChange(of: todo.text) { _, newValue in
                    if newValue.contains("\n") {
                        todo.text = newValue.replacingOccurrences(of: "\n", with: " ")
                        AppKeyboard.dismiss()
                    } else if newValue.isEmpty {
                        deleteTodo()
                    }
                }
                .onSubmit {
                    AppKeyboard.dismiss()
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
        .task(id: showsReorderHint) {
            guard showsReorderHint else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { showingReorderHint = true }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { showingReorderHint = false }
            }
        }
        .sheet(isPresented: $showMoveToAgenda) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Datum",
                        selection: $agendaDate,
                        displayedComponents: .date
                    )
                }
                .navigationTitle("Naar agenda")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") {
                            showMoveToAgenda = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verplaats") {
                            moveToAgenda()
                        }
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
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
                agendaDate = AppCalendar.startOfDay(.now)
                showMoveToAgenda = true
            } label: {
                Label("Naar agenda...", systemImage: "calendar.badge.plus")
            }
        } label: {
            Group {
                if showingReorderHint && showsReorderHint {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Text(ageBadgeText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.14), in: Capsule())
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .foregroundStyle(color)
            .frame(width: 36, height: 24, alignment: .center)
        }
        .accessibilityLabel("\(accessibleAgeText), to-do verplaatsen")
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

    private func deleteTodo() {
        guard !isDeleting else { return }
        isDeleting = true
        Task { @MainActor in
            await Task.yield()
            modelContext.delete(todo)
            try? modelContext.save()
        }
    }

    private func moveToAgenda() {
        let cleanText = todo.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            showMoveToAgenda = false
            return
        }

        let agendaEntry = DayEntry(
            date: agendaDate,
            rawText: cleanText,
            source: .todo
        )

        modelContext.insert(agendaEntry)
        modelContext.delete(todo)
        try? modelContext.save()
        showMoveToAgenda = false
    }
}

private struct NewTodoLine: View {
    let groupID: String

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "plus.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 24)

            TextField("typ iets", text: $text, axis: .vertical)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .foregroundStyle(.primary)
                .submitLabel(.done)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: " ")
                    addTodo()
                    AppKeyboard.dismiss()
                }
                .onSubmit {
                    addTodo()
                    AppKeyboard.dismiss()
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
}

private struct NewTodoGroupLine: View {
    @Binding var text: String
    let add: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            TextField("Nieuwe groep", text: $text, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    add()
                }
                .onSubmit {
                    add()
                }

            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
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
