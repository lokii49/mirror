import Foundation
import UserNotifications

/// "Remind me…" on a Scratch note (owner, 2026-11-07): one local notification at the time picked,
/// that opens the note. It never carries the note's words (the lock screen and a paired watch show
/// notifications), only "Scratch note reminder". Nothing leaves the device. Deleting the note
/// cancels it (`EntryTrash.moveToTrash`).
enum ScratchReminders {
    static let identifierPrefix = "mirror.scratchReminder."
    static let entryIDKey = "entryID"

    static func identifier(for entryID: UUID) -> String { identifierPrefix + entryID.uuidString }

    /// The entry a delivered reminder opens, or nil for any other notification.
    static func entryID(from request: UNNotificationRequest) -> UUID? {
        guard request.identifier.hasPrefix(identifierPrefix),
              let raw = request.content.userInfo[entryIDKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    /// The request for a reminder, kept apart from scheduling so a test can read what it shows.
    static func request(for entryID: UUID, at date: Date, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Scratch note reminder", comment: "Notification title for a reminder set on a Scratch note; never shows the note's text")
        content.body = String(localized: "Tap to open your note.", comment: "Notification body for a Scratch note reminder")
        content.sound = .default
        content.userInfo = [entryIDKey: entryID.uuidString]
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: identifier(for: entryID), content: content, trigger: trigger)
    }

    enum Outcome: Equatable { case scheduled, notAllowed, failed }

    /// Asks for notification permission the first time (it's the person's own reminder), then adds it.
    static func schedule(entryID: UUID, at date: Date) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        #if os(iOS)
        let allowed = status == .authorized || status == .provisional || status == .ephemeral
        #else
        let allowed = status == .authorized || status == .provisional
        #endif
        guard allowed else { return .notAllowed }
        do {
            try await center.add(request(for: entryID, at: date))
            return .scheduled
        } catch {
            return .failed
        }
    }

    static func cancel(entryIDs: [UUID]) {
        guard !entryIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: entryIDs.map(identifier(for:)))
    }

    /// A sensible first time to offer: the next whole hour, at least 30 minutes away.
    static func defaultTime(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        let soon = now.addingTimeInterval(30 * 60)
        let hour = calendar.dateInterval(of: .hour, for: soon)?.start ?? soon
        return hour < soon ? calendar.date(byAdding: .hour, value: 1, to: hour) ?? soon : hour
    }
}
