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

    // MARK: - Try Again while a generation is already in flight (2026-09-26 device recording)
    //
    // App-open pre-gen held the nudge coordinator key while the user tapped Try Again; each tap
    // hit coordinator-claimed, returned instantly, and resolvedNudgeState put the cached
    // fallback card straight back — Try Again looked dead for ~14s.

    private func insertThreeEntries(into context: ModelContext) throws {
        for text in ["Walked to the market early.", "Long call with my brother.", "Finished the bookshelf."] {
            context.insert(Entry(text: text))
        }
        try context.save()
    }

    private func nudgeKey() -> String { "nudge_\(todayIdentifier())" }

    @Test func fallbackCached_whileGenerationInFlight_showsLoadingNotFallback() async throws {
        let context = try makeContext()
        try insertThreeEntries(into: context)
        context.insert(Insight(type: .dailyNudge, content: InsightService.dailyNudgeUngroundedFallback, periodIdentifier: todayIdentifier()))
        try context.save()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let viewModel = InsightViewModel()

        #expect(InsightGenerationCoordinator.shared.claim(key: nudgeKey()))
        var released = false
        defer { if !released { InsightGenerationCoordinator.shared.release(key: nudgeKey()) } }

        await viewModel.loadNudge(entries: entries, insights: try context.fetch(FetchDescriptor<Insight>()), context: context)
        #expect(viewModel.nudgeState == .loading)

        InsightGenerationCoordinator.shared.release(key: nudgeKey())
        released = true
        await viewModel.loadNudge(entries: entries, insights: try context.fetch(FetchDescriptor<Insight>()), context: context)
        guard case .groundingFallback = viewModel.nudgeState else {
            Issue.record("expected .groundingFallback once nothing is in flight, got \(viewModel.nudgeState)")
            return
        }
    }

    @Test func retryNudge_waitsForInFlightGeneration_insteadOfBouncingBack() async throws {
        let context = try makeContext()
        try insertThreeEntries(into: context)
        let fallback = Insight(type: .dailyNudge, content: InsightService.dailyNudgeUngroundedFallback, periodIdentifier: todayIdentifier())
        fallback.generatedAt = Date().addingTimeInterval(-60)
        context.insert(fallback)
        try context.save()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let insights = try context.fetch(FetchDescriptor<Insight>())
        let viewModel = InsightViewModel()

        #expect(InsightGenerationCoordinator.shared.claim(key: nudgeKey()))
        var released = false
        defer { if !released { InsightGenerationCoordinator.shared.release(key: nudgeKey()) } }

        var retryFinished = false
        let retry = Task { @MainActor in
            await viewModel.retryNudge(entries: entries, insights: insights, context: context)
            retryFinished = true
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!retryFinished, "retry must wait on the in-flight generation, not return immediately")
        #expect(viewModel.nudgeState == .loading)

        // The in-flight run lands a real reflection. Inserting it BEFORE release also means
        // runDailyNudgeIfNeeded exits at its newestToday-is-real gate and never touches the
        // model — the simulator may have Gemma installed from other suites.
        context.insert(Insight(type: .dailyNudge, content: "You finished the bookshelf after the long call with your brother.", periodIdentifier: todayIdentifier()))
        try context.save()
        InsightGenerationCoordinator.shared.release(key: nudgeKey())
        released = true
        await retry.value

        #expect(retryFinished)
        switch viewModel.nudgeState {
        case .loaded, .subscriptionRequired: break   // real row wins; paywall depends on test-host tier
        default: Issue.record("expected the real reflection to resolve, got \(viewModel.nudgeState)")
        }
    }

    // The 2026-09-25 empty-context regression (locked-device decrypt failure defeating every
    // grounding guard) is covered by GroundingSampleHarness.test_generateNudge_
    // allEntriesUndecryptable_throwsWithoutGenerating instead of here — that version calls
    // InsightService.generateNudge directly with no ModelContainer at all, so it needs neither
    // this file's CloudKit-mirroring setup nor the `cloudKitDatabase: .none` fix above.
}
