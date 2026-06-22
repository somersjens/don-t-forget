import SwiftUI
import SwiftData

struct TodoView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.undoManager)
    private var undoManager

    @Query(sort: \TodoItem.createdAt, order: .forward)
    private var todos: [TodoItem]

    @State private var isScrolled = false
    @State private var isKeyboardVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    TodoBucketCard(
                        title: "Today",
                        icon: "sun.max",
                        bucket: .today,
                        todos: todosFor(.today)
                    )

                    TodoBucketCard(
                        title: "Short term",
                        icon: "bolt",
                        bucket: .shortTerm,
                        todos: todosFor(.shortTerm)
                    )

                    TodoBucketCard(
                        title: "Long term",
                        icon: "mountain.2",
                        bucket: .longTerm,
                        todos: todosFor(.longTerm)
                    )
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

    private func todosFor(_ bucket: TodoBucket) -> [TodoItem] {
        todos
            .filter { $0.bucket == bucket }
            .sorted {
                if $0.isDone != $1.isDone {
                    return !$0.isDone
                }

                return $0.createdAt < $1.createdAt
            }
    }
}

struct TodoBucketCard: View {
    let title: String
    let icon: String
    let bucket: TodoBucket
    let todos: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(todos) { todo in
                    TodoLine(todo: todo)
                }

                NewTodoLine(bucket: bucket)
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

struct TodoLine: View {
    @Bindable var todo: TodoItem

    @Environment(\.modelContext)
    private var modelContext

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                todo.toggleDone()
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            TextField("", text: $todo.text, axis: .vertical)
                .font(.system(size: 15, design: .monospaced))
                .textFieldStyle(.plain)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? .secondary : .primary)

            Menu {
                Button {
                    todo.bucket = .today
                } label: {
                    Label("Today", systemImage: "sun.max")
                }

                Button {
                    todo.bucket = .shortTerm
                } label: {
                    Label("Short term", systemImage: "bolt")
                }

                Button {
                    todo.bucket = .longTerm
                } label: {
                    Label("Long term", systemImage: "mountain.2")
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                todo.showOnWidget.toggle()
            } label: {
                Image(systemName: todo.showOnWidget ? "iphone.gen3" : "iphone.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                modelContext.delete(todo)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct NewTodoLine: View {
    let bucket: TodoBucket

    @Environment(\.modelContext)
    private var modelContext

    @State private var text = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("typ iets", text: $text, axis: .vertical)
                .font(.system(size: 15, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
                .onSubmit {
                    addTodo()
                }

            Button {
                addTodo()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 11))
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

        let todo = TodoItem(
            text: cleanText,
            bucket: bucket
        )

        modelContext.insert(todo)
        text = ""
    }
}
