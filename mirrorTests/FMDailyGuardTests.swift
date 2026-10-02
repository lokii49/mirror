import Testing
import Foundation
@testable import mirror

// The guard that sits between Foundation Models' structured daily reflection and the screen.
// Cases are the failures the llmrig measured (tools/llmrig/fm/RUBRIC_FM.md, rounds 4-6), written
// with synthetic text.
@Suite("FM daily reflection guard")
struct FMDailyGuardTests {
    private let walk = FMDailyGuard.Source(
        text: "Walked by the lake with Bruno after work, he chased the ducks again. Sun was out for once. Felt light for the first time this week.",
        mood: "Peaceful"
    )
    private let missing = FMDailyGuard.Source(
        text: "Rohan left for Bangalore this morning for the new job. The flat feels too quiet without him. Missing him a lot tonight.",
        mood: "Sad"
    )

    private func verify(_ quote: String, _ insight: String, _ source: FMDailyGuard.Source) -> FMDailyGuard.Verified? {
        FMDailyGuard.verify(quote: quote, insight: insight, sources: [source])
    }

    // MARK: Quote

    @Test func quoteIsShownInTheEntrysOwnWords() throws {
        let v = try #require(verify("walked by the lake with bruno after work, he chased the ducks again.", "You feel light.", walk))
        #expect(v.quote == "Walked by the lake with Bruno after work, he chased the ducks again.")
    }

    @Test func curlyQuotesAndLineBreaksStillMatch() throws {
        let source = FMDailyGuard.Source(text: "I didn\u{2019}t sleep well.\nThe call went long and I was tired.", mood: "Drained")
        let v = try #require(verify("I didn't sleep well. The call went long and I was tired.", "You feel tired.", source))
        #expect(v.quote == "I didn\u{2019}t sleep well. The call went long and I was tired.")
    }

    @Test func aQuoteNotInTodaysEntriesIsRejected() {
        #expect(verify("The rain outside kept me inside all afternoon.", "You feel calm.", walk) == nil)
    }

    @Test func aTooShortQuoteIsRejected() {
        #expect(verify("Felt light.", "You feel light.", walk) == nil)
    }

    @Test func aLongQuoteIsCutAtASentenceEndWithinTwentyFiveWords() throws {
        let text = "Client presentation got pushed to Thursday again. Spent the whole afternoon fixing the dashboard bug with Omar, finally found it in the date parsing. Skipped dinner and ate chips at my desk."
        let source = FMDailyGuard.Source(text: text, mood: "Overwhelmed")
        let v = try #require(verify(text, "You feel overwhelmed.", source))
        #expect(v.quote == "Client presentation got pushed to Thursday again. Spent the whole afternoon fixing the dashboard bug with Omar, finally found it in the date parsing.")
        #expect(v.quote.split(separator: " ").count <= FMDailyGuard.maxQuoteWords)
    }

    @Test func aLongSingleSentenceIsCutAtAWord() throws {
        let text = "so today was kind of a mess honestly I woke up late again and missed the bus and then the whole morning just went sideways because the manager moved the standup"
        let source = FMDailyGuard.Source(text: text, mood: "Frustrated")
        let v = try #require(verify(text, "You feel frustrated.", source))
        #expect(text.hasPrefix(v.quote))
        #expect(v.quote.split(separator: " ").count <= FMDailyGuard.maxQuoteWords)
    }

    // MARK: Insight

    @Test func aFeelingTheEntryNeverStatedIsDropped() throws {
        let v = try #require(verify("Felt light for the first time this week.", "You feel light. You feel a mix of relief and worry.", walk))
        #expect(v.insight == "You feel light.")
        #expect(v.droppedSentences == 1)
    }

    @Test func aMoodLabelAndItsSynonymsAreSupported() {
        #expect(verify("Felt light for the first time this week.", "You feel calm.", walk) != nil)
        #expect(verify("Felt light for the first time this week.", "You feel uneasy.", walk) == nil)
    }

    @Test func overclaimingWordsNeedTheEntry() throws {
        let v = try #require(verify("Felt light for the first time this week.", "You feel a lightness you haven't felt before. You walked by the lake.", walk))
        #expect(v.insight == "You walked by the lake.")
        // "again" is in the entry, so it may be used.
        #expect(verify("Felt light for the first time this week.", "Bruno chased the ducks again.", walk) != nil)
    }

    @Test func aFeelingFollowedByAVerbFormIsDropped() throws {
        let v = try #require(verify("Missing him a lot tonight.", "You feel sad. You feel missing him a lot.", missing))
        #expect(v.insight == "You feel sad.")
        #expect(verify("Missing him a lot tonight.", "You feel sad and missing him.", missing) == nil)
        #expect(verify("Missing him a lot tonight.", "You feel something heavy.", missing) != nil)
    }

    @Test func quoteMarksAndFirstPersonAreDropped() {
        #expect(verify("Felt light for the first time this week.", "You said \"light\" and meant it.", walk) == nil)
        #expect(verify("Felt light for the first time this week.", "I feel light today.", walk) == nil)
    }

    @Test func sceneryAndInventedNamesAreDropped() {
        #expect(verify("Felt light for the first time this week.", "You watched the sky change.", walk) == nil)
        #expect(verify("Felt light for the first time this week.", "You walked by the lake with Tara.", walk) == nil)
        #expect(verify("Felt light for the first time this week.", "You walked by the lake with Bruno.", walk) != nil)
    }

    @Test func stateWordsNeedSupportToo() {
        let plain = FMDailyGuard.Source(text: "Did laundry in the morning and made rice and dal for lunch. Replied to a few emails.", mood: "Content")
        #expect(FMDailyGuard.verify(quote: "Did laundry in the morning and made rice and dal for lunch.", insight: "You are quiet and focused.", sources: [plain]) == nil)
        #expect(FMDailyGuard.verify(quote: "Did laundry in the morning and made rice and dal for lunch.", insight: "It was an ordinary, steady day.", sources: [plain]) != nil)
    }

    @Test func insightKeepsAtMostTwoSentencesAndIsCapitalised() throws {
        let v = try #require(verify("Felt light for the first time this week.", "you feel light. you feel calm. you walked by the lake", walk))
        #expect(v.insight == "You feel light. You feel calm.")
    }

    @Test func aMoodFromAnotherEntryTodayCountsAsSupport() {
        let run = FMDailyGuard.Source(text: "Ran 5k before work, legs felt heavy but I finished.", mood: "Energized")
        let argue = FMDailyGuard.Source(text: "Evening was rough, argued with my brother over the phone. Still annoyed.", mood: "Frustrated")
        let v = FMDailyGuard.verify(quote: "Evening was rough, argued with my brother over the phone.", insight: "You feel annoyed. You feel energized.", sources: [run, argue])
        #expect(v?.sourceIndex == 1)
        #expect(v?.insight == "You feel annoyed. You feel energized.")
    }
}

// How the app assembles a verified reflection and what it does when attempts fail.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct StructuredNudgeTests {
        private let sad = Entry(text: "Rohan left for Bangalore this morning for the new job. The flat feels too quiet without him. Missing him a lot tonight.", mood: "Sad")

        @Test func assemblesTheShapeEveryGroundedReaderExpects() throws {
            let text = try #require(InsightService.assembleStructuredNudge(
                quote: "missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: []
            ))
            #expect(text.hasPrefix("You wrote, \"Missing him a lot tonight.\" You feel sad."))
            #expect(InsightService.isGrammarGrounded(text))
            let parts = try #require(InsightService.groundedNudgeParts(of: text))
            #expect(parts.quote == "Missing him a lot tonight.")
            // Sad day: the app's own fixed tip follows the model's sentence.
            let tip = try #require(InsightService.groundedNudgeTip(forMood: "Sad"))
            #expect(text.hasSuffix(tip))
            #expect(InsightService.nudgeTextForOutsideApp(text) == "You feel sad. " + tip)
        }

        @Test func noTipOnAGoodDay() throws {
            let happy = Entry(text: "Got the offer letter from the design studio today!", mood: "Joyful")
            let text = try #require(InsightService.assembleStructuredNudge(
                quote: "Got the offer letter from the design studio today!", insight: "You feel joyful.", source: [happy], recentNudges: []
            ))
            #expect(text.hasSuffix("You feel joyful."))
        }

        @Test func openerRotatesAfterTheLastReflection() throws {
            let first = try #require(InsightService.assembleStructuredNudge(
                quote: "Missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: []
            ))
            let second = try #require(InsightService.assembleStructuredNudge(
                quote: "Missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: [first], allowRepeat: true
            ))
            #expect(second.hasPrefix(InsightService.groundedNudgeOpeners[1]))
        }

        @Test func aRepeatedQuoteIsOnlyAcceptedWhenAllowed() throws {
            let first = try #require(InsightService.assembleStructuredNudge(
                quote: "Missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: []
            ))
            #expect(InsightService.assembleStructuredNudge(quote: "Missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: [first]) == nil)
            #expect(InsightService.assembleStructuredNudge(quote: "Missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: [first], allowRepeat: true) != nil)
        }

        @Test func retriesUntilADraftSurvives() async {
            var calls = 0
            let text = await InsightService.structuredFMNudge(source: [sad], recentNudges: [], userMessage: "") {
                calls += 1
                // 1: invented quote; 2: guardrail refusal; 3: good.
                if calls == 1 { return ("The rain kept me inside all evening long.", "You feel sad.") }
                if calls == 2 { throw LocalLLMError.emptyResponse }
                return ("Missing him a lot tonight.", "You feel sad.")
            }
            #expect(calls == 3)
            #expect(text?.hasPrefix("You wrote, \"Missing him a lot tonight.\"") == true)
        }

        @Test func nilWhenEveryAttemptFails() async {
            var calls = 0
            let text = await InsightService.structuredFMNudge(source: [sad], recentNudges: [], userMessage: "") {
                calls += 1
                return ("Missing him a lot tonight.", "You feel something like relief.")
            }
            #expect(text == nil)
            #expect(calls == InsightService.structuredNudgeAttempts)
        }
    }
}

// Real Foundation Models, end to end through generateNudge. Skipped unless HARNESS_REAL_FM is set
// (TEST_RUNNER_HARNESS_REAL_FM=1 on the xcodebuild command line) and the device has Apple Intelligence.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct RealFMNudgeTests {
        @Test func realFoundationModelsNudgeIsGroundedAndAssembled() async throws {
            guard ProcessInfo.processInfo.environment["HARNESS_REAL_FM"] != nil, LocalLLMService.prefersFoundationModels else { return }
            let sick = Entry(text: "Barely slept, got back from a late concert around 2 and my stomach was bad all night. Woke at 10, way later than usual, drank ORS. Had soup in the evening and sat with Karan on the balcony for a short chat.", mood: "Drained")
            var results: [String] = []
            for _ in 0..<5 {
                let (text, engine, degraded) = try await InsightService.generateNudge(entries: [sick], recentNudges: [])
                #expect(engine == .foundationModels)
                #expect(!degraded)
                #expect(InsightService.isGrammarGrounded(text))
                let parts = try #require(InsightService.groundedNudgeParts(of: text))
                #expect(sick.text.contains(parts.quote))
                #expect(!parts.rest.isEmpty)
                results.append(text)
            }
            print("[realfm] " + results.joined(separator: "\n[realfm] "))
        }
    }
}
