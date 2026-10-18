import Testing
import SwiftData
import Foundation
@testable import mirror

// Backlog A7: a digest/report regeneration that came back as the fallback replaced a real one
// (newest wins). A8: the monthly loader regenerated every 24h from unchanged writing. "Now" is
// pinned with DateHelpers.nowForTesting, since both paths are date-gated. Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct PeriodRegenerationTests {
        private static var cal: Calendar { Calendar.current }
        private static func day(_ m: Int, _ d: Int, _ h: Int = 12) -> Date {
            cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
        }

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: Entry.self, Insight.self, configurations: config)
            return ModelContext(container)
        }

        private func add(_ text: String, at date: Date, to context: ModelContext) {
            let e = Entry(text: text, mood: "Content")
            e.createdAt = date
            context.insert(e)
        }

        private static let realDigest = "THIS WEEK'S THEME: A synthetic week of walks and deadlines."
        private static let realReport = "THIS MONTH: A synthetic month of steady work and evening walks."
        /// Well-formed, but nothing in it comes from the entries.
        private static let invented = """
            THIS WEEK'S THEME: Quiet mornings repotting succulents on a sunny windowsill.
            YOUR ENERGY: Gardening restored patience after long calls with cousins.
            WHAT'S BUILDING: Sketching birds every Saturday at the harbour.
            WATCH OUT FOR: Skipping breakfast before choir rehearsals.
            MOOD BOOST: Bake that lemon bread recipe from grandma.
            NEXT WEEK: Plan a picnic near the old lighthouse.
            """

        private static let inventedMonthly = """
            YOUR MONTH IN ONE IMAGE: A lighthouse keeper polishing brass at dawn.
            THE TENSION AT THE CENTER: Choir rehearsals against harbour sketching.
            A MOMENT THAT SHIFTED SOMETHING: Repotting succulents on a sunny windowsill.
            WHAT YOU'RE BECOMING: Someone who bakes lemon bread for cousins.
            WHAT WANTS TO BE RELEASED: Skipping breakfast before rehearsals.
            YOUR QUESTION FOR NEXT MONTH: Which picnic spot near the lighthouse?
            """

        private func clear(_ type: InsightType, _ period: String) {
            UserDefaults.standard.removeObject(forKey: InsightService.periodFallbackAttemptKey(type, period: period))
        }

        // Sunday 2026-10-11 is the last day of ISO week 2026-W41.
        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func digestFallbackNeverReplacesARealDigest() async throws {
            let now = Self.day(10, 11)
            let week = DateHelpers.digestWeekIdentifier(for: now)
            clear(.weeklyDigest, week); defer { clear(.weeklyDigest, week) }
            let context = try makeContext()
            add("Long walk around the lake after work, the light was gold on the water.", at: Self.day(10, 6), to: context)
            add("Finally fixed the dashboard bug, it was in the date parsing all along.", at: Self.day(10, 7), to: context)
            add("Called an old friend tonight and we talked for almost an hour.", at: Self.day(10, 8), to: context)
            let real = Insight(type: .weeklyDigest, content: Self.realDigest, periodIdentifier: week, generatedByEngine: .gemma)
            real.generatedAt = Self.day(10, 9)
            context.insert(real)
            add("Saturday market with the neighbours, bought far too many apples.", at: Self.day(10, 10), to: context)
            try context.save()
            var calls = 0
            let invented = Self.invented
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return (invented, .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await DateHelpers.$nowForTesting.withValue(now) {
                await mirrorApp.runWeeklyDigestIfNeeded(context: context)
            }
            let digests = try context.fetch(FetchDescriptor<Insight>()).filter { $0.type == .weeklyDigest }
            #expect(calls > 0, "the stale digest was regenerated")
            #expect(digests.count == 1, "the fallback wasn't saved over the real digest")
            #expect(digests.first?.content == Self.realDigest)

            let callsAfter = calls
            await DateHelpers.$nowForTesting.withValue(now.addingTimeInterval(3_600)) {
                await mirrorApp.runWeeklyDigestIfNeeded(context: context)
            }
            #expect(calls == callsAfter, "unchanged week: no retry on the next trigger")
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func weeklyLoaderKeepsTheRealDigestWhenARetryFails() async throws {
            let now = Self.day(10, 11)
            let week = DateHelpers.digestWeekIdentifier(for: now)
            clear(.weeklyDigest, week); defer { clear(.weeklyDigest, week) }
            let context = try makeContext()
            add("Long walk around the lake after work, the light was gold on the water.", at: Self.day(10, 6), to: context)
            add("Finally fixed the dashboard bug, it was in the date parsing all along.", at: Self.day(10, 7), to: context)
            add("Called an old friend tonight and we talked for almost an hour.", at: Self.day(10, 8), to: context)
            let real = Insight(type: .weeklyDigest, content: Self.realDigest, periodIdentifier: week, generatedByEngine: .gemma)
            real.generatedAt = Self.day(10, 9)
            context.insert(real)
            add("Saturday market with the neighbours, bought far too many apples.", at: Self.day(10, 10), to: context)
            try context.save()
            var calls = 0
            let invented = Self.invented
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return (invented, .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let viewModel = InsightViewModel()
            let entries = try context.fetch(FetchDescriptor<Entry>())
            let insights = try context.fetch(FetchDescriptor<Insight>())
            await DateHelpers.$nowForTesting.withValue(now) {
                await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: context)
            }
            #expect(calls > 0)
            #expect(try context.fetch(FetchDescriptor<Insight>()).filter { $0.type == .weeklyDigest }.count == 1)
            if case .loaded(let shown) = viewModel.digestState {
                #expect(shown.content == Self.realDigest)
            } else {
                Issue.record("expected the real digest, got \(viewModel.digestState)")
            }
        }

        @Test func keptAttemptMarkersFromEarlierPeriodsAreRemoved() {
            let old = InsightService.periodFallbackAttemptKey(.weeklyDigest, period: "2026-W40")
            let current = InsightService.periodFallbackAttemptKey(.weeklyDigest, period: "2026-W41")
            let otherType = InsightService.periodFallbackAttemptKey(.monthlyReport, period: "2026-09")
            UserDefaults.standard.set(Date(), forKey: old)
            UserDefaults.standard.set(Date(), forKey: otherType)
            defer { [old, current, otherType].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
            InsightService.recordKeptRealRow(.weeklyDigest, period: "2026-W41")
            #expect(UserDefaults.standard.object(forKey: old) == nil)
            #expect(UserDefaults.standard.object(forKey: current) != nil)
            #expect(UserDefaults.standard.object(forKey: otherType) != nil, "other types keep theirs")
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func monthlyLoaderServesTheReportWhenNothingNewWasWritten() async throws {
            let now = Self.day(10, 28)
            let month = DateHelpers.monthIdentifier(for: now)
            clear(.monthlyReport, month); defer { clear(.monthlyReport, month) }
            let context = try makeContext()
            for d in 1...12 { add("Synthetic day \(d): a walk, some work, an early night with a book.", at: Self.day(10, d * 2), to: context) }
            let real = Insight(type: .monthlyReport, content: Self.realReport, periodIdentifier: month, generatedByEngine: .gemma)
            real.generatedAt = Self.day(10, 27, 10)  // 26h before now, after every entry
            context.insert(real)
            try context.save()
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("anything", .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let entries = try context.fetch(FetchDescriptor<Entry>())
            let insights = try context.fetch(FetchDescriptor<Insight>())
            let viewModel = InsightViewModel()
            await DateHelpers.$nowForTesting.withValue(now) {
                await viewModel.loadMonthlyReport(entries: entries, insights: insights, context: context)
            }
            #expect(calls == 0, "no new writing since the report: no regeneration")
            if case .loaded(let shown) = viewModel.monthlyReportState {
                #expect(shown.content == Self.realReport)
            } else {
                Issue.record("expected the cached report, got \(viewModel.monthlyReportState)")
            }
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func monthlyLoaderKeepsTheRealReportWhenARetryFails() async throws {
            let now = Self.day(10, 28)
            let month = DateHelpers.monthIdentifier(for: now)
            clear(.monthlyReport, month); defer { clear(.monthlyReport, month) }
            let context = try makeContext()
            for d in 1...12 { add("Synthetic day \(d): a walk, some work, an early night with a book.", at: Self.day(10, d * 2), to: context) }
            let real = Insight(type: .monthlyReport, content: Self.realReport, periodIdentifier: month, generatedByEngine: .gemma)
            real.generatedAt = Self.day(10, 25)
            context.insert(real)
            add("Late addition after the report: a long phone call with my sister.", at: Self.day(10, 27), to: context)
            try context.save()
            var calls = 0
            let invented = Self.inventedMonthly
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return (invented, .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let viewModel = InsightViewModel()
            await DateHelpers.$nowForTesting.withValue(now) {
                await viewModel.loadMonthlyReport(
                    entries: try! context.fetch(FetchDescriptor<Entry>()),
                    insights: try! context.fetch(FetchDescriptor<Insight>()),
                    context: context
                )
            }
            let reports = try context.fetch(FetchDescriptor<Insight>()).filter { $0.type == .monthlyReport }
            #expect(calls > 0)
            #expect(reports.count == 1)
            if case .loaded(let shown) = viewModel.monthlyReportState {
                #expect(shown.content == Self.realReport)
            } else {
                Issue.record("expected the real report, got \(viewModel.monthlyReportState)")
            }
        }
    }
}
