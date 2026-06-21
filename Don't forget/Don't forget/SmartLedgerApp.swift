import SwiftUI
import SwiftData

@main
struct SmartLedgerApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            DayEntry.self,
            TodoItem.self,
            RecurringItem.self
        ])
    }
}
