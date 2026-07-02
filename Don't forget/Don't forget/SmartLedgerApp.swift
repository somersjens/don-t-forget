import SwiftUI
import SwiftData

@main
@MainActor
struct SmartLedgerApp: App {
    var body: some Scene {
        WindowGroup {
            UndoLimitedRootView()
        }
        .modelContainer(AppModelStore.shared)
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
