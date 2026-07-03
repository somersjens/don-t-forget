import SwiftUI
import SwiftData

@main
@MainActor
struct SmartLedgerApp: App {
    @AppStorage(SettingsKeys.hasCompletedWelcome)
    private var hasCompletedWelcome = false

    init() {
        EndOfDayReminderService.configureNotificationPresentation()
        if AppModelStore.isICloudSyncEnabled {
            CloudSettingsSynchronizer.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedWelcome {
                UndoLimitedRootView()
                    .modelContainer(AppModelStore.shared)
            } else {
                WelcomeView()
            }
        }
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
