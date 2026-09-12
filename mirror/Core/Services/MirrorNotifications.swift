import UIKit
import UserNotifications

// Shows mood alert banner even when app is in foreground; suppresses all others.
final class MirrorNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MirrorNotificationDelegate()
    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == "mirror.moodAlert" {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == "mirror.moodCheckIn",
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                MoodCheckInPresenter.shared.pending = true
            }
        }
        if response.notification.request.identifier == NotificationService.moodAlertID,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier
            || response.actionIdentifier == NotificationService.moodAlertWriteActionID,
           let url = URL(string: "mirror://write") {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
        // moodAlertDismissActionID ("Not now") needs no handling — the system already
        // dismissed the notification before this fires.
        completionHandler()
    }
}

enum NotificationService {
    private static let nudgeID = "mirror.dailyNudge"
    private static let firstNudgeID = "mirror.firstNudge"
    private static let digestID = "mirror.weeklyDigest"
    // Not `private` — MirrorNotificationDelegate (same file, different type) reads these.
    static let moodAlertID = "mirror.moodAlert"
    static let moodAlertCategoryID = "mirror.moodAlert.category"
    static let moodAlertWriteActionID = "mirror.moodAlert.writeNow"
    private static let moodAlertDismissActionID = "mirror.moodAlert.notNow"
    private static let monthlyReportID = "mirror.monthlyReport"
    private static let writingReminderID = "mirror.writingReminder"
    private static let moodCheckInID = "mirror.moodCheckIn"
    private static let title = String(localized: "MirrorNotes", comment: "Push notification title")

    /// Registers the mood alert's quick actions. Must run before any mood alert notification
    /// is scheduled — called once from mirrorApp's init, alongside setting the delegate.
    static func registerCategories() {
        let writeAction = UNNotificationAction(
            identifier: moodAlertWriteActionID,
            title: String(localized: "Write now", comment: "Mood alert notification action — opens the write screen"),
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: moodAlertDismissActionID,
            title: String(localized: "Not now", comment: "Mood alert notification action — dismisses without opening the app"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: moodAlertCategoryID,
            actions: [writeAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Context-aware daily nudge — single repeating notification whose content is
    /// refreshed on every app-active and every nightly background task run.
    /// Three states: reflection ready / wrote but not ready yet / nothing written.
    ///
    /// `previewText`, when non-nil (user opted in via Settings, and the caller's `degraded`
    /// check already passed), replaces the generic "ready" body with a snippet of the actual
    /// nudge — the lock-screen surface is the whole product for anyone who doesn't open the
    /// app. Ignored unless `insightReady` is also true.
    static func rescheduleContextualNudge(
        hasWrittenToday: Bool,
        insightReady: Bool,
        hour: Int,
        minute: Int,
        previewText: String? = nil
    ) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [nudgeID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        if hasWrittenToday, insightReady, let preview = previewText, let snippet = notificationSnippet(preview) {
            content.body = snippet
        } else {
            content.body = hasWrittenToday
                ? (insightReady
                    ? String(localized: "Your daily reflection is ready.", comment: "Push notification body when today's daily reflection is ready")
                    : String(localized: "Come check your daily reflection.", comment: "Push notification body when today's reflection should be checked"))
                : String(localized: "What's on your mind? Take a moment to write.", comment: "Push notification body for a daily writing nudge")
        }

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: nudgeID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Free users — one-time notification after their first nudge is generated.
    /// Brings them back to see the paywall at the right moment.
    static func scheduleFirstNudgeHook(hour: Int, minute: Int) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [firstNudgeID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "MirrorNotes noticed something in your first entries. Open to see.", comment: "Push notification body after the first generated nudge")
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        // One-time only — free users don't get daily repeating nudges
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: firstNudgeID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Core subscribers only — Sunday 7AM repeating. Schedules (or re-schedules)
    /// whenever the weekly digest generates so it's always armed for the next Sunday.
    static func scheduleWeeklyDigest() async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [digestID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "Your weekly reflection is ready.", comment: "Push notification body for weekly digest")
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1
        components.hour = 7
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: digestID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Deep subscribers only — fires immediately when 3+ consecutive negative moods detected.
    static func sendMoodAlert(consecutiveCount: Int) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [moodAlertID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "You've been carrying a lot lately. Take a gentle moment for yourself.", comment: "Push notification body for a mood alert")
        content.sound = .default
        content.categoryIdentifier = moodAlertCategoryID
        // Separates this from the daily nudge's plain-banner treatment — it's the highest-stakes
        // notification the app sends. Without the com.apple.developer.usernotifications.time-
        // sensitive entitlement (not requested from Apple yet) this delivers as a normal active
        // notification; setting it now costs nothing and is a no-op rather than an error either way.
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: moodAlertID, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Deep subscribers only — fires on the 2nd of each month at 9AM to surface monthly report.
    static func scheduleMonthlyReportReminder() async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [monthlyReportID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "Your monthly deep report is ready.", comment: "Push notification body for monthly report")
        content.sound = .default

        var components = DateComponents()
        components.day = 2
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: monthlyReportID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// The standalone "time to write" reminder was folded into the unified
    /// daily check-in reminder (see `scheduleMoodCheckIn`). This only clears
    /// any leftover request from a build that still scheduled it.
    static func cancelWritingReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [writingReminderID])
    }

    /// All tiers — daily prompt to log how you're feeling right now, separate
    /// from the Core-only Daily Nudge and from writing a full entry.
    static func scheduleMoodCheckIn(hour: Int, minute: Int) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [moodCheckInID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "How are you feeling right now?", comment: "Push notification body for the daily mood check-in")
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: moodCheckInID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelMoodCheckIn() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [moodCheckInID])
    }

    static func cancelNudge() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [nudgeID, firstNudgeID])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func nudgeHour() -> Int {
        UserDefaults.standard.object(forKey: "nudgeHour") as? Int ?? 8
    }

    static func nudgeMinute() -> Int {
        UserDefaults.standard.object(forKey: "nudgeMinute") as? Int ?? 0
    }

    /// Truncates at a word boundary near 60 chars rather than mid-word — nil for empty/whitespace
    /// input so the caller falls back to the generic body instead of pushing an empty banner.
    /// Not `private` so InsightValidationTests can exercise it directly.
    static func notificationSnippet(_ text: String, limit: Int = 60) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: limit)
        let truncated = trimmed[..<cutoff]
        let lastSpace = truncated.lastIndex(of: " ") ?? cutoff
        return trimmed[..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        return status.authorizationStatus == .authorized
            || status.authorizationStatus == .provisional
    }
}
