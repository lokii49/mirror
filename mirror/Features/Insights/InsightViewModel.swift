import SwiftUI
import SwiftData

enum NudgeState {
    case idle
    case loading
    case loaded(Insight)
    case needsMoreEntries(Int)
    case subscriptionRequired
    case pendingNightlyGeneration
    case error(String)
}

enum DigestState {
    case idle
    case loading
    case loaded(Insight)
    case notEnoughEntries
    case subscriptionRequired
    case pendingNightlyGeneration
    case error(String)
}

enum MonthlyReportState {
    case idle
    case loading
    case loaded(Insight)
    case notEnoughEntries(remaining: Int)
    case subscriptionRequired
    case pendingNightlyGeneration
    case error(String)
}

@MainActor
@Observable
final class InsightViewModel {
    var nudgeState: NudgeState = .idle
    var digestState: DigestState = .idle
    var monthlyReportState: MonthlyReportState = .idle

    // MARK: - Daily Nudge
    // Cache-read-only: generation happens in mirrorApp.preGenerateInsightsIfNeeded (app-active)
    // and the nightly BGProcessingTask. Views never trigger LLM directly.

    func loadNudge(entries: [Entry], insights: [Insight], context: ModelContext) async {
        let today = DateHelpers.dayIdentifier(for: Date())
        let coordinatorKey = "nudge_\(today)"

        guard entries.count >= 3 else {
            nudgeState = .needsMoreEntries(3 - entries.count)
            return
        }

        let hasSeenFirstNudge = insights.contains { $0.type == .dailyNudge }
        if hasSeenFirstNudge && !SubscriptionService.shared.isSubscribed {
            nudgeState = .subscriptionRequired
            return
        }

        if let cached = insights.first(where: {
            $0.type == .dailyNudge && $0.periodIdentifier == today
        }) {
            nudgeState = .loaded(cached)
            return
        }

        // Pre-gen (mirrorApp.preGenerateInsightsIfNeeded) is actively running — show spinner.
        // onChange(of: insights.count) will re-call once it lands.
        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            nudgeState = .loading
            return
        }

        guard mirrorApp.modelAvailable() else {
            nudgeState = .error("AI model not installed. Add the Gemma model to the app bundle in Xcode.")
            return
        }

        nudgeState = .pendingNightlyGeneration
    }

    // MARK: - Weekly Digest
    // On-demand if no cache. Background Sunday task pre-generates so it's ready on wake.

    func loadWeeklyDigest(entries: [Entry], insights: [Insight], context: ModelContext) async {
        let thisWeek = DateHelpers.weekIdentifier(for: Date())
        let coordinatorKey = "digest_\(thisWeek)"

        guard entries.count >= 5 else {
            digestState = .notEnoughEntries
            return
        }

        guard SubscriptionService.shared.isSubscribed else {
            digestState = .subscriptionRequired
            return
        }

        if let cached = insights.first(where: {
            $0.type == .weeklyDigest && $0.periodIdentifier == thisWeek
        }) {
            digestState = .loaded(cached)
            return
        }

        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            digestState = .loading
            return
        }

        guard mirrorApp.modelAvailable() else {
            digestState = .error("AI model not installed.")
            return
        }

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            digestState = .loading
            return
        }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        digestState = .loading
        do {
            let text = try await InsightService.generateWeeklyDigest(entries: entries, token: "")
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek)
            context.insert(insight)
            try? context.save()
            digestState = .loaded(insight)
            await NotificationService.scheduleWeeklyDigest()
        } catch {
            digestState = .error(error.localizedDescription)
        }
    }

    // MARK: - Monthly Report
    // On-demand if no cache. Background end-of-month task pre-generates so it's ready on wake.

    func loadMonthlyReport(entries: [Entry], insights: [Insight], context: ModelContext, forceRegenerate: Bool = false) async {
        let thisMonth = DateHelpers.monthIdentifier(for: Date())
        let coordinatorKey = "monthlyReport_\(thisMonth)"

        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let thisMonthEntries = entries.filter { $0.createdAt >= monthStart }

        guard thisMonthEntries.count >= 20 else {
            monthlyReportState = .notEnoughEntries(remaining: 20 - thisMonthEntries.count)
            return
        }

        guard SubscriptionService.shared.isDeep else {
            monthlyReportState = .subscriptionRequired
            return
        }

        if !forceRegenerate, let cached = insights.first(where: {
            $0.type == .monthlyReport && $0.periodIdentifier == thisMonth
                && Date().timeIntervalSince($0.generatedAt) < 86400
        }) {
            monthlyReportState = .loaded(cached)
            return
        }

        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            monthlyReportState = .loading
            return
        }

        guard mirrorApp.modelAvailable() else {
            monthlyReportState = .error("AI model not installed.")
            return
        }

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            monthlyReportState = .loading
            return
        }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        monthlyReportState = .loading
        do {
            let text = try await InsightService.generateMonthlyReport(
                monthEntries: thisMonthEntries, allEntries: entries, token: ""
            )
            let insight = Insight(type: .monthlyReport, content: text, periodIdentifier: thisMonth)
            context.insert(insight)
            try? context.save()
            monthlyReportState = .loaded(insight)
            await NotificationService.scheduleMonthlyReportReminder()
        } catch {
            monthlyReportState = .error(error.localizedDescription)
        }
    }
}
