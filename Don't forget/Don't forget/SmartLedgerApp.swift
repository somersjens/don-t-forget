import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
                StoreRootView()
            } else {
                WelcomeView()
            }
        }
    }
}

private struct StoreRootView: View {
    @State private var loadResult = AppModelStore.load()
    @State private var recoveryDocument: AppBackupDocument?
    @State private var isExportingRecoveryBackup = false
    @State private var recoveryMessage: String?

    var body: some View {
        Group {
            switch loadResult {
            case .success(let container):
                UndoLimitedRootView()
                    .modelContainer(container)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Gegevens niet geopend", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Je gegevens zijn niet verwijderd. Sluit de app niet opnieuw af en installeer hem niet opnieuw. Probeer het nogmaals of neem contact op met support.\n\n\(error.localizedDescription)")
                } actions: {
                    VStack(spacing: 12) {
                        Button("Opnieuw proberen") {
                            loadResult = AppModelStore.retryAfterFailure()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Laatste veiligheidskopie bewaren") {
                            exportLatestSafetyBackup()
                        }
                    }
                }
                .padding()
            }
        }
        .fileExporter(
            isPresented: $isExportingRecoveryBackup,
            document: recoveryDocument,
            contentType: .json,
            defaultFilename: "Dont-forget_recovery-backup"
        ) { result in
            if case .failure(let error) = result {
                recoveryMessage = error.localizedDescription
            }
        }
        .alert("Veiligheidskopie", isPresented: recoveryMessageIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryMessage ?? "")
        }
    }

    private var recoveryMessageIsPresented: Binding<Bool> {
        Binding(
            get: { recoveryMessage != nil },
            set: { if !$0 { recoveryMessage = nil } }
        )
    }

    private func exportLatestSafetyBackup() {
        do {
            guard let archive = try AppBackupService.latestAutomaticSnapshot() else {
                recoveryMessage = "Er is nog geen automatische veiligheidskopie beschikbaar."
                return
            }
            recoveryDocument = AppBackupDocument(archive: archive)
            isExportingRecoveryBackup = true
        } catch {
            recoveryMessage = error.localizedDescription
        }
    }
}

private struct UndoLimitedRootView: View {
    @Environment(\.undoManager) private var undoManager
    @State private var persistenceError: String?

    var body: some View {
        RootTabView()
            .onAppear {
                undoManager?.levelsOfUndo = 3
            }
            .onReceive(NotificationCenter.default.publisher(for: .persistenceSaveFailed)) { note in
                persistenceError = note.userInfo?[PersistenceSafety.errorUserInfoKey] as? String
                    ?? "De wijziging kon niet worden bewaard."
            }
            .alert(
                "Bewaren mislukt",
                isPresented: Binding(
                    get: { persistenceError != nil },
                    set: { if !$0 { persistenceError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceError ?? "")
            }
    }
}
