import SwiftUI
import SwiftData

struct TodoGroup: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var icon: String

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
            TodoGroup(id: todayID, title: "Today", icon: "sun.max"),
            TodoGroup(id: shortTermID, title: "Short term", icon: "bolt"),
            TodoGroup(id: longTermID, title: "Long term", icon: "mountain.2")
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

            result.append(TodoGroup(id: id, title: title, icon: icon))
            seen.insert(id)
        }

        if result.isEmpty {
            result = [defaults[0]]
        }

        return result
    }
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
    @State private var reorderingGroupID: String?

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
                        TodoBucketCard(
                            group: group,
                            groups: groups,
                            todos: groupTodos,
                            canMoveUp: index > 0,
                            canMoveDown: index < groups.count - 1,
                            isReordering: reorderingGroupID != nil,
                            rename: { renameGroup(group.id, to: $0) },
                            delete: { deleteGroup(group.id) },
                            moveUp: { moveGroup(from: index, direction: -1) },
                            moveDown: { moveGroup(from: index, direction: 1) }
                        )
                        .zIndex(reorderingGroupID == group.id ? 1 : 0)
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
            .filter { $0.bucketRawValue == groupID }
            .sorted {
                if $0.isDone != $1.isDone {
                    return !$0.isDone
                }

                if $0.isDone {
                    return ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
                }

                return $0.createdAt < $1.createdAt
            }
    }

    private func renameGroup(_ id: String, to title: String) {
        var updated = groups
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].title = title
        groups = updated
    }

    private func moveGroup(from index: Int, direction: Int) {
        var updated = groups
        let target = index + direction
        guard updated.indices.contains(index), updated.indices.contains(target) else { return }

        let movingID = updated[index].id
        updated.swapAt(index, target)
        reorderingGroupID = movingID

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            groups = updated
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            if reorderingGroupID == movingID {
                reorderingGroupID = nil
            }
        }
    }

    private func addGroup() {
        let title = newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, groups.count < TodoGroupStore.maxCount else { return }

        var updated = groups
        updated.append(TodoGroup(
            id: UUID().uuidString,
            title: title,
            icon: "list.bullet"
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
        groups = updated
        try? modelContext.save()
    }
}

private struct TodoBucketCard: View {
    let group: TodoGroup
    let groups: [TodoGroup]
    let todos: [TodoItem]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isReordering: Bool
    let rename: (String) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    private var openTodos: [TodoItem] {
        todos.filter { !$0.isDone }
    }

    private var oldestOpenTodo: TodoItem? {
        openTodos.min { $0.createdAt < $1.createdAt }
    }

    private var canDelete: Bool {
        groups.count > 1 && todos.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: group.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Groep", text: Binding(
                        get: { group.title },
                        set: { rename($0) }
                    ))
                    .font(.system(size: 17, weight: .semibold))
                    .textFieldStyle(.plain)

                    Text(bucketSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                actionToolbar
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(todos) { todo in
                    TodoLine(todo: todo, groups: groups)
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
    }

    private func cardIconButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
    }

    private var actionToolbar: some View {
        HStack(spacing: 0) {
            cardIconButton(systemName: "chevron.up", isEnabled: canMoveUp, action: moveUp)
            cardIconButton(systemName: "chevron.down", isEnabled: canMoveDown, action: moveDown)

            Button(role: canDelete ? .destructive : nil, action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .foregroundStyle(canDelete ? Color.secondary : Color.secondary.opacity(0.35))
            .accessibilityLabel(canDelete ? "Groep verwijderen" : "Groep bevat nog to-do's")
        }
        .padding(2)
        .frame(width: 88, alignment: .trailing)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .animation(nil, value: canMoveUp)
        .animation(nil, value: canMoveDown)
        .animation(nil, value: canDelete)
        .allowsHitTesting(!isReordering)
    }

    private var bucketSummary: String {
        guard !openTodos.isEmpty else {
            return "leeg"
        }

        let countText = openTodos.count == 1 ? "1 open" : "\(openTodos.count) open"

        guard let oldestOpenTodo else {
            return countText
        }

        let age = TodoAge.daysOpen(since: oldestOpenTodo.createdAt)
        if age == 0 {
            return "\(countText) · vandaag"
        }

        return "\(countText) · oudste \(age)d"
    }
}

private struct TodoLine: View {
    @Bindable var todo: TodoItem
    let groups: [TodoGroup]

    @Environment(\.modelContext)
    private var modelContext

    @State private var showMoveToAgenda = false
    @State private var agendaDate = AppCalendar.startOfDay(.now)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            moveMenu

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: $todo.text, axis: .vertical)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .lineLimit(1...)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)

                Text(ageText)
                    .font(.system(size: 12))
                    .foregroundStyle(ageColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Button {
                todo.toggleDone()
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
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
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    private var ageText: String {
        if todo.isDone {
            let days = TodoAge.daysBetween(todo.createdAt, todo.completedAt ?? .now)
            return days == 0 ? "vandaag afgerond" : "afgerond na \(days)d"
        }

        let days = TodoAge.daysOpen(since: todo.createdAt)
        return days == 0 ? "vandaag aangemaakt" : "\(days)d open"
    }

    private var ageColor: Color {
        guard !todo.isDone else {
            return .secondary
        }

        let days = TodoAge.daysOpen(since: todo.createdAt)
        if days >= 14 {
            return .orange
        }

        if days >= 7 {
            return Color(red: 0.72, green: 0.53, blue: 0.02)
        }

        return .secondary
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)

            TextField("typ iets", text: $text, axis: .vertical)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .foregroundStyle(.secondary)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else {
                        return
                    }

                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    addTodo()
                }
                .onSubmit {
                    addTodo()
                }

            Button {
            addTodo()
        } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
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
