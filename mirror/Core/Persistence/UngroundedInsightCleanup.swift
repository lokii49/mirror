import Foundation
import SwiftData

/// One-time repair pass over already-cached insights generated before the recent-scoped
/// grounding fix (2026-09-20 — see `InsightService.isUngrounded`'s doc comment). Before that
/// fix, the grounding guard only checked a nudge/digest/report against its full recent+background
/// pool (up to ~23-26 entries), which a fabrication could clear on coincidental overlap with
/// background filler once that pool grew large enough — the "rain outside... quiet moments"
/// incident this whole fix chain traces back to. A reflection generated under that gap can still
/// be sitting in SwiftData (and CloudKit-synced to other devices) rendering as a genuine
/// reflection, since `resolvedNudgeState`/`resolvedDigestState`/monthly's equivalent only
/// re-check a cached insight's exact text against the canned fallback strings — they never
/// re-run `isUngrounded` on it. Fixing generation going forward does nothing for what's already
/// cached; this closes that gap.
///
/// Gated on a UserDefaults flag, not an app-version check — runs once per device after this
/// ships, regardless of whether that device is a fresh install or an existing install updating
/// from the App Store. Each device carries its own flag, so a multi-device CloudKit user gets
/// every device cleaned independently as each one is opened.
///
/// Two safeguards against running on a store CloudKit hasn't finished syncing to yet (a fresh
/// update's first foreground can have entries still arriving) — a false "ungrounded" read here
/// would rewrite a genuine reflection's `content`, not just skip it:
/// 1. An empty store never sets the flag — it retries every foreground until there's something
///    to check, instead of a stale sync race permanently skipping the one device that needed it.
/// 2. The scan itself is deferred until at least one real backgrounding has happened since app
///    launch (`recordBackgrounding()`, called from `scenePhase == .background`), giving CloudKit
///    a chance to import before anything is inspected. Deliberately keyed to `.background`, not
///    `.active` — a system permission dialog mid-launch flips `scenePhase` .active -> .inactive
///    -> .active without ever backgrounding, which would satisfy a same-launch `.active` counter
///    and defeat the deferral on the very first cold launch. Not a guarantee — CloudKit's own
///    completion isn't observed here — but the residual risk this leaves is bounded: the only
///    effect of a false positive is a genuine reflection's cached copy showing the fallback + Try
///    Again card once, which regenerates a real one on tap. It never touches journal entries,
///    only a regenerable AI cache.
///
/// Non-destructive, same pattern as `CachedInsightRepair`: never deletes a row (a CloudKit-synced
/// delete can hand another device a tombstone). Rewrites `content` in place to the type's canned
/// fallback message, which flips it to the existing groundingFallback UI (title + message + Try
/// Again button) instead of leaving fabricated content looking like a real reflection.
enum UngroundedInsightCleanup {
    // v2: v1 shipped, and actually ran on at least one real device, while ALL THREE type checks
    // here (daily nudge via `ungroundedDailyNudges`, plus this file's own inline weekly/monthly
    // checks) still called the SCALED `isUngrounded` against a single day's/week's/month's
    // entries — too strict for that small a corpus (see `sharesNoWordWithRecent`'s doc comment;
    // that fix landed AFTER v1 had already been built, installed, and run). A v1 run could have
    // wrongly flipped genuinely-grounded insights of any of the three types to the fallback
    // message. Bumping the flag lets v2 run once more with the corrected check.
    //
    // This does NOT recover anything v1 already overwrote: `content` was rewritten in place with
    // no version history kept, so a genuine reflection v1 incorrectly replaced is gone. v2 only
    // stops further incorrect flags going forward.
    private static let flag = "mirror.didCleanUngroundedCachedInsights.v2"
    private static let backgroundingCountKey = "mirror.ungroundedCleanupBackgroundingCount"
    private static let minBackgroundings = 1

    /// Called from `scenePhase == .background`. Deliberately not `@MainActor` — backgrounding
    /// can race app teardown; this is just a UserDefaults increment.
    static func recordBackgrounding() {
        let count = UserDefaults.standard.integer(forKey: backgroundingCountKey) + 1
        UserDefaults.standard.set(count, forKey: backgroundingCountKey)
    }

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        guard UserDefaults.standard.integer(forKey: backgroundingCountKey) >= minBackgroundings else { return }

        let allInsights = (try? context.fetch(FetchDescriptor<Insight>())) ?? []
        let allEntries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        guard !allInsights.isEmpty, !allEntries.isEmpty else {
            // Don't set the flag — a device whose CloudKit sync hasn't populated entries/insights
            // yet needs to retry, not be permanently skipped.
            return
        }

        var changed = 0

        for insight in InsightService.ungroundedDailyNudges(among: allInsights, allEntries: allEntries) {
            guard !InsightService.isUngroundedFallback(insight.content) else { continue }
            insight.content = InsightService.dailyNudgeUngroundedFallback
            changed += 1
        }

        // Weekly digest / monthly report have no dedicated retroactive-audit function (unlike
        // daily nudge's `ungroundedDailyNudges`) — reconstructed inline here using each insight's
        // own `periodIdentifier` against the fixed dual grounding check.
        for insight in allInsights where insight.type == .weeklyDigest {
            guard !InsightService.isUngroundedFallback(insight.content) else { continue }
            // Computed from createdAt, not the stored `Entry.weekIdentifier` — that field
            // defaults to "" and can be unset on entries created before it existed or restored
            // via CloudKit without it, which would silently match nothing here.
            let weekEntries = allEntries.filter { DateHelpers.weekIdentifier(for: $0.createdAt) == insight.periodIdentifier }
            // Flat sharesNoWordWithRecent, not the scaled isUngrounded — a single week's entries
            // is a small corpus, same regime that regressed for the daily nudge (see that
            // function's doc comment).
            guard !weekEntries.isEmpty, InsightService.sharesNoWordWithRecent(insight.content, recentEntries: weekEntries) else { continue }
            insight.content = InsightService.weeklyDigestUngroundedFallback
            changed += 1
        }

        for insight in allInsights where insight.type == .monthlyReport {
            guard !InsightService.isUngroundedFallback(insight.content) else { continue }
            let monthEntries = allEntries.filter { DateHelpers.monthIdentifier(for: $0.createdAt) == insight.periodIdentifier }
            guard !monthEntries.isEmpty, InsightService.sharesNoWordWithRecent(insight.content, recentEntries: monthEntries) else { continue }
            insight.content = InsightService.monthlyReportUngroundedFallback
            changed += 1
        }

        do {
            if changed > 0 {
                try context.save()
                mirrorApp.syncNudgeToWidget(context: context)
                WidgetBridge.syncWeeklyDigest(from: context)
                WidgetBridge.syncMonthlyReport(from: context)
            }
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Leave the flag unset — retry on the next foreground.
        }
    }
}
