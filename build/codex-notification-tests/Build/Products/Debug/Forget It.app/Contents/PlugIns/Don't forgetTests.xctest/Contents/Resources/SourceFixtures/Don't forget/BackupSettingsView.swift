import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @State private var document: AppBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingRestore: AppBackupArchive?
    @State private var isConfirmingRestore = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button(action: exportBackup) {
                    Label(locale.localized("Volledige backup maken"), systemImage: "externaldrive.badge.plus")
                }
                .settingsCardRow(.first)

                Button {
                    isImporting = true
                } label: {
                    Label(locale.localized("Backupbestand terugzetten"), systemImage: "square.and.arrow.down")
                }
                .settingsCardRow(.middle)

                Button(action: prepareLatestSafetyRestore) {
                    Label(
                        locale.localized("Laatste veiligheidskopie terugzetten"),
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                }
                .settingsCardRow(.last)
            } footer: {
                Text(locale.localized("De backup bevat actieve en afgeronde items, herhalingen en instellingen. Voor een herstelactie wordt eerst nog een kopie van de huidige gegevens gemaakt."))
            }
        }
        .navigationTitle(locale.localized("Backup en herstel"))
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .json,
            defaultFilename: filename
        ) { result in
            switch result {
            case .success:
                message = locale.localized("Volledige backup bewaard.")
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: prepareRestore
        )
        .alert(locale.localized("Huidige gegevens vervangen?"), isPresented: $isConfirmingRestore) {
            Button(locale.localized("Annuleer"), role: .cancel) { pendingRestore = nil }
            Button(locale.localized("Zet backup terug"), role: .destructive, action: restorePendingBackup)
        } message: {
            Text(locale.localizedFormat(
                "De backup bevat %lld items. Er wordt eerst automatisch een veiligheidskopie gemaakt.",
                pendingRestore?.itemCount ?? 0
            ))
        }
        .alert(locale.localized("Backup"), isPresented: messageIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .alert(locale.localized("Backup mislukt"), isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var filename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Forget-It_backup_\(formatter.string(from: .now))"
    }

    private func exportBackup() {
        do {
            document = AppBackupDocument(archive: try AppBackupService.makeArchive(from: modelContext))
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareRestore(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try AppBackupService.decode(Data(contentsOf: url))
            isConfirmingRestore = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareLatestSafetyRestore() {
        do {
            guard let archive = try AppBackupService.latestAutomaticSnapshot() else {
                message = locale.localized("Er is nog geen automatische veiligheidskopie beschikbaar.")
                return
            }
            pendingRestore = archive
            isConfirmingRestore = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePendingBackup() {
        guard let archive = pendingRestore else { return }
        do {
            try AppBackupService.restore(archive, into: modelContext)
            pendingRestore = nil
            message = locale.localized("Backup teruggezet. Heropen de app om alle instellingen opnieuw te laden.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
