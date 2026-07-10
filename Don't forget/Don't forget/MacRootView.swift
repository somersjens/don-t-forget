#if os(macOS)
import AppKit
import CloudKit
import SwiftData
import SwiftUI

extension Notification.Name {
    static let macCreateItem = Notification.Name("mac.createItem")
    static let macUndoAgendaAction = Notification.Name("mac.undoAgendaAction")
}

enum MacSection: String, CaseIterable, Identifiable {
    case agenda, todo, recurring, history

    var id: Self { self }
    var title: String {
        switch self {
        case .agenda: "Agenda"
        case .todo: "Taken"
        case .recurring: "Terugkerend"
        case .history: "Afgerond"
        }
    }
    var icon: String {
        switch self {
        case .agenda: "calendar"
        case .todo: "checklist"
        case .recurring: "repeat"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct MacRootView: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query private var dayEntries: [DayEntry]
    @Query private var todos: [TodoItem]
    @Query private var recurringItems: [RecurringItem]

    @State private var section: MacSection = .agenda
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var persistenceError: String?
    @State private var hasAppliedInitialWindowSize = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            itemList

            bottomNavigation
        }
        .frame(minWidth: 480, minHeight: 520)
        .onAppear(perform: applyInitialWindowSize)
        .inspector(isPresented: inspectorPresented) {
            detail
                .inspectorColumnWidth(min: 300, ideal: 350, max: 440)
        }
        .onChange(of: section) { _, _ in selection = nil }
        .onReceive(NotificationCenter.default.publisher(for: .macCreateItem)) { _ in
            createItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .persistenceSaveFailed)) { note in
            persistenceError = note.userInfo?[PersistenceSafety.errorUserInfoKey] as? String
        }
        .alert("Bewaren mislukt", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "")
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { if !$0 { selection = nil } }
        )
    }

    private func applyInitialWindowSize() {
        guard !hasAppliedInitialWindowSize else { return }
        hasAppliedInitialWindowSize = true
        Task { @MainActor in
            await Task.yield()
            guard let window = NSApp.keyWindow else { return }
            window.setContentSize(NSSize(width: 480, height: max(520, window.contentLayoutRect.height)))
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Text(section.title)
                .font(.title2.bold())

            Spacer()

            TextField("Zoeken", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 440)

            Button(action: finishEditing) {
                Label("Bewerken afsluiten", systemImage: "return")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .help("Bewerken afsluiten")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func finishEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if section == .agenda {
            NotificationCenter.default.post(name: .macUndoAgendaAction, object: nil)
        } else {
            selection = nil
        }
    }

    private var bottomNavigation: some View {
        HStack(spacing: 8) {
            ForEach(MacSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(item.title)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(section == item ? Color.white : Color.primary.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .background(
                        section == item ? Color.brandHardBlue : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var itemList: some View {
        switch section {
        case .agenda:
            MacCalendarView(entries: agendaItems, selection: $selection)
        case .todo:
            List(todoItems, selection: $selection) { todo in
                MacTodoRow(todo: todo).tag(todo.id)
            }
            .overlay { emptyState(todoItems.isEmpty, "Geen taken", "checklist") }
        case .recurring:
            List(activeRecurringItems, selection: $selection) { item in
                MacRecurringRow(item: item).tag(item.id)
            }
            .overlay { emptyState(activeRecurringItems.isEmpty, "Geen terugkerende items", "repeat") }
        case .history:
            List(selection: $selection) {
                if !historyDayEntries.isEmpty {
                    Section("Agenda") {
                        ForEach(historyDayEntries) { entry in
                            MacAgendaRow(entry: entry).tag(entry.id)
                        }
                    }
                }
                if !historyTodos.isEmpty {
                    Section("Taken") {
                        ForEach(historyTodos) { todo in
                            MacTodoRow(todo: todo).tag(todo.id)
                        }
                    }
                }
            }
            .overlay {
                emptyState(historyDayEntries.isEmpty && historyTodos.isEmpty, "Nog niets afgerond", "clock")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = dayEntries.first(where: { $0.id == selection }) {
            MacDayEntryEditor(entry: entry)
        } else if let todo = todos.first(where: { $0.id == selection }) {
            MacTodoEditor(todo: todo)
        } else if let item = recurringItems.first(where: { $0.id == selection }) {
            MacRecurringEditor(item: item)
        } else {
            EmptyView()
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var agendaItems: [DayEntry] {
        dayEntries
            .filter { !$0.isDone && !$0.isRemoved && matches($0.rawText) }
            .sorted { ($0.date, $0.manualOrder) < ($1.date, $1.manualOrder) }
    }

    private var todoItems: [TodoItem] {
        todos
            .filter { !$0.isDone && !$0.isRemoved && matches($0.text) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeRecurringItems: [RecurringItem] {
        recurringItems
            .filter { !$0.isRemoved && matches($0.title + " " + $0.notes) }
            .sorted { $0.nextDate < $1.nextDate }
    }

    private var historyDayEntries: [DayEntry] {
        dayEntries
            .filter { ($0.isDone || $0.isRemoved) && matches($0.rawText) }
            .sorted { ($0.completedAt ?? $0.date) > ($1.completedAt ?? $1.date) }
    }

    private var historyTodos: [TodoItem] {
        todos
            .filter { ($0.isDone || $0.isRemoved) && matches($0.text) }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private func matches(_ value: String) -> Bool {
        normalizedSearch.isEmpty || value.localizedCaseInsensitiveContains(normalizedSearch)
    }

    @ViewBuilder
    private func emptyState(_ isEmpty: Bool, _ title: String, _ image: String) -> some View {
        if isEmpty {
            ContentUnavailableView.search(text: normalizedSearch)
                .opacity(normalizedSearch.isEmpty ? 0 : 1)
                .overlay {
                    if normalizedSearch.isEmpty {
                        ContentUnavailableView(title, systemImage: image)
                    }
                }
        }
    }

    private func createItem() {
        switch section {
        case .agenda:
            let item = DayEntry(date: .now)
            modelContext.insert(item)
            selection = item.id
        case .todo:
            let item = TodoItem()
            modelContext.insert(item)
            selection = item.id
        case .recurring:
            let item = RecurringItem(nextDate: .now)
            modelContext.insert(item)
            selection = item.id
        case .history:
            return
        }
        PersistenceSafety.save(modelContext)
    }

    private func removeSelection() {
        guard let selection else { return }
        if let item = dayEntries.first(where: { $0.id == selection }) {
            item.isRemoved = true
            item.completedAt = .now
        } else if let item = todos.first(where: { $0.id == selection }) {
            item.isRemoved = true
            item.completedAt = .now
        } else if let item = recurringItems.first(where: { $0.id == selection }) {
            item.isRemoved = true
            item.completedAt = .now
        }
        PersistenceSafety.save(modelContext)
        self.selection = nil
    }
}

private struct MacAgendaRow: View {
    let entry: DayEntry
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : "calendar")
                .foregroundStyle(entry.isDone ? .green : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.rawText.isEmpty ? "Nieuw agenda-item" : entry.rawText)
                    .lineLimit(2)
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MacTodoRow: View {
    let todo: TodoItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(todo.isDone ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text.isEmpty ? "Nieuwe taak" : todo.text).lineLimit(2)
                Text(todo.bucketRawValue).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MacRecurringRow: View {
    let item: RecurringItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Nieuw terugkerend item" : item.title).lineLimit(2)
                Text("Volgende: \(item.nextDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct MacDayEntryEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: DayEntry

    var body: some View {
        Form {
            Section("Agenda-item") {
                TextField("Omschrijving", text: $entry.rawText, axis: .vertical)
                DatePicker("Datum", selection: $entry.date, displayedComponents: .date)
                Toggle("Afgerond", isOn: $entry.isDone)
            }
            Section("Details") {
                LabeledContent("Aangemaakt", value: entry.createdAt.formatted())
                LabeledContent("Bron", value: entry.sourceRawValue)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.rawText.isEmpty ? "Nieuw agenda-item" : entry.rawText)
        .onChange(of: entry.rawText) { _, _ in entry.refreshParsedFields(); save() }
        .onChange(of: entry.date) { _, newValue in entry.date = AppCalendar.startOfDay(newValue); save() }
        .onChange(of: entry.isDone) { _, done in entry.completedAt = done ? .now : nil; save() }
    }
    private func save() { PersistenceSafety.save(modelContext) }
}

private struct MacTodoEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var todo: TodoItem

    var body: some View {
        Form {
            Section("Taak") {
                TextField("Omschrijving", text: $todo.text, axis: .vertical)
                Picker("Lijst", selection: $todo.bucketRawValue) {
                    Text("Vandaag").tag(TodoBucket.today.rawValue)
                    Text("Binnenkort").tag(TodoBucket.shortTerm.rawValue)
                    Text("Later").tag(TodoBucket.longTerm.rawValue)
                }
                Toggle("Afgerond", isOn: $todo.isDone)
            }
            Section("Details") {
                LabeledContent("Aangemaakt", value: todo.createdAt.formatted())
            }
        }
        .formStyle(.grouped)
        .navigationTitle(todo.text.isEmpty ? "Nieuwe taak" : todo.text)
        .onChange(of: todo.text) { _, _ in save() }
        .onChange(of: todo.bucketRawValue) { _, _ in save() }
        .onChange(of: todo.isDone) { _, done in todo.completedAt = done ? .now : nil; save() }
    }
    private func save() { PersistenceSafety.save(modelContext) }
}

private struct MacRecurringEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: RecurringItem

    var body: some View {
        Form {
            Section("Terugkerend item") {
                TextField("Naam", text: $item.title)
                DatePicker("Volgende datum", selection: $item.nextDate, displayedComponents: .date)
                TextField("Herhaling", text: $item.frequencyText)
                Picker("Categorie", selection: $item.themeRawValue) {
                    Text("Verjaardag").tag(RecurringTheme.birthday.rawValue)
                    Text("Algemeen").tag(RecurringTheme.general.rawValue)
                    Text("Persoonlijk").tag(RecurringTheme.personal.rawValue)
                }
            }
            Section("Notities") {
                TextEditor(text: $item.notes).frame(minHeight: 120)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.title.isEmpty ? "Nieuw terugkerend item" : item.title)
        .onChange(of: item.title) { _, _ in save() }
        .onChange(of: item.nextDate) { _, value in item.nextDate = AppCalendar.startOfDay(value); save() }
        .onChange(of: item.frequencyText) { _, _ in save() }
        .onChange(of: item.themeRawValue) { _, _ in save() }
        .onChange(of: item.notes) { _, _ in save() }
    }
    private func save() { PersistenceSafety.save(modelContext) }
}

struct MacCloudSettingsView: View {
    @State private var status: CKAccountStatus?

    var body: some View {
        Form {
            Section("iCloud") {
                LabeledContent("Synchronisatie") {
                    HStack {
                        Image(systemName: status == .available ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                            .foregroundStyle(status == .available ? .green : .orange)
                        Text(statusText)
                    }
                }
                Text("Deze Mac gebruikt dezelfde private iCloud-container als je iPhone en iPad. Wijzigingen worden automatisch op alle apparaten bijgewerkt.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 220)
        .task { status = await ICloudStatusService.accountStatus() }
    }

    private var statusText: String {
        switch status {
        case .available: "Actief"
        case .noAccount: "Geen iCloud-account"
        case .restricted: "Beperkt"
        case .temporarilyUnavailable: "Tijdelijk niet beschikbaar"
        case .couldNotDetermine: "Onbekend"
        case nil: "Controleren…"
        @unknown default: "Onbekend"
        }
    }
}
#endif
