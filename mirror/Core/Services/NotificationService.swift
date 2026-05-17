import UserNotifications

enum NotificationService {
    private static let nudgeID = "mirror.dailyNudge"
    private static let firstNudgeID = "mirror.firstNudge"
    private static let digestID = "mirror.weeklyDigest"
    private static let moodAlertID = "mirror.moodAlert"
    private static let monthlyReportID = "mirror.monthlyReport"

    /// Core subscribers only — repeats daily at the user's configured time.
    static func scheduleRepeatingNudge(hour: Int, minute: Int) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [nudgeID])

        let content = UNMutableNotificationContent()
        content.title = "MirrorNotes"
        content.body = "Your daily reflection is ready."
        content.sound = .default

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
        content.title = "MirrorNotes"
        content.body = "MirrorNotes noticed something in your first entries. Open to see."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        // One-time only — free users don't get daily repeating nudges
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: firstNudgeID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Core subscribers only — repeats weekly on Sunday at 7AM.
    static func scheduleWeeklyDigest() async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [digestID])

        let content = UNMutableNotificationContent()
        content.title = "MirrorNotes"
        content.body = "Your weekly reflection is ready."
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
        content.title = "MirrorNotes"
        content.body = "You've logged low mood \(consecutiveCount) times in a row. Take a moment to check in."
        content.sound = .default

        let request = UNNotificationRequest(identifier: moodAlertID, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Deep subscribers only — fires on the 2nd of each month at 9AM to surface monthly report.
    static func scheduleMonthlyReportReminder() async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [monthlyReportID])

        let content = UNMutableNotificationContent()
        content.title = "MirrorNotes"
        content.body = "Your monthly deep report is ready."
        content.sound = .default

        var components = DateComponents()
        components.day = 2
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: monthlyReportID, content: content, trigger: trigger)
        try? await center.add(request)
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

    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        return status.authorizationStatus == .authorized
            || status.authorizationStatus == .provisional
    }
}
