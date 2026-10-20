import Testing
import SwiftData
import Foundation
@testable import mirror

/// Paid-tier gates (CLAUDE.md tiers), checked with DEBUG `debugSetTier` (every feature is free
/// until 15 November 2026, `SubscriptionService.allFeaturesFree(now:)`). Serialized with the other suites that read the shared tier.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct TierGateTests {
        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return ModelContext(try ModelContainer(for: Entry.self, Insight.self, configurations: config))
        }

        private func withTier(_ tier: SubscriptionTier, _ body: () async throws -> Void) async rethrows {
            let before = SubscriptionService.shared.tier
            SubscriptionService.shared.debugSetTier(tier)
            defer { SubscriptionService.shared.debugSetTier(before) }
            try await body()
        }

        private func entries(_ n: Int, in context: ModelContext, now: Date = Date()) -> [Entry] {
            (0..<n).map { i in
                let e = Entry(text: "Synthetic entry \(i): a walk, some work, an early night.", mood: "Content")
                e.createdAt = now.addingTimeInterval(Double(-i) * 3_600)
                context.insert(e)
                return e
            }
        }

        /// Free until paid plans start on 15 November, local time; gated from then on. The paid
        /// build is installed before that date and must not gate anyone early.
        @Test func everythingIsFreeUntilFifteenNovember() {
            let cal = Calendar.current
            let lastFreeMinute = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23, minute: 59))!
            let cutover = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
            #expect(SubscriptionService.allFeaturesFree(now: lastFreeMinute))
            #expect(!SubscriptionService.allFeaturesFree(now: cutover))
            #expect(!SubscriptionService.allFeaturesFree(now: cutover.addingTimeInterval(30 * 86_400)))
        }

        @Test func askLimitsPerTier() {
            #expect(SubscriptionService.askMonthlyLimit(for: .free) == 0)
            #expect(SubscriptionService.askMonthlyLimit(for: .core) == 15)
            #expect(SubscriptionService.askMonthlyLimit(for: .deep) == .max)
        }

        @Test func talkItOutIsHiddenOnFree() {
            #expect(!SubscriptionService.offersTalkItOut(for: .free))
            #expect(SubscriptionService.offersTalkItOut(for: .core))
            #expect(SubscriptionService.offersTalkItOut(for: .deep))
        }

        /// Free keeps reading what was already made (owner, 2026-10-20): the card shows the newest
        /// reflection while it's current, however many there are.
        @Test func freeKeepsReadingTheirLatestReflection() async throws {
            let context = try makeContext()
            let all = entries(3, in: context)
            let today = DateHelpers.dayIdentifier(for: Date())
            let first = Insight(type: .dailyNudge, content: #"You wrote, "Synthetic entry 0." That sounds steady."#, periodIdentifier: today, generatedByEngine: .gemma)
            context.insert(first)
            try context.save()
            try await withTier(.free) {
                let viewModel = InsightViewModel()
                await viewModel.loadNudge(entries: all, insights: [first], context: context)
                guard case .loaded(let shown) = viewModel.nudgeState else {
                    Issue.record("free user's first reflection: expected .loaded, got \(viewModel.nudgeState)"); return
                }
                #expect(shown.persistentModelID == first.persistentModelID)

                let older = Insight(type: .dailyNudge, content: #"You wrote, "Synthetic entry 1." That sounds calm."#, periodIdentifier: "2026-10-01", generatedByEngine: .gemma)
                older.generatedAt = Date(timeIntervalSinceNow: -9 * 86_400)
                let oldest = Insight(type: .dailyNudge, content: #"You wrote, "Synthetic entry 2." That sounds calm."#, periodIdentifier: "2026-09-20", generatedByEngine: .gemma)
                oldest.generatedAt = Date(timeIntervalSinceNow: -30 * 86_400)
                context.insert(older)
                context.insert(oldest)
                await viewModel.loadNudge(entries: all, insights: [older, first, oldest], context: context)
                guard case .loaded(let latest) = viewModel.nudgeState else {
                    Issue.record("Free with several reflections: expected .loaded, got \(viewModel.nudgeState)"); return
                }
                #expect(latest.persistentModelID == first.persistentModelID)
            }
        }

        /// A fallback today doesn't give Free a Try Again: no new reflection is coming.
        @Test func freeWithAFallbackTodaySeesTheLockNotTryAgain() async throws {
            let context = try makeContext()
            let all = entries(3, in: context)
            let real = Insight(type: .dailyNudge, content: #"You wrote, "Synthetic entry 1." That sounds calm."#, periodIdentifier: "2026-10-01", generatedByEngine: .gemma)
            real.generatedAt = Date(timeIntervalSinceNow: -9 * 86_400)
            let fallback = Insight(type: .dailyNudge, content: InsightService.dailyNudgeUngroundedFallback,
                                   periodIdentifier: DateHelpers.dayIdentifier(for: Date()), generatedByEngine: .gemma)
            context.insert(real)
            context.insert(fallback)
            try await withTier(.free) {
                let viewModel = InsightViewModel()
                await viewModel.loadNudge(entries: all, insights: [real, fallback], context: context)
                guard case .subscriptionRequired = viewModel.nudgeState else {
                    Issue.record("expected .subscriptionRequired, got \(viewModel.nudgeState)"); return
                }
            }
        }

        @Test func freeFirstReflectionFromLastWeekIsNotKeptOnTheCard() async throws {
            let context = try makeContext()
            let all = entries(3, in: context)
            let old = Insight(type: .dailyNudge, content: #"You wrote, "Synthetic entry 2." That sounds calm."#, periodIdentifier: "2026-10-01", generatedByEngine: .gemma)
            old.generatedAt = Date(timeIntervalSinceNow: -9 * 86_400)
            context.insert(old)
            try await withTier(.free) {
                let viewModel = InsightViewModel()
                await viewModel.loadNudge(entries: all, insights: [old], context: context)
                guard case .subscriptionRequired = viewModel.nudgeState else {
                    Issue.record("expected .subscriptionRequired, got \(viewModel.nudgeState)"); return
                }
            }
        }

        @Test func digestNeedsCoreAndReportNeedsDeep() async throws {
            let context = try makeContext()
            let lastWeek = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
            let all = entries(12, in: context, now: lastWeek)
            try await withTier(.free) {
                let viewModel = InsightViewModel()
                await viewModel.loadWeeklyDigest(entries: all, insights: [], context: context)
                guard case .subscriptionRequired = viewModel.digestState else {
                    Issue.record("digest on Free: got \(viewModel.digestState)"); return
                }
            }
            try await withTier(.core) {
                let viewModel = InsightViewModel()
                await DateHelpers.$nowForTesting.withValue(lastWeek) {
                    await viewModel.loadMonthlyReport(entries: all, insights: [], context: context)
                }
                guard case .subscriptionRequired = viewModel.monthlyReportState else {
                    Issue.record("report on Core: got \(viewModel.monthlyReportState)"); return
                }
            }
        }

        /// A digest already made this week stays readable on Free; without one Free sees the lock,
        /// never "N more entries" (no digest is coming).
        @Test func freeReadsASavedDigestElseTheLock() async throws {
            let context = try makeContext()
            let sunday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
            let few = entries(1, in: context, now: sunday)
            let week = DateHelpers.digestWeekIdentifier(for: sunday)
            let saved = Insight(type: .weeklyDigest, content: #"You wrote, "Synthetic entry 0." A steady week."#, periodIdentifier: week, generatedByEngine: .gemma)
            context.insert(saved)
            try await withTier(.free) {
                let viewModel = InsightViewModel()
                await DateHelpers.$nowForTesting.withValue(sunday) {
                    await viewModel.loadWeeklyDigest(entries: few, insights: [saved], context: context)
                }
                guard case .loaded(let shown) = viewModel.digestState else {
                    Issue.record("saved digest on Free: got \(viewModel.digestState)"); return
                }
                #expect(shown.persistentModelID == saved.persistentModelID)

                await DateHelpers.$nowForTesting.withValue(sunday) {
                    await viewModel.loadWeeklyDigest(entries: few, insights: [], context: context)
                }
                guard case .subscriptionRequired = viewModel.digestState else {
                    Issue.record("no digest on Free: got \(viewModel.digestState)"); return
                }
            }
        }

        /// This month's report already made stays readable without Deep, even mid-month; without
        /// one it's the lock, not "waiting for month end".
        @Test func coreReadsASavedReportElseTheLock() async throws {
            let context = try makeContext()
            let midMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
            let all = entries(3, in: context, now: midMonth)
            let saved = Insight(type: .monthlyReport, content: #"You wrote, "Synthetic entry 0." A full month."#,
                                periodIdentifier: DateHelpers.monthIdentifier(for: midMonth), generatedByEngine: .gemma)
            context.insert(saved)
            for tier in [SubscriptionTier.free, .core] {
                try await withTier(tier) {
                    let viewModel = InsightViewModel()
                    await DateHelpers.$nowForTesting.withValue(midMonth) {
                        await viewModel.loadMonthlyReport(entries: all, insights: [saved], context: context)
                    }
                    guard case .loaded = viewModel.monthlyReportState else {
                        Issue.record("saved report on \(tier): got \(viewModel.monthlyReportState)"); return
                    }
                    await DateHelpers.$nowForTesting.withValue(midMonth) {
                        await viewModel.loadMonthlyReport(entries: all, insights: [], context: context)
                    }
                    guard case .subscriptionRequired = viewModel.monthlyReportState else {
                        Issue.record("no report on \(tier): got \(viewModel.monthlyReportState)"); return
                    }
                }
            }
        }
    }
}
