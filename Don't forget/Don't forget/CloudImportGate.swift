import CoreData
import Foundation

/// Holds back the first generation of recurring occurrences until iCloud has
/// delivered what the user's other devices already generated.
///
/// Recurrence occurrences are materialised rows, not a synced plan. A device
/// that reconciles while its CloudKit import is still running sees a store
/// that is missing most of those rows, generates the whole series itself, and
/// ends up with two copies of every occurrence once the import lands. Waiting
/// for the import to go quiet removes that race; the duplicate collapse in
/// `RecurringOccurrenceReconciler` cleans up whatever slips through anyway.
///
/// The gate only ever *waits*, so it costs no work. After the store has
/// settled once it returns immediately for the rest of the launch.
@MainActor
enum CloudImportGate {
    private static var lastActivity = Date.now
    private static var activeImportCount = 0
    private static var hasSettled = false
    private static var observerTokens: [NSObjectProtocol] = []

    /// Called once at launch so the quiet window is measured from process
    /// start rather than from the first reconciliation.
    static func start() {
        guard observerTokens.isEmpty, AppModelStore.isICloudSyncEnabled else { return }
        lastActivity = .now

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CloudImportGate.lastActivity = .now
                }
            }
        )

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                    event.type == .import else {
                    return
                }
                let hasFinished = event.endDate != nil
                Task { @MainActor in
                    CloudImportGate.noteImport(hasFinished: hasFinished)
                }
            }
        )
    }

    /// Waits until no import has been running or reported for `quietPeriod`,
    /// and at most `maximumWait` in total. Both bounds are deliberately short:
    /// a slow or offline import must never keep the user's own recurring items
    /// from appearing.
    static func waitUntilSettled(
        maximumWait: Duration = .seconds(8),
        quietPeriod: TimeInterval = 1.2
    ) async {
        guard !hasSettled else { return }
        guard AppModelStore.isICloudSyncEnabled else {
            hasSettled = true
            return
        }

        let deadline = ContinuousClock.now.advanced(by: maximumWait)
        while ContinuousClock.now < deadline {
            if activeImportCount == 0,
               Date.now.timeIntervalSince(lastActivity) >= quietPeriod {
                break
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }

        hasSettled = true
    }

    private static func noteImport(hasFinished: Bool) {
        lastActivity = .now
        if hasFinished {
            activeImportCount = max(0, activeImportCount - 1)
        } else {
            activeImportCount += 1
        }
    }
}
