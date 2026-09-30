import Testing
import SwiftData
import Foundation
@testable import mirror

// One more daily reflection on the day of writing (owner-approved 2026-09-28): a reflection made
// from yesterday's writing no longer blocks today's writing from being reflected until tomorrow,
// or from being skipped when tomorrow's writing comes first. Plus the Today card label, the
// next-morning card, and Past reflections grouping that go with it. Integration cases run the
// real mirrorApp.runDailyNudgeIfNeeded against an in-memory store with the generation intercept,
// so no model runs; they need a model to be "available" to get past that gate.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct DailyReflectionTimingTests {

        private let startOfToday = Calendar.current.startOfDay(for: Date())

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: Entry.self, Insight.self, configurations: config)
            return ModelContext(container)
        }

        @discardableResult
        private func addEntry(_ text: String, at date: Date, to context: ModelContext) -> Entry {
            let e = Entry(text: text, mood: "Content")
            e.createdAt = date
            context.insert(e)
            return e
        }

        @discardableResult
        private func addReflection(_ content: String, at date: Date, to context: ModelContext) -> Insight {
            let i = Insight(type: .dailyNudge, content: content, periodIdentifier: DateHelpers.dayIdentifier(for: date), generatedByEngine: .gemma)
            i.generatedAt = date
            context.insert(i)
            return i
        }

        private func todaysReflections(_ context: ModelContext) throws -> [Insight] {
            let today = DateHelpers.dayIdentifier(for: Date())
            return try context.fetch(FetchDescriptor<Insight>()).filter { $0.type == .dailyNudge && $0.periodIdentifier == today }
        }

        /// Three readable entries yesterday, and a real reflection made just after midnight from them.
        private func seedYesterdayAndMorningReflection(_ context: ModelContext) throws {
            addEntry("Long walk around the lake with Bruno after work, the light was gold on the water.", at: startOfToday.addingTimeInterval(-6 * 3_600), to: context)
            addEntry("Finally fixed the dashboard bug with Omar, it was in the date parsing all along.", at: startOfToday.addingTimeInterval(-5 * 3_600), to: context)
            addEntry("Called Anu tonight, first time in weeks, and we talked for almost an hour.", at: startOfToday.addingTimeInterval(-4 * 3_600), to: context)
            addReflection(#"You wrote, "Called Anu tonight, first time in weeks, and we talked for almost an hour." That sounds like a warm evening."#, at: startOfToday.addingTimeInterval(1), to: context)
            try context.save()
        }

        /// A grounded Gemma reply built from the plan's own grammar: its first quote option.
        private static func groundedReply(for plan: LocalLLMService.GemmaPlan) -> String {
            guard case .grammarConstrained(_, let grammar) = plan,
                  let start = grammar.range(of: "quote ::= \"")?.upperBound else { return "not grounded" }
            var quote = ""
            var escaped = false
            for c in grammar[start...] {
                if escaped { quote.append(c); escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { break } else { quote.append(c) }
            }
            return "You wrote, \"\(quote)\" That sounds like a lot to hold today."
        }

        private func clearMarker() { UserDefaults.standard.removeObject(forKey: mirrorApp.extraReflectionFailedAttemptKey) }

        // MARK: Gate (pure)

        @Test func gate_allowsOneMoreOnlyForNewWritingTodayNotYetReflected() {
            let r = startOfToday.addingTimeInterval(8 * 3_600)
            let allow = InsightService.allowsAnotherReflectionToday
            #expect(!allow(r, [], nil), "nothing written today")
            #expect(!allow(r, [r.addingTimeInterval(-60)], nil), "today's writing was already reflected")
            #expect(allow(r, [r.addingTimeInterval(60)], nil), "today's reflection was about earlier days; wrote since")
            #expect(!allow(r, [r.addingTimeInterval(-60), r.addingTimeInterval(60)], nil), "already covered today, so no third")
            #expect(!allow(r, [r.addingTimeInterval(60)], r.addingTimeInterval(120)), "an extra attempt failed after that writing")
            #expect(allow(r, [r.addingTimeInterval(60), r.addingTimeInterval(180)], r.addingTimeInterval(120)), "new writing after the failed attempt")
        }

        // MARK: Which day a reflection is about

        @Test func reflectedDay_isTheNewestEntryAtOrBeforeTheReflection() {
            let yesterdayEvening = Entry(text: "Repotted the basil and the mint on the windowsill, then called it a night.", mood: "Content")
            yesterdayEvening.createdAt = startOfToday.addingTimeInterval(-3_600)
            let laterToday = Entry(text: "Wrote this after the reflection was made, about the rest of the day.", mood: "Content")
            laterToday.createdAt = startOfToday.addingTimeInterval(20 * 3_600)
            let reflection = Insight(type: .dailyNudge, content: "x", periodIdentifier: "p")
            reflection.generatedAt = startOfToday.addingTimeInterval(18 * 3_600)
            let day = InsightService.reflectedDay(of: reflection, entriesNewestFirst: [laterToday, yesterdayEvening])
            #expect(day == Calendar.current.startOfDay(for: yesterdayEvening.createdAt))
        }

        // MARK: Past reflections grouping

        @Test func pastList_keepsBothReflectionsOfADay_butCollapsesSameDayDuplicates() throws {
            let context = try makeContext()
            let yesterday = addEntry("Repotted the basil and the mint on the windowsill, then called it a night.", at: startOfToday.addingTimeInterval(-3_600), to: context)
            let today = addEntry("The whole afternoon went to the new project plan and it finally makes sense.", at: startOfToday.addingTimeInterval(3 * 3_600), to: context)
            let aboutYesterday = addReflection("real one", at: startOfToday.addingTimeInterval(2 * 3_600), to: context)
            let aboutToday = addReflection("real two", at: startOfToday.addingTimeInterval(4 * 3_600), to: context)
            let duplicateAboutToday = addReflection("real two, other device", at: startOfToday.addingTimeInterval(4 * 3_600 + 30), to: context)
            let fallback = addReflection(InsightService.dailyNudgeUngroundedFallback, at: startOfToday.addingTimeInterval(5 * 3_600), to: context)
            try context.save()

            let past = InsightView.pastDailyReflections(
                from: [aboutYesterday, aboutToday, duplicateAboutToday, fallback],
                entriesNewestFirst: [today, yesterday]
            )
            #expect(past.rows.map(\.content) == ["real two, other device", "real one"])
            #expect(past.reflectedDays[aboutYesterday.persistentModelID] == Calendar.current.startOfDay(for: yesterday.createdAt))
        }

        // MARK: Next-morning card

        @Test func nextMorning_keepsYesterdaysReflectionOnTheCard_untilNewWriting() async throws {
            let context = try makeContext()
            for (i, text) in ["Long walk around the lake with Bruno after work, gold light on the water.", "Fixed the dashboard bug with Omar, it was the date parsing all along.", "Called Anu tonight for the first time in weeks and talked for an hour."].enumerated() {
                addEntry(text, at: startOfToday.addingTimeInterval(Double(-4 + i) * 3_600), to: context)
            }
            let lastNight = addReflection("You wrote, \"Called Anu tonight for the first time in weeks and talked for an hour.\" That sounds warm.", at: startOfToday.addingTimeInterval(-30 * 60), to: context)
            try context.save()
            let viewModel = InsightViewModel()

            await viewModel.loadNudge(entries: try context.fetch(FetchDescriptor<Entry>()), insights: try context.fetch(FetchDescriptor<Insight>()), context: context)
            switch viewModel.nudgeState {
            case .loaded(let shown): #expect(shown.persistentModelID == lastNight.persistentModelID)
            case .subscriptionRequired: break   // depends on the test host's tier
            default: Issue.record("expected last night's reflection on the card, got \(viewModel.nudgeState)")
            }

            addEntry("Morning pages before work, still thinking about the call with Anu.", at: startOfToday.addingTimeInterval(60), to: context)
            try context.save()
            await viewModel.loadNudge(entries: try context.fetch(FetchDescriptor<Entry>()), insights: try context.fetch(FetchDescriptor<Insight>()), context: context)
            if case .loaded = viewModel.nudgeState { Issue.record("new writing since: expected the pending card, got .loaded") }
        }

        @Test func nextMorning_doesNotResurfaceAnOlderReflection() async throws {
            let context = try makeContext()
            for (i, text) in ["Long walk around the lake with Bruno after work, gold light on the water.", "Fixed the dashboard bug with Omar, it was the date parsing all along.", "Called Anu tonight for the first time in weeks and talked for an hour."].enumerated() {
                addEntry(text, at: startOfToday.addingTimeInterval(Double(-72 + i) * 3_600), to: context)
            }
            addReflection("You wrote, \"Called Anu tonight for the first time in weeks and talked for an hour.\" That sounds warm.", at: startOfToday.addingTimeInterval(-60 * 3_600), to: context)
            try context.save()
            let viewModel = InsightViewModel()
            await viewModel.loadNudge(entries: try context.fetch(FetchDescriptor<Entry>()), insights: try context.fetch(FetchDescriptor<Insight>()), context: context)
            if case .loaded = viewModel.nudgeState { Issue.record("a two-day-old reflection must not come back on the Today card") }
        }

        @Test func nextMorning_afterASkippedDay_stillShowsTheWriteTodayCard() async throws {
            // Wrote two days ago; the reflection about that was made yesterday; nothing written
            // yesterday or today. The card must not keep a reflection about the day before.
            let context = try makeContext()
            for (i, text) in ["Long walk around the lake with Bruno after work, gold light on the water.", "Fixed the dashboard bug with Omar, it was the date parsing all along.", "Called Anu tonight for the first time in weeks and talked for an hour."].enumerated() {
                addEntry(text, at: startOfToday.addingTimeInterval(Double(-30 + i) * 3_600), to: context)
            }
            addReflection("You wrote, \"Called Anu tonight for the first time in weeks and talked for an hour.\" That sounds warm.", at: startOfToday.addingTimeInterval(-16 * 3_600), to: context)
            try context.save()
            let viewModel = InsightViewModel()
            await viewModel.loadNudge(entries: try context.fetch(FetchDescriptor<Entry>()), insights: try context.fetch(FetchDescriptor<Insight>()), context: context)
            if case .loaded = viewModel.nudgeState { Issue.record("a reflection about the day before yesterday must not stay on the Today card") }
        }

        // MARK: Reflection time

        @Test func reflectionTime_comparesMinutesToo() {
            func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: startOfToday)! }
            func due(_ now: Date, _ hour: Int, _ minute: Int) -> Bool {
                mirrorApp.isAtOrPastReflectionTime(now, hour: hour, minute: minute)
            }
            #expect(!due(at(8, 15), 8, 30), "8:15 is before an 8:30 reflection time")
            #expect(due(at(8, 30), 8, 30))
            #expect(due(at(9, 0), 8, 30))
            #expect(!due(at(7, 59), 8, 0))
            #expect(due(at(8, 0), 8, 0), "a whole-hour time behaves as before")
            #expect(!due(at(0, 0), 23, 59))
        }

        // MARK: Background catch-up condition ("save and leave")

        @Test func catchUp_isDue_forTheSameDaySecondReflection() throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            #expect(mirrorApp.dailyReflectionMayBeDue(context: context), "no reflection yet today")

            try seedYesterdayAndMorningReflection(context)
            #expect(!mirrorApp.dailyReflectionMayBeDue(context: context), "today's reflection, nothing written today")

            addEntry("The whole afternoon went to the new project plan and it finally makes sense now.", at: startOfToday.addingTimeInterval(2), to: context)
            try context.save()
            #expect(mirrorApp.dailyReflectionMayBeDue(context: context), "wrote today after a reflection about yesterday")

            addReflection(#"You wrote, "The whole afternoon went to the new project plan and it finally makes sense now." That sounds good."#, at: startOfToday.addingTimeInterval(3), to: context)
            try context.save()
            #expect(!mirrorApp.dailyReflectionMayBeDue(context: context), "today's writing is reflected")

            addReflection(InsightService.dailyNudgeUngroundedFallback, at: startOfToday.addingTimeInterval(4), to: context)
            try context.save()
            #expect(mirrorApp.dailyReflectionMayBeDue(context: context), "newest is the fallback: retry, as before")
        }

        // MARK: Through runDailyNudgeIfNeeded

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func secondReflection_isMade_whenTodaysWasAboutEarlierDays_andUserWroteSince() async throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            try seedYesterdayAndMorningReflection(context)
            addEntry("The whole afternoon went to the new project plan and it finally makes sense now.", at: startOfToday.addingTimeInterval(2), to: context)
            try context.save()
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, plan in
                calls += 1
                return (Self.groundedReply(for: plan), .gemma)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            let rows = try todaysReflections(context)
            #expect(calls >= 1)
            #expect(rows.count == 2)
            #expect(rows.allSatisfy { !InsightService.isUngroundedFallback($0.content) })
            #expect(rows.max { $0.generatedAt < $1.generatedAt }?.content.contains("new project plan") == true)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func failedSecondReflection_isNotSaved_andWaitsForNewWriting() async throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            try seedYesterdayAndMorningReflection(context)
            addEntry("The whole afternoon went to the new project plan and it finally makes sense now.", at: startOfToday.addingTimeInterval(2), to: context)
            try context.save()
            var calls = 0
            var grounded = false
            // The fallback card comes from the free-prose path: a reply the word-overlap guards
            // reject on every attempt (same trick as test_dumpNudgePromptsForRig).
            LocalLLMService.generateInterceptForTesting = { _, _, _, plan in
                calls += 1
                return grounded ? (Self.groundedReply(for: plan), .gemma) : ("The rain outside feels heavy tonight, doesn't it?", .foundationModels)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls >= 1)
            #expect(try todaysReflections(context).count == 1, "the fallback must not replace the real reflection")
            #expect(UserDefaults.standard.object(forKey: mirrorApp.extraReflectionFailedAttemptKey) != nil)

            let callsAfterFailure = calls
            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls == callsAfterFailure, "no retry until the user writes again")

            addEntry("Evening now, and the plan still holds up after a second look at it.", at: Date().addingTimeInterval(1), to: context)
            try context.save()
            grounded = true
            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls > callsAfterFailure)
            #expect(try todaysReflections(context).count == 2)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func throwingSecondAttempt_isNotRecorded_andRetriesOnTheNextTrigger() async throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            try seedYesterdayAndMorningReflection(context)
            addEntry("The whole afternoon went to the new project plan and it finally makes sense now.", at: startOfToday.addingTimeInterval(2), to: context)
            try context.save()
            var calls = 0
            // Not one of the offered quotes, so the grammar validator rejects every attempt and
            // generateNudge throws (a cut-off or failed generation, not the fallback card).
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("You wrote, \"nothing like this\" That sounds odd.", .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls >= 1)
            #expect(try todaysReflections(context).count == 1)
            #expect(UserDefaults.standard.object(forKey: mirrorApp.extraReflectionFailedAttemptKey) == nil)
            let callsAfterFirst = calls
            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls > callsAfterFirst, "a throw retries on the next trigger")
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func noSecondReflection_whenTodaysAlreadyCoveredTodaysWriting() async throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            for (i, text) in ["Long walk around the lake with Bruno after work, gold light on the water.", "Fixed the dashboard bug with Omar, it was the date parsing all along."].enumerated() {
                addEntry(text, at: startOfToday.addingTimeInterval(Double(-4 + i) * 3_600), to: context)
            }
            addEntry("Early start today, coffee on the balcony before anyone else was up.", at: startOfToday.addingTimeInterval(1), to: context)
            addReflection(#"You wrote, "Early start today, coffee on the balcony before anyone else was up." That sounds calm."#, at: startOfToday.addingTimeInterval(2), to: context)
            addEntry("Afternoon was meetings back to back and I am tired now.", at: startOfToday.addingTimeInterval(3), to: context)
            try context.save()
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, plan in calls += 1; return (Self.groundedReply(for: plan), .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls == 0)
            #expect(try todaysReflections(context).count == 1)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func noThirdReflection_afterTheSecond() async throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            try seedYesterdayAndMorningReflection(context)
            addEntry("The whole afternoon went to the new project plan and it finally makes sense now.", at: startOfToday.addingTimeInterval(2), to: context)
            addReflection(#"You wrote, "The whole afternoon went to the new project plan and it finally makes sense now." That sounds good."#, at: startOfToday.addingTimeInterval(3), to: context)
            addEntry("Evening now, and the plan still holds up after a second look at it.", at: startOfToday.addingTimeInterval(4), to: context)
            try context.save()
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, plan in calls += 1; return (Self.groundedReply(for: plan), .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls == 0)
            #expect(try todaysReflections(context).count == 2)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func noSecondReflection_withoutWritingToday() async throws {
            clearMarker(); defer { clearMarker() }
            let context = try makeContext()
            try seedYesterdayAndMorningReflection(context)
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, plan in calls += 1; return (Self.groundedReply(for: plan), .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(calls == 0)
            #expect(try todaysReflections(context).count == 1)
        }
    }
}
