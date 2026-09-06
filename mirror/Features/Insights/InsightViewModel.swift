import SwiftUI
import SwiftData

enum NudgeState {
    case idle
    case loading
    case loaded(Insight)
    case needsMoreEntries(Int)
    case subscriptionRequired
    case pendingNightlyGeneration
    case modelNotInstalled
    case error(String)
}

enum DigestState {
    case idle
    case loading
    case loaded(Insight)
    case notEnoughEntries(Int)
    case subscriptionRequired
    case pendingNightlyGeneration
    case modelNotInstalled
    case error(String)
}

enum MonthlyReportState {
    case idle
    case loading
    case loaded(Insight)
    case notEnoughEntries(remaining: Int, total: Int)
    case endOfMonthTooFewEntries(count: Int)
    case subscriptionRequired
    case pendingNightlyGeneration
    case modelNotInstalled
    case error(String)
}

enum AskState: Equatable {
    static let minimumEntries = 7

    case idle
    case notEnoughEntries(remaining: Int)
    case modelNotInstalled
    case subscriptionRequired
    case ready
}

@MainActor
@Observable
final class InsightViewModel {
    var nudgeState: NudgeState = .idle
    var digestState: DigestState = .idle
    var monthlyReportState: MonthlyReportState = .idle
    var askState: AskState = .idle

    // Ask has no natural period/cache identity (it's a running chat, not one insight
    // per week/month) — once entries/model clear the bar they stay cleared for the
    // session instead of re-locking the chat on a transient dip (e.g. deleting an entry).
    private var hasEnoughEntriesEverConfirmed = false
    private var modelReadyEverConfirmedForAsk = false

    // MARK: - Daily Nudge
    // Cache-read-only: generation happens in mirrorApp.preGenerateInsightsIfNeeded (app-active)
    // and the nightly BGProcessingTask. Views never trigger LLM directly.

    func loadNudge(entries: [Entry], insights: [Insight], context: ModelContext) async {
        let newState = resolvedNudgeState(entries: entries, insights: insights)
        // Both entries.count and insights.count onChange fire in the same frame,
        // producing two back-to-back synchronous calls. Only write if state actually changed
        // to avoid "tried to update multiple times per frame" warnings.
        if nudgeState != newState { nudgeState = newState }
    }

    private func resolvedNudgeState(entries: [Entry], insights: [Insight]) -> NudgeState {
        let today = DateHelpers.dayIdentifier(for: Date())
        let coordinatorKey = "nudge_\(today)"

        guard entries.count >= 3 else {
            return .needsMoreEntries(3 - entries.count)
        }

        let hasSeenFirstNudge = insights.contains { $0.type == .dailyNudge }
        if hasSeenFirstNudge && !SubscriptionService.shared.isSubscribed {
            return .subscriptionRequired
        }

        if let cached = insights.first(where: {
            $0.type == .dailyNudge && $0.periodIdentifier == today
        }) {
            return .loaded(cached)
        }

        // Pre-gen (mirrorApp.preGenerateInsightsIfNeeded) is actively running — show spinner.
        // onChange(of: insights.count) will re-call once it lands.
        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            return .loading
        }

        guard mirrorApp.modelAvailable() else {
            return .modelNotInstalled
        }

        return .pendingNightlyGeneration
    }

    // MARK: - Weekly Digest
    // On-demand if no cache. Background Sunday task pre-generates so it's ready on wake.

    func loadWeeklyDigest(entries: [Entry], insights: [Insight], context: ModelContext) async {
        let thisWeek = DateHelpers.weekIdentifier(for: Date())
        let coordinatorKey = "digest_\(thisWeek)"

        guard SubscriptionService.shared.isSubscribed else {
            digestState = .subscriptionRequired
            return
        }

        // The digest is "this week" — gate on entries written this week, not lifetime.
        let weekEntries = entries.filter { DateHelpers.weekIdentifier(for: $0.createdAt) == thisWeek }
        // Newest row wins; a stale digest is superseded by a fresh insert, never
        // deleted (a CloudKit-synced Insight deletion can hand a second device a
        // tombstoned object). Matches the monthly report's non-destructive approach.
        let cachedThisWeek = insights
            .filter { $0.type == .weeklyDigest && $0.periodIdentifier == thisWeek }
            .max { $0.generatedAt < $1.generatedAt }

        // Serve the existing digest for this week unless it's gone stale (24h
        // cooldown elapsed AND newer entries since) — serving before the count
        // gate means deleting an entry after it generated doesn't blank it.
        if let cached = cachedThisWeek {
            let stale = InsightService.weeklyDigestIsStale(
                generatedAt: cached.generatedAt,
                newestWeekEntry: weekEntries.map(\.createdAt).max()
            )
            guard stale else {
                digestState = .loaded(cached)
                return
            }
            // fall through to regenerate
        }

        guard weekEntries.count >= InsightService.weeklyDigestMinimumWeekEntries else {
            digestState = .notEnoughEntries(InsightService.weeklyDigestMinimumWeekEntries - weekEntries.count)
            return
        }

        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            digestState = .loading
            return
        }

        guard mirrorApp.modelAvailable() else {
            digestState = .modelNotInstalled
            return
        }

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            digestState = .loading
            return
        }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        digestState = .loading
        do {
            let (text, engine) = try await InsightService.generateWeeklyDigest(weekEntries: weekEntries, allEntries: entries)
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            WidgetBridge.syncWeeklyDigest(from: context)
            digestState = .loaded(insight)
            await NotificationService.scheduleWeeklyDigest()
        } catch {
            digestState = .error(friendlyLLMError(error))
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

        let isMonthEnd = DateHelpers.isInLastThreeDaysOfMonth(now)
        let minimumEntries = isMonthEnd ? 10 : 20

        if isMonthEnd && thisMonthEntries.count < 10 {
            monthlyReportState = .endOfMonthTooFewEntries(count: thisMonthEntries.count)
            return
        }

        guard thisMonthEntries.count >= minimumEntries else {
            monthlyReportState = .notEnoughEntries(remaining: minimumEntries - thisMonthEntries.count, total: minimumEntries)
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
            monthlyReportState = .modelNotInstalled
            return
        }

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            monthlyReportState = .loading
            return
        }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        monthlyReportState = .loading
        do {
            let (text, engine) = try await InsightService.generateMonthlyReport(
                monthEntries: thisMonthEntries, allEntries: entries
            )
            let insight = Insight(type: .monthlyReport, content: text, periodIdentifier: thisMonth, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            WidgetBridge.syncMonthlyReport(from: context)
            monthlyReportState = .loaded(insight)
            await NotificationService.scheduleMonthlyReportReminder()
        } catch {
            monthlyReportState = .error(friendlyLLMError(error))
        }
    }

    // MARK: - Ask
    // Gating only — Ask is chat-style (per-question, user-triggered), not one cached
    // insight per period, so there's no .loading/.loaded case here. AskView reads
    // askState to decide which screen to show, then calls InsightService.ask directly.

    func loadAskState(entries: [Entry]) {
        let newState = resolvedAskState(entries: entries)
        if askState != newState { askState = newState }
    }

    private func resolvedAskState(entries: [Entry]) -> AskState {
        guard SubscriptionService.shared.isSubscribed else { return .subscriptionRequired }

        if entries.count >= AskState.minimumEntries { hasEnoughEntriesEverConfirmed = true }
        guard hasEnoughEntriesEverConfirmed else {
            return .notEnoughEntries(remaining: AskState.minimumEntries - entries.count)
        }

        if isAskModelReady() { modelReadyEverConfirmedForAsk = true }
        guard modelReadyEverConfirmedForAsk else { return .modelNotInstalled }

        return .ready
    }

    // Bundled-resource check + ModelDownloadManager's byte-verified install check —
    // stronger than the bare mirrorApp.modelAvailable() fileExists used elsewhere in
    // this file, since a truncated/corrupt model file must not unlock Ask's chat UI.
    private func isAskModelReady() -> Bool {
        if Bundle.main.url(forResource: LocalLLMService.modelFileName, withExtension: LocalLLMService.modelExtension) != nil {
            return true
        }
        return (try? ModelDownloadManager.installedModelExists()) ?? false
    }
}

func friendlyLLMError(_ error: Error) -> String {
    switch error {
    case InsightError.incompleteResponse:
        return String(localized: "Mirror couldn't finish the reflection. Tap retry — it usually works on the next try.")
    case InsightError.emptyResponse:
        return String(localized: "Mirror didn't get a response. Tap retry in a moment.")
    case InsightError.serviceUnavailable:
        return String(localized: "Something went wrong. Mirror will try again tonight while your phone charges.")
    default:
        return String(localized: "Something went wrong. Tap retry or come back in a moment.")
    }
}
