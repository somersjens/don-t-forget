import Foundation
import SwiftData

extension Notification.Name {
    static let persistenceSaveFailed = Notification.Name("persistence.saveFailed")
}

@MainActor
enum PersistenceSafety {
    static let errorUserInfoKey = "error"

    /// Saves a user-initiated change. Failed mutations are rolled back so the
    /// interface never keeps showing data that was not persisted.
    @discardableResult
    static func save(_ modelContext: ModelContext) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            report(error)
            return false
        }
    }

    static func report(_ error: Error) {
        NotificationCenter.default.post(
            name: .persistenceSaveFailed,
            object: nil,
            userInfo: [errorUserInfoKey: error.localizedDescription]
        )
    }
}
