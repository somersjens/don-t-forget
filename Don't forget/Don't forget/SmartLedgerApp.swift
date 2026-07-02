import SwiftUI
import SwiftData

@main
struct SmartLedgerApp: App {
    var body: some Scene {
        WindowGroup {
            UndoLimitedRootView()
        }
        .modelContainer(for: [
            DayEntry.self,
            TodoItem.self,
            RecurringItem.self
        ])
    }
}

private struct UndoLimitedRootView: View {
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        RootTabView()
            .onAppear {
                undoManager?.levelsOfUndo = 3
            }
    }
}
