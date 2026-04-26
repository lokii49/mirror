import SwiftUI
import SwiftData
import BackgroundTasks

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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                scheduleWeeklyDigestTask()
            }
        }
        .backgroundTask(.appRefresh("com.lokesh.mirror.weeklyDigest")) {
            await runWeeklyDigestIfNeeded()
        }
    }

    // MARK: - BGAppRefreshTask scheduling

    private func scheduleWeeklyDigestTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.lokesh.mirror.weeklyDigest")
        request.earliestBeginDate = nextSunday7AM()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func nextSunday7AM() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 1 // Sunday
        components.hour = 7
        components.minute = 0
        components.second = 0
        guard var next = calendar.date(from: components) else { return now }
        if next <= now {
            next = calendar.date(byAdding: .weekOfYear, value: 1, to: next) ?? next
        }
        return next
    }

    // MARK: - Background digest generation

    @MainActor
    private func runWeeklyDigestIfNeeded() async {
        let context = sharedModelContainer.mainContext
        let thisWeek = DateHelpers.weekIdentifier(for: Date())

        // Skip if digest already exists this week
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == thisWeek }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        guard !existing.contains(where: { $0.type == .weeklyDigest }) else {
            scheduleWeeklyDigestTask()
            return
        }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries = (try? context.fetch(entryDescriptor)) ?? []

        guard entries.count >= 5,
              SubscriptionService.shared.isSubscribed,
              let token = KeychainManager.load() else {
            scheduleWeeklyDigestTask()
            return
        }

        do {
            let text = try await InsightService.generateWeeklyDigest(entries: entries, token: token)
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek)
            context.insert(insight)
            try? context.save()
        } catch {
            // Non-fatal — retry next week
        }

        scheduleWeeklyDigestTask()
    }
}
