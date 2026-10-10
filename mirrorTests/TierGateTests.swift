import Testing
import SwiftData
import Foundation
@testable import mirror

/// Paid-tier gates (CLAUDE.md tiers), checked with DEBUG `debugSetTier` while every feature is
/// free in the shipping build. Serialized with the other suites that read the shared tier.
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

        @Test func askLimitsPerTier() {
            #expect(SubscriptionService.askMonthlyLimit(for: .free) == 0)
            #expect(SubscriptionService.askMonthlyLimit(for: .core) == 15)
            #expect(SubscriptionService.askMonthlyLimit(for: .deep) == .max)
        }

        @Test func freeSeesTheFirstReflectionThenThePaywall() async throws {
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
                context.insert(older)
                await viewModel.loadNudge(entries: all, insights: [first, older], context: context)
                guard case .subscriptionRequired = viewModel.nudgeState else {
                    Issue.record("second reflection on Free: expected .subscriptionRequired, got \(viewModel.nudgeState)"); return
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
    }
}
