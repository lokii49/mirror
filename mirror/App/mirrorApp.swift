import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit
import WidgetKit
import RevenueCat

@main
struct mirrorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Entry.self,
            Insight.self,
            UserProfile.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: "appl_OcfOuFibRNCALKDBSbAslQwJKQT")
        registerNightlyInsightsTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Proactively generate so content is ready before user opens Insights tab.
                Task(priority: .background) {
                    await preGenerateInsightsIfNeeded()
                }
            case .background:
                scheduleNightlyInsights()
                // If LLM is mid-generation when backgrounded, request ~30s grace so iOS
                // doesn't suspend before the current inference completes.
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
            processingTask.expirationHandler = {
                work.cancel()
                processingTask.setTaskCompleted(success: false)
            }
            Task {
                _ = await work.result
                processingTask.setTaskCompleted(success: true)
                // Re-schedule for the next night
                scheduleNightlyInsights()
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
        await runDailyNudgeIfNeeded(context: context)
        // Weekly digest only on Sunday
        if Calendar.current.component(.weekday, from: Date()) == 1 {
            await runWeeklyDigestIfNeeded(context: context)
        }
    }

    // MARK: - Proactive generation on app active

    @MainActor
    private func preGenerateInsightsIfNeeded() async {
        let context = sharedModelContainer.mainContext
        await mirrorApp.runDailyNudgeIfNeeded(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)
    }

    // MARK: - Shared generation helpers (also called from BGAppRefreshTask fallback)

    @MainActor
    static func runDailyNudgeIfNeeded(context: ModelContext) async {
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

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        do {
            let text = try await InsightService.generateNudge(entries: entries, token: "")
            let insight = Insight(type: .dailyNudge, content: text, periodIdentifier: today)
            context.insert(insight)
            try? context.save()
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            if SubscriptionService.shared.isSubscribed {
                await NotificationService.scheduleRepeatingNudge(hour: hour, minute: minute)
            } else {
                // First nudge for free users — one-time hook to drive paywall conversion
                await NotificationService.scheduleFirstNudgeHook(hour: hour, minute: minute)
            }
        } catch { /* Non-fatal — InsightView.task will retry when user navigates there */ }
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

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        do {
            let text = try await InsightService.generateWeeklyDigest(entries: entries, token: "")
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek)
            context.insert(insight)
            try? context.save()
            await NotificationService.scheduleWeeklyDigest()
        } catch { /* Non-fatal */ }
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

        var countByDay: [String: Int] = [:]
        var moodByDay: [String: String] = [:]

        for entry in entries {
            let key = widgetDayFormatter.string(from: entry.createdAt)
            countByDay[key, default: 0] += 1
            if let mood = entry.mood {
                moodByDay[key] = mood
            }
        }

        let defaults = UserDefaults(suiteName: "group.com.lokesh.mirror")
        defaults?.set(try? JSONEncoder().encode(countByDay), forKey: "widget.entries.heatmap")
        defaults?.set(try? JSONEncoder().encode(moodByDay),  forKey: "widget.mood.heatmap")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Background time extension for mid-session generation

    private func extendBackgroundForPendingGeneration() {
        guard InsightGenerationCoordinator.shared.isAnyGenerating else { return }
        let app = UIApplication.shared
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = app.beginBackgroundTask(withName: "mirror.insight.completion") {
            app.endBackgroundTask(bgTask)
        }
        Task { @MainActor in
            while InsightGenerationCoordinator.shared.isAnyGenerating {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            app.endBackgroundTask(bgTask)
        }
    }
}
