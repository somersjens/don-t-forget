import Foundation
import SwiftData

extension Notification.Name {
    static let persistenceSaveFailed = Notification.Name("persistence.saveFailed")
}

@MainActor
enum PersistenceSafety {
    static let errorUserInfoKey = "error"

    private static var pendingSaveTask: Task<Void, Never>?
    private static weak var pendingSaveContext: ModelContext?

    /// Saves a user-initiated change. Failed mutations are rolled back so the
    /// interface never keeps showing data that was not persisted.
    @discardableResult
    static func save(_ modelContext: ModelContext) -> Bool {
        // A directly requested save supersedes any coalesced one for the same
        // context; both would persist the identical pending change set.
        if pendingSaveContext === modelContext {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            pendingSaveContext = nil
        }
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            report(error)
            return false
        }
    }

    /// Coalesces bursts of small mutations (for example rapidly completing
    /// several tasks) into a single save. The models are already mutated, so
    /// the interface shows every change immediately; only the synchronous
    /// store commit is kept off the latency-sensitive tap itself.
    static func scheduleSave(
        _ modelContext: ModelContext,
        after delay: Duration = .milliseconds(300)
    ) {
        pendingSaveTask?.cancel()
        pendingSaveContext = modelContext
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            pendingSaveTask = nil
            guard let context = pendingSaveContext else { return }
            pendingSaveContext = nil
            _ = save(context)
        }
    }

    /// Persists a scheduled save immediately, for example when the scene
    /// resigns or a view disappears while a coalescing window is still open.
    static func flushScheduledSave() {
        guard pendingSaveTask != nil else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard let context = pendingSaveContext else { return }
        pendingSaveContext = nil
        _ = save(context)
    }

    static func report(_ error: Error) {
        NotificationCenter.default.post(
            name: .persistenceSaveFailed,
            object: nil,
            userInfo: [errorUserInfoKey: error.localizedDescription]
        )
    }
}
