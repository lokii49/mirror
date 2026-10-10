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
    /// Same shape as DigestState.groundingFallback / MonthlyReportState.groundingFallback —
    /// `insight.content == InsightService.dailyNudgeUngroundedFallback`, detected by content
    /// equality so the view shows an honest message and a real retry instead of rendering it
    /// as an ordinary reflection.
    case groundingFallback(Insight)
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
    /// Its existing card copy ("Available Sunday mornings... generates overnight") was
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

    /// The one exception to "views never trigger LLM directly": a user's explicit "Try Again"
    /// tap on a groundingFallback card is deliberate intent, same as the nightly background
    /// task's own bypassTimeGate — so this re-enters the exact same generation entry point
    /// (mirrorApp.runDailyNudgeIfNeeded) rather than duplicating its gates here.
    ///
    /// `userInitiatedRetry: true` matters, not just `bypassTimeGate`: a real device case
    /// (2026-09-20) showed Try Again doing nothing, repeatably — the account's one real nudge
    /// had a `generatedAt` that happened not to be older than the user's newest entry at the
    /// moment they tapped, so the "no new writing since the last real nudge" gate silently
    /// returned before generation ever ran. That gate is meant to stop automatic regeneration
    /// churn (nightly task, app-open pre-gen), not a deliberate tap — same reasoning digest/
    /// monthly's `forceRegenerate` already uses.
    ///
    /// After generation, re-fetches `Insight` directly from `context` rather than reusing the
    /// `insights` parameter — that array is a plain snapshot captured when the caller's button
    /// closure fired, not a live query, so it still doesn't contain the row `runDailyNudgeIfNeeded`
    /// just inserted a moment earlier in this same function. Another real device case (2026-09-20):
    /// generation succeeded (a real, grounded reflection saved) but the card kept showing the old
    /// fallback until the user manually left and reopened Insights — SwiftData's own `@Query`
    /// eventually notices the new row and fires `onChange(of: insights.count)` too, but not
    /// promptly enough to trust as the only path. Fetching fresh here makes the result visible
    /// immediately regardless of that timing.
    func retryNudge(entries: [Entry], insights: [Insight], context: ModelContext) async {
        // Instant feedback — generation is a cold model load plus inference (can run 10s of
        // seconds on-device), and runDailyNudgeIfNeeded gives no progress callback of its own.
        // Without this the button looks dead for that whole window.
        nudgeState = .loading
        // Real device case (2026-09-26): app-open pre-gen was already mid-generation when the
        // user tapped, so runDailyNudgeIfNeeded hit its coordinator-claimed gate and returned
        // instantly — the card flashed .loading for a frame and snapped back to the fallback,
        // repeatedly, for ~14s. Wait for that in-flight run first, THEN run our own: if it
        // landed a real row, runDailyNudgeIfNeeded's newestToday-is-real gate returns early;
        // if it landed another fallback (or threw), the tap still gets a genuine fresh attempt
        // instead of being swallowed.
        let key = "nudge_\(DateHelpers.dayIdentifier(for: Date()))"
        await InsightGenerationCoordinator.shared.waitUntilReleased(key)
        await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true, userInitiatedRetry: true)
        let freshInsights = (try? context.fetch(FetchDescriptor<Insight>())) ?? insights
        await loadNudge(entries: entries, insights: freshInsights, context: context)
    }

    private func resolvedNudgeState(entries: [Entry], insights: [Insight]) -> NudgeState {
        let today = DateHelpers.dayIdentifier(for: Date())
        let coordinatorKey = "nudge_\(today)"

        // Readable entries only, as `runDailyNudgeIfNeeded` counts them: with a photo-only entry or
        // a failed transcription among three, the card promised a reflection the runner never made
        // (backlog A11). Stops after three, so it decrypts at most a few entries.
        let readable = entries.lazy.filter(InsightService.hasReadableContext).prefix(3).count
        guard readable >= 3 else {
            return .needsMoreEntries(3 - readable)
        }

        let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        // A reflection still current for the card: today's, or (next morning) one about
        // yesterday's or today's writing with nothing written since.
        func isCurrent(_ nudge: Insight) -> Bool {
            if nudge.periodIdentifier == today { return true }
            guard nudge.generatedAt >= startOfYesterday,
                  !entries.contains(where: { $0.createdAt > nudge.generatedAt }),
                  let aboutDay = InsightService.reflectedDay(of: nudge, entriesNewestFirst: entries.sorted { $0.createdAt > $1.createdAt })
            else { return false }
            return aboutDay >= startOfYesterday
        }

        // The first reflection is free (CLAUDE.md, staged onboarding): a free user sees it, and
        // the paywall follows it. This used to return .subscriptionRequired as soon as any real
        // reflection existed, so the first one was never shown and that paywall never fired. A
        // fallback doesn't count as "seen" either.
        let realNudges = insights.filter { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
        if !realNudges.isEmpty && !SubscriptionService.shared.isSubscribed {
            if realNudges.count == 1, let first = realNudges.first, isCurrent(first) { return .loaded(first) }
            return .subscriptionRequired
        }

        // Newest wins, not first: a retried fallback inserts a new row for today rather than
        // deleting the old one (same non-destructive pattern digest/monthly already use), so
        // today can briefly hold two rows while the retry's result lands.
        if let cached = insights
            .filter({ $0.type == .dailyNudge && $0.periodIdentifier == today })
            .max(by: { $0.generatedAt < $1.generatedAt }) {
            guard InsightService.isUngroundedFallback(cached.content) else { return .loaded(cached) }
            // A fallback row with a generation actively running is stale by definition — show
            // progress, not a "Couldn't confirm" card whose Try Again would just queue behind
            // the run already in flight. InsightView re-resolves on the coordinator's release.
            return InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) ? .loading : .groundingFallback(cached)
        }

        // Pre-gen (mirrorApp.preGenerateInsightsIfNeeded) is actively running — show spinner.
        // onChange(of: insights.count) will re-call once it lands.
        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            return .loading
        }

        // With a second reflection allowed on the day of writing (2026-09-28), an evening
        // writer's reflection lands that evening, so the next morning has no row for today until
        // they write again. Keep it on the card (labelled with its day) rather than a "generates
        // at 8:00" card nothing new is coming for, but only while it's about yesterday's or
        // today's writing and nothing has been written since: someone who skipped yesterday
        // still gets the "write today" card, not a reflection about the day before.
        if let latest = realNudges.max(by: { $0.generatedAt < $1.generatedAt }), isCurrent(latest) {
            return .loaded(latest)
        }

        // Foundation Models alone counts as available, but Russian runs only on Gemma (A15).
        guard mirrorApp.modelAvailable(),
              LocalLLMService.isGemmaModelAvailable || !InsightService.nudgeNeedsGemma(entries: entries) else {
            return .modelNotInstalled
        }

        return .pendingNightlyGeneration
    }

    // MARK: - Weekly Digest
    // On-demand if no cache. Background Sunday task pre-generates so it's ready on wake.

    func loadWeeklyDigest(entries: [Entry], insights: [Insight], context: ModelContext, forceRegenerate: Bool = false) async {
        let thisWeek = DateHelpers.digestWeekIdentifier(for: DateHelpers.now())
        let coordinatorKey = "digest_\(thisWeek)"

        guard SubscriptionService.shared.isSubscribed else {
            digestState = .subscriptionRequired
            return
        }

        // The digest is "this week" — gate on entries written this week, not lifetime.
        // Readable only, as the runner and generator count them (backlog A11).
        let weekEntries = entries
            .filter { DateHelpers.digestWeekIdentifier(for: $0.createdAt) == thisWeek }
            .filter(InsightService.hasReadableContext)
        // Newest row wins; a stale digest is superseded by a fresh insert, never
        // deleted (a CloudKit-synced Insight deletion can hand a second device a
        // tombstoned object). Matches the monthly report's non-destructive approach.
        let cachedThisWeek = insights
            .filter { $0.type == .weeklyDigest && $0.periodIdentifier == thisWeek }
            .max { $0.generatedAt < $1.generatedAt }

        // Advisor-audit finding: every gate below this point used to end the function outright
        // when it blocked — but a stale cached digest is still a real, readable digest. Losing
        // it the moment ANY gate (entries/model/day) fails discards content the user was already
        // reading, just because the cache also happens to be due for a refresh. "Stale beats
        // none" the same way generateNudge's own fail-open logic already treats a flawed nudge —
        // this closure is the shared fallback every gate below reaches for before giving up.
        func servingCachedOr(_ blocked: @autoclosure () -> DigestState) -> DigestState {
            guard let cached = cachedThisWeek else { return blocked() }
            return InsightService.isUngroundedFallback(cached.content) ? .groundingFallback(cached) : .loaded(cached)
        }

        // Serve the existing digest for this week unless it's gone stale (24h
        // cooldown elapsed AND newer entries since) — serving before the count
        // gate means deleting an entry after it generated doesn't blank it.
        if !forceRegenerate, let cached = cachedThisWeek {
            let stale = InsightService.weeklyDigestIsStale(
                generatedAt: InsightService.stalenessBaseline(cachedAt: cached.generatedAt, .weeklyDigest, period: thisWeek),
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

        // Entry count checked BEFORE the Sunday gate below — same priority daily nudge's
        // needsMoreEntries and monthly's endOfMonthTooFewEntries both give the count. A
        // first-time user with 1 entry on a Tuesday should see "2 more entries to go" (something
        // to act on right now), not "available Sunday mornings" — the day-gate only matters once
        // there's actually enough material to generate from. forceRegenerate bypasses this too:
        // it's only ever triggered from an existing groundingFallback card's Try Again, so a
        // digest already exists for this week — an explicit user retry shouldn't be blocked by
        // an entry count dropping (e.g. a deleted entry) after that digest was generated.
        guard forceRegenerate || weekEntries.count >= InsightService.weeklyDigestMinimumWeekEntries else {
            let remaining = InsightService.weeklyDigestMinimumWeekEntries - weekEntries.count
            // Fall back to the most recent earlier week's digest until this week
            // has enough entries — better than a bare "1/3" progress bar.
            let notEnoughState: DigestState
            if let prior = insights
                .filter({ $0.type == .weeklyDigest && $0.periodIdentifier != thisWeek })
                .max(by: { $0.generatedAt < $1.generatedAt }) {
                notEnoughState = .previousWeek(prior, remaining: remaining)
            } else {
                notEnoughState = .notEnoughEntries(remaining)
            }
            digestState = servingCachedOr(notEnoughState)
            return
        }

        // Checked before the Sunday gate below: if the model isn't available at all, "Available
        // Sunday mornings" is just as misleading as the day-gate promise was for a stale
        // groundingFallback insight (see that check above) — waiting for Sunday wouldn't help
        // either, since there's still no model to generate with once it arrives. The real
        // blocker is named directly instead.
        guard mirrorApp.modelAvailable() else {
            digestState = servingCachedOr(.modelNotInstalled)
            return
        }

        // On-demand generation is gated to Sunday, matching the background pre-gen task's own
        // rule (mirrorApp.swift's Sunday-only calls into runWeeklyDigestIfNeeded) — without this,
        // opening Insights on, say, a Tuesday with 3+ entries already written generates a
        // "weekly" digest that only reflects 1-2 days of the week. Same premature-generation
        // issue the monthly report had before isInLastWeekOfMonth. Checked only once there's
        // enough material to generate from (see the entry-count gate above) — forceRegenerate
        // (the user's own "Try Again" tap on an existing grounding-fallback digest) bypasses
        // this too: a digest already exists for this week by definition in that case, so the
        // week-completeness concern this gate exists for doesn't apply to re-rolling it.
        guard forceRegenerate || DateHelpers.isSunday() else {
            digestState = servingCachedOr(.pendingNightlyGeneration)
            return
        }

        if InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) {
            digestState = .loading
            return
        }

        // Saved encrypted: with the key unreadable, show the error card instead of a plaintext row.
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: false) else {
            digestState = .error(friendlyLLMError(InsightError.serviceUnavailable("content key unavailable")))
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
            if let cached = cachedThisWeek, InsightService.keepsRealRowOverFallback(newText: text, cachedContent: cached.content) {
                InsightService.recordKeptRealRow(.weeklyDigest, period: thisWeek)
                digestState = .loaded(cached)
                return
            }
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            WidgetBridge.syncWeeklyDigest(from: context)
            digestState = InsightService.isUngroundedFallback(text) ? .groundingFallback(insight) : .loaded(insight)
            await NotificationService.scheduleWeeklyDigest()
        } catch {
            // Cancelled with the view (or the app backgrounding): not an error to show. The
            // next load resolves the card again.
            if Task.isCancelled { return }
            digestState = .error(friendlyLLMError(error))
        }
    }

    // MARK: - Monthly Report
    // On-demand if no cache. Background end-of-month task pre-generates so it's ready on wake.

    func loadMonthlyReport(entries: [Entry], insights: [Insight], context: ModelContext, forceRegenerate: Bool = false) async {
        let thisMonth = DateHelpers.monthIdentifier(for: DateHelpers.now())
        let coordinatorKey = "monthlyReport_\(thisMonth)"

        let cal = Calendar.current
        let now = DateHelpers.now()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let thisMonthEntries = entries.filter { $0.createdAt >= monthStart }

        // Generation is gated on being in the last week of the month FIRST — a report about
        // "this month" generated from only the first two weeks isn't actually a monthly report,
        // no matter how many entries went into it. Entry count is only checked once that's true.
        //
        // Deliberately the OPPOSITE order from loadWeeklyDigest, which checks entry count before
        // its Sunday gate — flagged by advisor audit as an undocumented asymmetry worth calling
        // out explicitly rather than leaving the next reader to assume they match. The date-first
        // order here was the original, explicitly-requested design for monthly and is left as-is;
        // weekly's count-first order was a later, separate explicit request (a first-time user
        // with too few entries should see "N more to go", not "wait for Sunday", regardless of
        // day). Both are intentional, not a bug — they just optimize for different things: monthly
        // treats the date as the primary blocker since the wait can be weeks long either way,
        // while weekly treats entry count as primary since its wait is at most a few days and
        // showing something actionable matters more there.
        guard DateHelpers.isInLastWeekOfMonth(now) else {
            monthlyReportState = .waitingForMonthEnd(entryCount: thisMonthEntries.count)
            return
        }

        // Readable only, as the runner counts them (backlog A11). After the date gate, so the three
        // weeks of "waiting for month end" (which shows the plain count) decrypt nothing.
        let readableThisMonth = thisMonthEntries.filter(InsightService.hasReadableContext)
        guard readableThisMonth.count >= InsightService.monthlyReportMinimumEntries else {
            monthlyReportState = .endOfMonthTooFewEntries(count: readableThisMonth.count)
            return
        }

        guard SubscriptionService.shared.isDeep else {
            monthlyReportState = .subscriptionRequired
            return
        }

        // Newest wins — same non-destructive approach as loadWeeklyDigest's cachedThisWeek.
        // Computed unconditionally (not folded into the 24h freshness check below) so a >24h-old
        // report is still reachable as a stale-but-readable fallback, not just invisible once its
        // freshness window closes.
        let cachedThisMonth = insights
            .filter { $0.type == .monthlyReport && $0.periodIdentifier == thisMonth }
            .max { $0.generatedAt < $1.generatedAt }

        // Advisor-audit finding (same shape as loadWeeklyDigest's servingCachedOr, added same
        // day): the old version of this cache lookup folded the 24h freshness check directly
        // into `insights.first(where:)`'s predicate, so a report older than 24h was invisible to
        // it — not "found but stale," just gone. If the model then turned out to be unavailable
        // below, a real, readable 2-day-old report was replaced by "AI model needed" instead of
        // being served. "Stale beats none" here too.
        func servingCachedOr(_ blocked: @autoclosure () -> MonthlyReportState) -> MonthlyReportState {
            guard let cached = cachedThisMonth else { return blocked() }
            return InsightService.isUngroundedFallback(cached.content) ? .groundingFallback(cached) : .loaded(cached)
        }

        // Same staleness rule as the background runner: 24h passed AND newer writing this month (or
        // since this device's last kept-real attempt). Was 24h alone, so opening Monthly each day of
        // the last week regenerated from the same entries (backlog A8).
        if !forceRegenerate, let cached = cachedThisMonth,
           !InsightService.weeklyDigestIsStale(
               generatedAt: InsightService.stalenessBaseline(cachedAt: cached.generatedAt, .monthlyReport, period: thisMonth),
               newestWeekEntry: readableThisMonth.map(\.createdAt).max()
           ) {
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
            monthlyReportState = servingCachedOr(.modelNotInstalled)
            return
        }

        guard MirrorEncryption.canEncrypt(creatingIfNeeded: false) else {  // see loadWeeklyDigest
            monthlyReportState = .error(friendlyLLMError(InsightError.serviceUnavailable("content key unavailable")))
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
                monthEntries: readableThisMonth, allEntries: entries
            )
            if let cached = cachedThisMonth, InsightService.keepsRealRowOverFallback(newText: text, cachedContent: cached.content) {
                InsightService.recordKeptRealRow(.monthlyReport, period: thisMonth)
                monthlyReportState = .loaded(cached)
                return
            }
            let insight = Insight(type: .monthlyReport, content: text, periodIdentifier: thisMonth, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            WidgetBridge.syncMonthlyReport(from: context)
            monthlyReportState = InsightService.isUngroundedFallback(text) ? .groundingFallback(insight) : .loaded(insight)
            await NotificationService.scheduleMonthlyReportReminder()
        } catch {
            if Task.isCancelled { return }  // see loadWeeklyDigest
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
    // serviceUnavailable used to promise "Mirror will try again tonight while your phone
    // charges", but nothing retries Ask, and the nightly digest runs only on Sundays (backlog A15a).
    default:
        return String(localized: "Something went wrong. Tap retry or come back in a moment.")
    }
}
