import Foundation
import UserNotifications

private final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
enum EndOfDayReminderService {
    static let defaultMinutes = 21 * 60 + 50
    static let notificationSoundName = "Notification_sound.mp3"

    private static let identifierPrefix = "end-of-day-reminder."
    private static let scheduledIdentifiersKey = "endOfDayReminder.scheduledIdentifiers"
    private static let maximumScheduledDays = 60
    private static var schedulingGeneration = 0
    private static let notificationDelegate = AppNotificationDelegate()

    private struct EntrySnapshot {
        let date: Date
        let text: String
        let startMinutes: Int?
        let manualOrder: Double
    }

    static func configureNotificationPresentation() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    static func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if isAuthorized(settings.authorizationStatus) {
            return true
        }

        switch settings.authorizationStatus {
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        default:
            return false
        }
    }

    static func reschedule(entries: [DayEntry], minutes: Int, now: Date = .now) async throws {
        schedulingGeneration += 1
        let generation = schedulingGeneration
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard generation == schedulingGeneration else { return }
        guard isAuthorized(settings.authorizationStatus) else {
            cancelPendingReminders()
            return
        }

        removeStoredPendingReminders()

        let calendar = AppCalendar.calendar
        let today = calendar.startOfDay(for: now)
        let safeMinutes = min(max(minutes, 0), 23 * 60 + 59)
        let snapshots = entries.map {
            EntrySnapshot(
                date: calendar.startOfDay(for: $0.date),
                text: normalizedText($0.rawText),
                startMinutes: $0.startMinutes,
                manualOrder: $0.manualOrder
            )
        }
        let grouped = Dictionary(grouping: snapshots, by: \.date)
        let scheduledDays = grouped.keys
            .filter { $0 >= today }
            .sorted()
            .prefix(maximumScheduledDays)

        var identifiers: [String] = []
        for day in scheduledDays {
            guard generation == schedulingGeneration else { return }
            guard let fireDate = calendar.date(
                bySettingHour: safeMinutes / 60,
                minute: safeMinutes % 60,
                second: 0,
                of: day
            ), fireDate > now else {
                continue
            }

            let dayEntries = (grouped[day] ?? [])
                .filter { !$0.text.isEmpty }
                .sorted(by: sortEntries)
            guard !dayEntries.isEmpty else { continue }

            let content = notificationContent(
                body: reminderBody(texts: dayEntries.map(\.text))
            )

            let dateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: false
            )
            let identifier = identifierPrefix
                + String(Int(day.timeIntervalSince1970))
                + "."
                + UUID().uuidString
            try await center.add(UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            ))
            guard generation == schedulingGeneration else {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
            identifiers.append(identifier)
            UserDefaults.standard.set(identifiers, forKey: scheduledIdentifiersKey)
        }
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
#if os(macOS)
        status == .authorized || status == .provisional
#else
        status == .authorized || status == .provisional || status == .ephemeral
#endif
    }

    static func sendTestNotification(
        entries: [DayEntry],
        emptyText: String,
        now: Date = .now
    ) async throws {
        let calendar = AppCalendar.calendar
        let today = calendar.startOfDay(for: now)
        let texts = entries
            .map {
                EntrySnapshot(
                    date: calendar.startOfDay(for: $0.date),
                    text: normalizedText($0.rawText),
                    startMinutes: $0.startMinutes,
                    manualOrder: $0.manualOrder
                )
            }
            .filter { $0.date == today && !$0.text.isEmpty }
            .sorted(by: sortEntries)
            .map(\.text)

        let content = notificationContent(
            body: testReminderBody(texts: texts, emptyText: emptyText)
        )

        let request = UNNotificationRequest(
            identifier: identifierPrefix + "test",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    static func cancelPendingReminders() {
        schedulingGeneration += 1
        removeStoredPendingReminders()
    }

    private static func removeStoredPendingReminders() {
        let defaults = UserDefaults.standard
        let identifiers = defaults.stringArray(forKey: scheduledIdentifiersKey) ?? []
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        defaults.removeObject(forKey: scheduledIdentifiersKey)
    }

    static func reminderBody(texts: [String]) -> String {
        "\(texts.count)x | " + texts.joined(separator: " | ")
    }

    static func testReminderBody(texts: [String], emptyText: String) -> String {
        texts.isEmpty ? "0x | \(emptyText)" : reminderBody(texts: texts)
    }

    static var notificationTitle: String {
        notificationTitle(for: AppCalendar.language)
    }

    static func notificationTitle(for language: AppLanguage) -> String {
        language.locale.localized("notification.title")
    }

    private static func notificationContent(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle
        content.body = body
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: notificationSoundName)
        )
        return content
    }

    private static func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func sortEntries(_ first: EntrySnapshot, _ second: EntrySnapshot) -> Bool {
        switch (first.startMinutes, second.startMinutes) {
        case let (a?, b?):
            return a == b ? first.manualOrder < second.manualOrder : a < b
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return first.manualOrder < second.manualOrder
        }
    }

}
