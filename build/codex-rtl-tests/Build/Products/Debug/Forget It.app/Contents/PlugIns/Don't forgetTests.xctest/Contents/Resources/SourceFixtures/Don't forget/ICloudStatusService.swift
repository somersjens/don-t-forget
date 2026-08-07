import CloudKit
import Foundation

enum ICloudStatusService {
    static func accountStatus() async -> CKAccountStatus {
        await withCheckedContinuation { continuation in
            CKContainer(identifier: AppModelStore.iCloudContainerIdentifier)
                .accountStatus { status, _ in
                    continuation.resume(returning: status)
                }
        }
    }

    static func warningDescription(for status: CKAccountStatus, locale: Locale) -> String? {
        switch status {
        case .available:
            nil
        case .noAccount:
            locale.localized("Geen iCloud-account aangemeld; gegevens blijven alleen op dit apparaat")
        case .restricted:
            locale.localized("iCloud is beperkt op dit apparaat")
        case .couldNotDetermine:
            locale.localized("iCloud-status kon niet worden bepaald")
        case .temporarilyUnavailable:
            locale.localized("iCloud is tijdelijk niet beschikbaar")
        @unknown default:
            locale.localized("Onbekende iCloud-status")
        }
    }
}
