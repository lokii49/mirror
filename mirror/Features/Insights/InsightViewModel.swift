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
    /// This week isn't unlocked yet, but an earlier week's digest exists — show
    /// it as a fallback so the section isn't just a progress bar. `remaining` is
    /// how many more entries this week unlocks a fresh one.
    case previousWeek(Insight, remaining: Int)
    case notEnoughEntries(Int)
    case subscriptionRequired
    /// Not yet Sunday — on-demand generation is gated to match the background pre-gen task's
    /// own Sunday-only rule (see loadWeeklyDigest), so this now covers the real "wait for the
    /// week to finish" case, not just an in-flight background task as the name might suggest.
    /// Its existing card copy ("Available each Sunday morning... generates overnight") was
    /// already exactly this message — this case was declared but never actually set before.
    case pendingNightlyGeneration
    case modelNotInstalled
    /// `insight.content == InsightService.weeklyDigestUngroundedFallback` — detected by content
    /// equality (no schema change) rather than `.loaded`, so the view can show an honest message
    /// and a real retry action instead of rendering fabricated-content-shaped-honest-text as if
    /// it were a normal digest with nothing to do about it.
    case groundingFallback(Insight)
    case error(String)
}

enum MonthlyReportState {
    case idle
    case loading
    case loaded(Insight)
    /// Not yet in DateHelpers.isInLastWeekOfMonth's window — entry count doesn't matter here,
    /// generation simply hasn't opened for the month yet. Replaces the old
    /// `notEnoughEntries(remaining:total:)`, which could misleadingly tell a user with plenty of
    /// entries to "write N more" when the real blocker was purely the date, not the count.
    case waitingForMonthEnd(entryCount: Int)
    case endOfMonthTooFewEntries(count: Int)
    case subscriptionRequired
    case pendingNightlyGeneration
    case modelNotInstalled
    /// Same shape as DigestState.groundingFallback — see its doc comment.
    case groundingFallback(Insight)
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

    func loadWeeklyDigest(entries: [Entry], insights: [Insight], context: ModelContext, forceRegenerate: Bool = false) async {
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
        if !forceRegenerate, let cached = cachedThisWeek {
            let stale = InsightService.weeklyDigestIsStale(
                generatedAt: cached.generatedAt,
                newestWeekEntry: weekEntries.map(\.createdAt).max()
            )
            guard stale else {
                // A cached fallback insight's whole point is "try again" — but retrying needs
                // the model, so if it isn't available right now (e.g. still downloading),
                // showing an actionable "Try Again" button is misleading: tapping it would just
                // land on .modelNotInstalled anyway. Show that directly instead. A normal
                // (non-fallback) cached insight has nothing to redo, so model availability is
                // irrelevant there — this check only applies to the fallback branch.
                if InsightService.isUngroundedFallback(cached.content) {
                    digestState = mirrorApp.modelAvailable() ? .groundingFallback(cached) : .modelNotInstalled
                } else {
                    digestState = .loaded(cached)
                }
                return
            }
            // fall through to regenerate
        }

        // On-demand generation is gated to Sunday, matching the background pre-gen task's own
        // rule (mirrorApp.swift's Sunday-only calls into runWeeklyDigestIfNeeded) — without this,
        // opening Insights on, say, a Tuesday with 3+ entries already written generates a
        // "weekly" digest that only reflects 1-2 days of the week. Same premature-generation
        // issue the monthly report had before isInLastWeekOfMonth. forceRegenerate (the user's
        // own "Try Again" tap on an existing grounding-fallback digest) bypasses this: a digest
        // already exists for this week by definition in that case, so the week-completeness
        // concern this gate exists for doesn't apply to re-rolling it.
        guard forceRegenerate || DateHelpers.isSunday() else {
            digestState = .pendingNightlyGeneration
            return
        }

        guard weekEntries.count >= InsightService.weeklyDigestMinimumWeekEntries else {
            let remaining = InsightService.weeklyDigestMinimumWeekEntries - weekEntries.count
            // Fall back to the most recent earlier week's digest until this week
            // has enough entries — better than a bare "1/3" progress bar.
            if let prior = insights
                .filter({ $0.type == .weeklyDigest && $0.periodIdentifier != thisWeek })
                .max(by: { $0.generatedAt < $1.generatedAt }) {
                digestState = .previousWeek(prior, remaining: remaining)
            } else {
                digestState = .notEnoughEntries(remaining)
            }
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
            digestState = InsightService.isUngroundedFallback(text) ? .groundingFallback(insight) : .loaded(insight)
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

        // Generation is gated on being in the last week of the month FIRST — a report about
        // "this month" generated from only the first two weeks isn't actually a monthly report,
        // no matter how many entries went into it. Entry count is only checked once that's true.
        guard DateHelpers.isInLastWeekOfMonth(now) else {
            monthlyReportState = .waitingForMonthEnd(entryCount: thisMonthEntries.count)
            return
        }

        guard thisMonthEntries.count >= InsightService.monthlyReportMinimumEntries else {
            monthlyReportState = .endOfMonthTooFewEntries(count: thisMonthEntries.count)
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
            // Same reasoning as loadWeeklyDigest's cache-serve branch: a cached fallback's "Try
            // Again" needs the model, so don't show it as actionable when the model isn't ready.
            if InsightService.isUngroundedFallback(cached.content) {
                monthlyReportState = mirrorApp.modelAvailable() ? .groundingFallback(cached) : .modelNotInstalled
            } else {
                monthlyReportState = .loaded(cached)
            }
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
            monthlyReportState = InsightService.isUngroundedFallback(text) ? .groundingFallback(insight) : .loaded(insight)
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

    // Foundation Models needs no download at all, so it's checked first — without this an
    // FM-capable device (iOS 26+, Apple Intelligence on, eligible hardware) would gate Ask on
    // downloading Gemma even though FM alone can generate immediately. Below that: bundled-
    // resource check + ModelDownloadManager's byte-verified install check — stronger than the
    // bare mirrorApp.modelAvailable() fileExists used elsewhere in this file, since a
    // truncated/corrupt model file must not unlock Ask's chat UI.
    private func isAskModelReady() -> Bool {
        if FoundationModelEngine.isAvailable { return true }
        if Bundle.main.url(forResource: LocalLLMService.modelFileName, withExtension: LocalLLMService.modelExtension) != nil {
            return true
        }
        return (try? ModelDownloadManager.installedModelExists()) ?? false
    }
}

func friendlyLLMError(_ error: Error) -> String {
    switch error {
    case InsightError.incompleteResponse:
        return String(localized: "MirrorNotes couldn't finish the reflection. Tap retry — it usually works on the next try.")
    case InsightError.emptyResponse:
        return String(localized: "MirrorNotes didn't get a response. Tap retry in a moment.")
    case InsightError.serviceUnavailable:
        return String(localized: "Something went wrong. Mirror will try again tonight while your phone charges.")
    default:
        return String(localized: "Something went wrong. Tap retry or come back in a moment.")
    }
}
