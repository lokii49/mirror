import Foundation
import SwiftData
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

    /// Asks for notification permission the first time (it's the person's own reminder); true when
    /// a reminder can be delivered. Called when a time is picked, before the note is saved.
    static func ensureAllowed() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        #if os(iOS)
        return status == .authorized || status == .provisional || status == .ephemeral
        #else
        return status == .authorized || status == .provisional
        #endif
    }

    static func schedule(entryID: UUID, at date: Date) async -> Outcome {
        guard await ensureAllowed() else { return .notAllowed }
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request(for: entryID, at: date))
            return .scheduled
        } catch {
            return .failed
        }
    }

    /// When this note's reminder will fire, or nil when none is waiting.
    static func pendingDate(for entryID: UUID) async -> Date? {
        let id = identifier(for: entryID)
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == id }) else { return nil }
        return (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    static func cancel(entryIDs: [UUID]) {
        guard !entryIDs.isEmpty else { return }
        let ids = entryIDs.map(identifier(for:))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        // One already in Notification Center would open a note that's gone.
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Reminders whose note is gone from this device by a way that never ran `cancel`: trashed or
    /// erased on another device and synced in, or an iCloud purge. Run on app-active; a reminder
    /// is set on this device, so its note was here when it was set.
    @MainActor
    static func dropOrphans(in context: ModelContext) async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let entryIDs = pending.compactMap(entryID(from:))
        guard !entryIDs.isEmpty else { return }
        let gone = entryIDs.filter { id in
            var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            // A failed fetch keeps the reminder.
            return ((try? context.fetchCount(descriptor)) ?? 1) == 0
        }
        cancel(entryIDs: gone)
    }

    /// Every Scratch reminder still waiting (Delete Everything), so none fires for a note that's gone.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// The chip's wording: the weekday within the next 6 days ("Sat 11:00 PM"), else the date
    /// ("18 Nov, 9:00 AM"), so a reminder ten days out doesn't read as this week's.
    static func chipFormat(for date: Date, now: Date = Date()) -> Date.FormatStyle {
        date < now.addingTimeInterval(6 * 24 * 60 * 60)
            ? .dateTime.weekday(.abbreviated).hour().minute()
            : .dateTime.day().month(.abbreviated).hour().minute()
    }

    /// A sensible first time to offer: the next whole hour, at least 30 minutes away.
    static func defaultTime(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        let soon = now.addingTimeInterval(30 * 60)
        let hour = calendar.dateInterval(of: .hour, for: soon)?.start ?? soon
        return hour < soon ? calendar.date(byAdding: .hour, value: 1, to: hour) ?? soon : hour
    }
}
