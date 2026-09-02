import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit
import UserNotifications
import WidgetKit
import RevenueCat

@main
struct mirrorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Foreground proactive generation task — cancelled immediately when app backgrounds
    // so GPU inference stops at the next Task.checkCancellation() in LocalLLMService.
    nonisolated(unsafe) static var activeGenerationTask: Task<Void, Never>?

    var sharedModelContainer: ModelContainer = MirrorModelContainer.shared

    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: "appl_OcfOuFibRNCALKDBSbAslQwJKQT")
        UNUserNotificationCenter.current().delegate = MirrorNotificationDelegate.shared
        registerNightlyInsightsTask()
        configureNavigationBarAppearance()
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = UIColor(MirrorTheme.inkBorder)
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Request notification permission for users who completed onboarding before
                // the permission prompt was added (status .notDetermined = never asked).
                Task {
                    await requestNotificationPermissionIfNeeded()
                    migrateToUnifiedDailyReminder()
                    await reArmUserReminders()
                }
                // Backfill the rate-us gate for users already past 5 entries
                // (including anyone who only saw Apple's raw prompt on an older
                // build). Idempotent — one-shot flag, self-guards on count.
                Task { @MainActor in
                    ReviewRequestManager.requestIfEntryMilestoneReached(context: sharedModelContainer.mainContext)
                }
                // One-time move of daily mood check-ins from the legacy encrypted
                // UserDefaults blob into SwiftData (so they sync via CloudKit).
                // Idempotent, one-directional, keeps the blob intact.
                Task { @MainActor in
                    MoodCheckInMigration.runIfNeeded(context: sharedModelContainer.mainContext)
                }
                // Proactively generate so content is ready before user opens Insights tab.
                // Store task so we can cancel it immediately if the app backgrounds.
                mirrorApp.activeGenerationTask?.cancel()
                mirrorApp.activeGenerationTask = Task(priority: .background) {
                    await preGenerateInsightsIfNeeded()
                }
            case .background:
                // Cancel any foreground GPU generation immediately — LocalLLMService will
                // stop at the next Task.checkCancellation() and the nightly BGProcessingTask
                // will retry on CPU.
                mirrorApp.activeGenerationTask?.cancel()
                mirrorApp.activeGenerationTask = nil
                scheduleDailyNudgeFallback()
                generateDailyNudgeInBackgroundIfNeeded()
                scheduleNightlyInsights()
                // Give any remaining in-flight generation (BGProcessingTask path) ~30s grace.
                extendBackgroundForPendingGeneration()
            default:
                break
            }
        }
        // Keep BGAppRefreshTask as a lightweight fallback for weekly digest on devices
        // that don't charge overnight (power requirement not met for nightly task).
        .backgroundTask(.appRefresh("com.lokesh.mirror.weeklyDigest")) {
            await runWeeklyDigestFallback()
        }
        .backgroundTask(.appRefresh("com.lokesh.mirror.dailyNudge")) {
            await runDailyNudgeFallback()
        }
        .backgroundTask(.appRefresh("com.lokesh.mirror.monthlyReport")) {
            await runMonthlyReportFallback()
        }
    }

    // MARK: - BGProcessingTask: nightly at ~3AM while charging

    private func registerNightlyInsightsTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.lokesh.mirror.nightlyInsights",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                await mirrorApp.runNightlyInsights(container: self.sharedModelContainer)
            }
            // Guard against calling setTaskCompleted twice if expiration fires before work finishes.
            nonisolated(unsafe) var expired = false
            processingTask.expirationHandler = {
                expired = true
                work.cancel()
                processingTask.setTaskCompleted(success: false)
            }
            Task {
                _ = await work.result
                scheduleNightlyInsights()  // always re-schedule, even if expired
                guard !expired else { return }
                processingTask.setTaskCompleted(success: true)
            }
        }
    }

    private func scheduleNightlyInsights() {
        let request = BGProcessingTaskRequest(identifier: "com.lokesh.mirror.nightlyInsights")
        // Only run while charging → no thermal impact on the user.
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        // Target ~3AM local time; iOS fires it opportunistically after that.
        request.earliestBeginDate = next3AM()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func next3AM() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        components.second = 0
        guard var target = calendar.date(from: components) else { return Date() }
        if target <= Date() {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return target
    }

    // MARK: - Nightly task body (static so the BGTask closure can call it without capturing self)

    @MainActor
    private static func runNightlyInsights(container: ModelContainer) async {
        let context = container.mainContext
        await runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)

        // Refresh contextual nudge notification so it reflects tonight's generation result.
        // Covers the case where no writing happened: resets to "write" message so user
        // isn't reminded of a stale "ready" from yesterday.
        if SubscriptionService.shared.isSubscribed {
            let insightReady = hasDailyNudgeForToday(context: context)
            let hasWrittenToday = hasEntryToday(context: context)
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            await NotificationService.rescheduleContextualNudge(
                hasWrittenToday: hasWrittenToday,
                insightReady: insightReady,
                hour: hour,
                minute: minute
            )
        }

        // Weekly digest only on Sunday
        if Calendar.current.component(.weekday, from: Date()) == 1 {
            await runWeeklyDigestIfNeeded(context: context)
        }
        // Monthly report: generate once 20+ entries exist (Deep only)
        await runMonthlyReportIfNeeded(context: context)
        // Fill in moods the save-time auto-detect missed, then check alerts
        await backfillMissingMoodsIfNeeded(context: context)
        // Mood alert check every night (Deep only)
        await checkMoodAlertIfNeeded(context: context)
    }

    // MARK: - Proactive generation on app active

    @MainActor
    private func preGenerateInsightsIfNeeded() async {
        let context = sharedModelContainer.mainContext
        await mirrorApp.runDailyNudgeIfNeeded(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)
        mirrorApp.syncNudgeToWidget(context: context)

        // Update the daily nudge notification to reflect current state.
        // Content resets on every app open so the message matches today's context.
        if SubscriptionService.shared.isSubscribed {
            let insightReady = mirrorApp.hasDailyNudgeForToday(context: context)
            let hasWrittenToday = mirrorApp.hasEntryToday(context: context)
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            await NotificationService.rescheduleContextualNudge(
                hasWrittenToday: hasWrittenToday,
                insightReady: insightReady,
                hour: hour,
                minute: minute
            )
        }

        // Weekly digest: generate on Sundays proactively (fallback if nightly BGProcessingTask missed)
        if Calendar.current.component(.weekday, from: Date()) == 1 {
            await mirrorApp.runWeeklyDigestIfNeeded(context: context)
        }
        // Monthly report: generate as soon as 20+ entries exist, not only on the 1st.
        await mirrorApp.runMonthlyReportIfNeeded(context: context)
        // Fill in moods the save-time auto-detect missed, then check alerts
        await mirrorApp.backfillMissingMoodsIfNeeded(context: context)
        await mirrorApp.checkMoodAlertIfNeeded(context: context)
    }

    // MARK: - Shared generation helpers (also called from BGAppRefreshTask fallback)

    @MainActor
    static func runDailyNudgeIfNeeded(context: ModelContext, bypassTimeGate: Bool = false) async {
        let today = DateHelpers.dayIdentifier(for: Date())
        let coordinatorKey = "nudge_\(today)"

        // Check SwiftData cache
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        let todayInsights = (try? context.fetch(descriptor)) ?? []
        guard !todayInsights.contains(where: { $0.type == .dailyNudge }) else { return }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries = (try? context.fetch(entryDescriptor)) ?? []
        guard entries.count >= 3 else { return }

        // First nudge is free; subsequent require subscription
        let allInsightsDescriptor = FetchDescriptor<Insight>()
        let allInsights = (try? context.fetch(allInsightsDescriptor)) ?? []
        let hasSeenFirst = allInsights.contains { $0.type == .dailyNudge }
        if hasSeenFirst && !SubscriptionService.shared.isSubscribed { return }

        // Only generate if there are entries written after the last nudge.
        // No new writing → no new reflection.
        if let lastNudge = allInsights
            .filter({ $0.type == .dailyNudge })
            .max(by: { $0.generatedAt < $1.generatedAt }) {
            guard entries.contains(where: { $0.createdAt > lastNudge.generatedAt }) else { return }
        }

        // Respect the user's preferred nudge time so a full day of writing informs the reflection.
        // Nightly background tasks bypass this gate — they're the fallback for users who never
        // opened the app at their preferred hour.
        if !bypassTimeGate {
            let preferredHour = NotificationService.nudgeHour()
            let currentHour = Calendar.current.component(.hour, from: Date())
            guard currentHour >= preferredHour else { return }
        }

        guard modelAvailable() else { return }
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        let recentNudges = allInsights
            .filter { $0.type == .dailyNudge }
            .sorted { $0.generatedAt > $1.generatedAt }
            .prefix(4)
            .map(\.content)

        do {
            let text = try await InsightService.generateNudge(entries: entries, recentNudges: Array(recentNudges))
            let insight = Insight(type: .dailyNudge, content: text, periodIdentifier: today)
            context.insert(insight)
            try context.save()
            let wDefaults = UserDefaults(suiteName: "group.com.lokesh.mirror")
            wDefaults?.set(text, forKey: "widget.nudge.text")
            wDefaults?.set(today, forKey: "widget.nudge.date")
            WidgetCenter.shared.reloadTimelines(ofKind: "MirrorNudgeWidget")
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            if SubscriptionService.shared.isSubscribed {
                // Update the repeating nudge content to "ready" so it fires correctly at nudge time.
                // No second one-time notification — that would double-fire at the same minute.
                await NotificationService.rescheduleContextualNudge(
                    hasWrittenToday: true,
                    insightReady: true,
                    hour: hour,
                    minute: minute
                )
            } else {
                // First nudge for free users — one-time hook to drive paywall conversion
                await NotificationService.scheduleFirstNudgeHook(hour: hour, minute: minute)
            }
        } catch { /* Non-fatal — InsightView.task will retry when user navigates there */ }
    }

    @MainActor
    static func hasDailyNudgeForToday(context: ModelContext) -> Bool {
        let today = DateHelpers.dayIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        let todayInsights = (try? context.fetch(descriptor)) ?? []
        return todayInsights.contains { $0.type == .dailyNudge }
    }

    @MainActor
    static func hasEntryToday(context: ModelContext) -> Bool {
        let start = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.createdAt >= start }
        )
        return ((try? context.fetch(descriptor)) ?? []).count > 0
    }

    @MainActor
    static func runWeeklyDigestIfNeeded(context: ModelContext) async {
        let thisWeek = DateHelpers.weekIdentifier(for: Date())
        let coordinatorKey = "digest_\(thisWeek)"

        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == thisWeek }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        guard !existing.contains(where: { $0.type == .weeklyDigest }) else { return }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries = (try? context.fetch(entryDescriptor)) ?? []
        guard entries.count >= 5, SubscriptionService.shared.isSubscribed else { return }
        guard modelAvailable() else { return }
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        do {
            let text = try await InsightService.generateWeeklyDigest(entries: entries)
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek)
            context.insert(insight)
            try context.save()
            // scheduleWeeklyDigest is the sole fire — no separate one-time notification
            // to avoid double-banner on Sunday at 7am.
            await NotificationService.scheduleWeeklyDigest()
        } catch { /* Non-fatal */ }
    }

    // MARK: - Monthly Report (Deep only)

    @MainActor
    static func runMonthlyReportIfNeeded(context: ModelContext) async {
        let thisMonth = DateHelpers.monthIdentifier(for: Date())
        let coordinatorKey = "monthlyReport_\(thisMonth)"

        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == thisMonth }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        // Respect 24h cache — only auto-generate once per month
        guard !existing.contains(where: { $0.type == .monthlyReport }) else { return }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allEntries = (try? context.fetch(entryDescriptor)) ?? []
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let monthEntries = allEntries.filter { $0.createdAt >= monthStart }
        let minEntries = DateHelpers.isInLastThreeDaysOfMonth(now) ? 10 : 20
        guard monthEntries.count >= minEntries, SubscriptionService.shared.isDeep else { return }
        guard modelAvailable() else { return }
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        do {
            let text = try await InsightService.generateMonthlyReport(monthEntries: monthEntries, allEntries: allEntries)
            let insight = Insight(type: .monthlyReport, content: text, periodIdentifier: thisMonth)
            context.insert(insight)
            try context.save()
            await NotificationService.scheduleMonthlyReportReminder()
        } catch { /* Non-fatal */ }
    }

    // MARK: - Model availability

    static func modelAvailable() -> Bool {
        if Bundle.main.url(forResource: LocalLLMService.modelFileName, withExtension: LocalLLMService.modelExtension) != nil {
            return true
        }
        guard let url = try? LocalLLMService.preferredModelURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Mood Alert (Deep only — 3 consecutive negative-mood days)

    private static let moodAlertCooldownKey = "mirror.lastMoodAlertSent"

    // MARK: - Mood backfill
    //
    // The save-time auto-detect in WriteView is fire-and-forget: if the app is
    // suspended right after saving (the common case), the LLM task dies and the
    // entry stays mood-less forever. This pass retries on app-active and nightly.

    private static var isBackfillingMoods = false
    private static let moodBackfillWindowDays = 14
    private static let moodBackfillBatchLimit = 5

    @MainActor
    static func backfillMissingMoodsIfNeeded(context: ModelContext) async {
        guard SubscriptionService.shared.isSubscribed else { return }
        guard LocalLLMService.isModelAvailable else { return }
        guard !isBackfillingMoods else { return }
        isBackfillingMoods = true
        defer { isBackfillingMoods = false }

        let cutoff = Calendar.current.date(byAdding: .day, value: -moodBackfillWindowDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.encryptedMood == nil && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let candidates = ((try? context.fetch(descriptor)) ?? []).prefix(moodBackfillBatchLimit)

        for entry in candidates {
            guard !Task.isCancelled else { return }
            guard !entry.textDecryptionFailed else { continue }
            let text = entry.insightContext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // One failure means the LLM path is unhealthy right now (memory pressure,
            // cancellation mid-load) — stop the pass and let the next trigger retry.
            guard let detected = try? await InsightService.detectEmotion(text: text),
                  MirrorTheme.moodOptions.contains(detected) else { return }
            entry.mood = detected
            try? context.save()
        }
    }

    @MainActor
    static func checkMoodAlertIfNeeded(context: ModelContext) async {
        guard SubscriptionService.shared.isDeep else { return }

        // Cooldown: at most one alert per 24h
        if let last = UserDefaults.standard.object(forKey: moodAlertCooldownKey) as? Date,
           Date().timeIntervalSince(last) < 86400 { return }

        let descriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []

        // Consecutive negative *days* (entry moods + check-ins merged, latest of
        // the day wins; a day with no reading breaks the run) — not consecutive
        // entries, which three low entries in one afternoon could falsely trip.
        let checkIns = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        let negativeDays = MoodLog.consecutiveNegativeDays(
            entries: entries,
            checkIns: checkIns
        )

        if negativeDays >= 3 {
            UserDefaults.standard.set(Date(), forKey: moodAlertCooldownKey)
            await NotificationService.sendMoodAlert(consecutiveCount: negativeDays)
        }
    }

    // MARK: - BGAppRefreshTask fallback for daily reflection

    @MainActor
    private func runDailyNudgeFallback() async {
        let context = sharedModelContainer.mainContext
        await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
        scheduleDailyNudgeFallback()
    }

    private func scheduleDailyNudgeFallback() {
        let request = BGAppRefreshTaskRequest(identifier: "com.lokesh.mirror.dailyNudge")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func generateDailyNudgeInBackgroundIfNeeded() {
        let today = DateHelpers.dayIdentifier(for: Date())
        guard !InsightGenerationCoordinator.shared.isInFlight("nudge_\(today)") else { return }

        let app = UIApplication.shared
        let bgTask = BackgroundTaskReference()
        bgTask.id = app.beginBackgroundTask(withName: "mirror.dailyNudge.catchup") {
            Task { @MainActor in
                app.endBackgroundTask(bgTask.id)
            }
        }

        Task { @MainActor in
            let context = sharedModelContainer.mainContext
            if !mirrorApp.hasDailyNudgeForToday(context: context) {
                await mirrorApp.runDailyNudgeIfNeeded(context: context)
            }
            app.endBackgroundTask(bgTask.id)
        }
    }

    // MARK: - BGAppRefreshTask fallback for weekly digest

    @MainActor
    private func runWeeklyDigestFallback() async {
        let context = sharedModelContainer.mainContext
        await mirrorApp.runWeeklyDigestIfNeeded(context: context)
        scheduleWeeklyDigestFallback()
    }

    private func scheduleWeeklyDigestFallback() {
        let request = BGAppRefreshTaskRequest(identifier: "com.lokesh.mirror.weeklyDigest")
        request.earliestBeginDate = nextSunday7AM()
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Monthly report BGAppRefreshTask (fallback for 1st of month)

    @MainActor
    private func runMonthlyReportFallback() async {
        let context = sharedModelContainer.mainContext
        await mirrorApp.runMonthlyReportIfNeeded(context: context)
        scheduleMonthlyReportFallback()
    }

    private func scheduleMonthlyReportFallback() {
        let request = BGAppRefreshTaskRequest(identifier: "com.lokesh.mirror.monthlyReport")
        request.earliestBeginDate = lastDayOfCurrentMonth9PM()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func lastDayOfCurrentMonth9PM() -> Date {
        let cal = Calendar.current
        let now = Date()
        // Last day of current month = first day of next month minus 1 day
        guard let nextMonthAny = cal.date(byAdding: .month, value: 1, to: now),
              let nextMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: nextMonthAny)),
              let lastDay = cal.date(byAdding: .day, value: -1, to: nextMonthStart) else { return now }
        var comps = cal.dateComponents([.year, .month, .day], from: lastDay)
        comps.hour = 21; comps.minute = 0; comps.second = 0
        guard var target = cal.date(from: comps) else { return now }
        if target <= now {
            // Already past end of this month — target last day of next month
            guard let twoMonthsAny = cal.date(byAdding: .month, value: 2, to: now),
                  let twoMonthsStart = cal.date(from: cal.dateComponents([.year, .month], from: twoMonthsAny)),
                  let nextLastDay = cal.date(byAdding: .day, value: -1, to: twoMonthsStart) else { return target }
            var nextComps = cal.dateComponents([.year, .month, .day], from: nextLastDay)
            nextComps.hour = 21; nextComps.minute = 0; nextComps.second = 0
            target = cal.date(from: nextComps) ?? target
        }
        return target
    }

    private func nextSunday7AM() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 1
        components.hour = 7
        components.minute = 0
        components.second = 0
        guard var next = calendar.date(from: components) else { return now }
        if next <= now {
            next = calendar.date(byAdding: .weekOfYear, value: 1, to: next) ?? next
        }
        return next
    }

    // MARK: - Widget data bridge

    private static let widgetDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    static func updateWidgetHeatmaps(context: ModelContext) {
        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)])
        let entries = (try? context.fetch(descriptor)) ?? []

        // Entry count per day drives the streak + wrote-today flags below. Stays
        // entry-only — a mood check-in isn't "writing an entry".
        var countByDay: [String: Int] = [:]
        for entry in entries {
            countByDay[widgetDayFormatter.string(from: entry.createdAt), default: 0] += 1
        }

        // Mood per day: entry moods + standalone daily check-ins, latest reading
        // of the day wins. Single merge rule, shared with every other surface.
        let checkIns = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        var moodByDay: [String: String] = [:]
        for (day, event) in MoodLog.dailyMoods(entries: entries, checkIns: checkIns) {
            moodByDay[widgetDayFormatter.string(from: day)] = event.mood
        }

        let defaults = UserDefaults(suiteName: "group.com.lokesh.mirror")
        defaults?.set(try? JSONEncoder().encode(countByDay), forKey: "widget.entries.heatmap")
        defaults?.set(try? JSONEncoder().encode(moodByDay),  forKey: "widget.mood.heatmap")

        // Streak + wrote-today for WriteWidget / EntriesMapWidget
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = widgetDayFormatter
        let todayKey = fmt.string(from: today)
        let wroteToday = (countByDay[todayKey] ?? 0) > 0
        var streakDay = today
        if !wroteToday {
            if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
               (countByDay[fmt.string(from: yesterday)] ?? 0) > 0 {
                streakDay = yesterday
            } else {
                streakDay = Date.distantPast
            }
        }
        var streak = 0
        while (countByDay[fmt.string(from: streakDay)] ?? 0) > 0 {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: streakDay) else { break }
            streakDay = prev
        }
        defaults?.set(streak, forKey: "widget.streak")
        defaults?.set(wroteToday, forKey: "widget.wrote.today")

        WidgetCenter.shared.reloadAllTimelines()
    }

    // Writes today's nudge text to AppGroup so NudgeWidget can read it even if the
    // nudge was generated in a previous app session (runDailyNudgeIfNeeded bails early then).
    @MainActor
    static func syncNudgeToWidget(context: ModelContext) {
        let today = DateHelpers.dayIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        guard let insights = try? context.fetch(descriptor),
              let nudge = insights.first(where: { $0.type == .dailyNudge }) else { return }
        let defaults = UserDefaults(suiteName: "group.com.lokesh.mirror")
        defaults?.set(nudge.content, forKey: "widget.nudge.text")
        defaults?.set(today, forKey: "widget.nudge.date")
    }

    // MARK: - Notification permission (existing users who completed onboarding before prompt was added)

    /// One-time move from the old separate "writing reminder" to the unified
    /// daily check-in reminder. Carries the user's chosen time over (unless
    /// they'd already picked a check-in time) and clears the old request.
    private func migrateToUnifiedDailyReminder() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "didMergeDailyReminder") else { return }
        d.set(true, forKey: "didMergeDailyReminder")

        if d.bool(forKey: "writingReminderEnabled"), !d.bool(forKey: "moodCheckInTimeUserSet") {
            d.set(d.object(forKey: "writingReminderHour") as? Int ?? 9, forKey: "moodCheckInHour")
            d.set(d.object(forKey: "writingReminderMinute") as? Int ?? 0, forKey: "moodCheckInMinute")
        }
        NotificationService.cancelWritingReminder()
    }

    /// Re-issue the unified daily check-in reminder on every foreground.
    /// `scheduleMoodCheckIn` clears-and-re-adds and no-ops when notifications
    /// aren't authorized — so this is idempotent and self-heals the case where
    /// the reminder was left on (it's on by default) before permission was
    /// granted, when nothing would otherwise have been scheduled.
    private func reArmUserReminders() async {
        let d = UserDefaults.standard
        // `moodCheckInEnabled` defaults to true — treat a missing value as on.
        let enabled = (d.object(forKey: "moodCheckInEnabled") as? Bool) ?? true
        guard enabled else { return }
        await NotificationService.scheduleMoodCheckIn(
            hour: d.object(forKey: "moodCheckInHour") as? Int ?? 9,
            minute: d.object(forKey: "moodCheckInMinute") as? Int ?? 0
        )
    }

    private func requestNotificationPermissionIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted, SubscriptionService.shared.isSubscribed {
            let context = sharedModelContainer.mainContext
            let insightReady = mirrorApp.hasDailyNudgeForToday(context: context)
            let hasWrittenToday = mirrorApp.hasEntryToday(context: context)
            await NotificationService.rescheduleContextualNudge(
                hasWrittenToday: hasWrittenToday,
                insightReady: insightReady,
                hour: NotificationService.nudgeHour(),
                minute: NotificationService.nudgeMinute()
            )
        }
    }

    // MARK: - Background time extension for mid-session generation

    private func extendBackgroundForPendingGeneration() {
        guard InsightGenerationCoordinator.shared.isAnyGenerating else { return }
        let app = UIApplication.shared
        let bgTask = BackgroundTaskReference()
        bgTask.id = app.beginBackgroundTask(withName: "mirror.insight.completion") {
            Task { @MainActor in
                app.endBackgroundTask(bgTask.id)
            }
        }
        Task { @MainActor in
            while InsightGenerationCoordinator.shared.isAnyGenerating {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            app.endBackgroundTask(bgTask.id)
        }
    }
}

private final class BackgroundTaskReference: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid
}
