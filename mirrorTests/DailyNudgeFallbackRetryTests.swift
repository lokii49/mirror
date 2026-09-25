import Testing
import SwiftData
import Foundation
@testable import mirror

// Regression coverage for the "queue" question raised 2026-09-17: once a daily nudge fell
// back (grounding check failed 3x), it was a dead end — hasDailyNudgeForToday/
// todaysDailyNudgeText treated the fallback row as a real nudge, which fed straight into
// push-notification copy ("insightReady") promising a reflection that was actually the
// "couldn't confirm" message. It also blocked mirrorApp.runDailyNudgeIfNeeded's own cache
// guard from ever retrying that day, including in the nightly BGProcessingTask's low-pressure
// (charging, idle) window. Fixed by having both helpers ignore fallback-content rows and pick
// the newest real one — same non-destructive "insert, don't delete" pattern weekly digest and
// monthly report already use for their own groundingFallback retries.
// .serialized: without it, Swift Testing's default in-suite parallelism crashed the host
// process outright — concurrent in-memory ModelContainers each spin up their own Core Data +
// CloudKit mirroring setup, and tearing several down at once raced hard enough to kill the run
// ("Crash: mirror", NSCocoaErrorDomain 134060 "store was removed from the coordinator"). This
// alone isn't a complete fix: Xcode's own simulator-clone-level parallelism (separate from
// Swift Testing's in-process scheduling, and what .serialized has no control over) can still
// reproduce the same crash even with just this suite selected via -only-testing — matches this
// repo's existing "Xcode 27 beta sim instability" issue, not a new one. Confirmed passing with
// -parallel-testing-enabled NO; if this suite flakes in CI, run it that way rather than
// re-debugging it as a code problem.
@Suite(.serialized)
@MainActor
struct DailyNudgeFallbackRetryTests {

    private func makeContext() throws -> ModelContext {
        // cloudKitDatabase: .none — see the 2026-09-25 correction in the trailing comment below.
        // Without it, this in-memory container still attempts CloudKit mirroring setup against
        // this CloudKit-entitled test host with no iCloud account signed in, which is what the
        // header comment's "store was removed from the coordinator" crash traces back to.
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Entry.self, Insight.self, configurations: config)
        return ModelContext(container)
    }

    private func todayIdentifier() -> String {
        DateHelpers.dayIdentifier(for: Date())
    }

    @Test func onlyFallbackInsightForToday_hasDailyNudgeForToday_isFalse() throws {
        let context = try makeContext()
        let fallback = Insight(
            type: .dailyNudge,
            content: InsightService.dailyNudgeUngroundedFallback,
            periodIdentifier: todayIdentifier()
        )
        context.insert(fallback)
        try context.save()

        #expect(!mirrorApp.hasDailyNudgeForToday(context: context))
        #expect(mirrorApp.todaysDailyNudgeText(context: context) == nil)
    }

    // The retry path inserts a new row rather than deleting the fallback (CloudKit-safe, same
    // reasoning as weekly digest/monthly report) — so today can briefly hold both. The real one,
    // regardless of insertion order, must win.
    @Test func realNudgeAlongsideOlderFallback_winsRegardlessOfInsertionOrder() throws {
        let context = try makeContext()
        let today = todayIdentifier()

        let fallback = Insight(type: .dailyNudge, content: InsightService.dailyNudgeUngroundedFallback, periodIdentifier: today)
        fallback.generatedAt = Date().addingTimeInterval(-60)
        context.insert(fallback)

        let real = Insight(type: .dailyNudge, content: "You mentioned the drive home from your sister's tonight.", periodIdentifier: today)
        real.generatedAt = Date()
        context.insert(real)
        try context.save()

        #expect(mirrorApp.hasDailyNudgeForToday(context: context))
        #expect(mirrorApp.todaysDailyNudgeText(context: context) == real.content)
    }

    @Test func noInsightYetToday_hasDailyNudgeForToday_isFalse() throws {
        let context = try makeContext()
        #expect(!mirrorApp.hasDailyNudgeForToday(context: context))
        #expect(mirrorApp.todaysDailyNudgeText(context: context) == nil)
    }

    // The 2026-09-25 empty-context regression (locked-device decrypt failure defeating every
    // grounding guard) is covered by GroundingSampleHarness.test_generateNudge_
    // allEntriesUndecryptable_throwsWithoutGenerating instead of here — that version calls
    // InsightService.generateNudge directly with no ModelContainer at all, so it needs neither
    // this file's CloudKit-mirroring setup nor the `cloudKitDatabase: .none` fix above.
}
