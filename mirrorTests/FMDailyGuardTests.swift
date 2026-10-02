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

// The option matcher the reflections outside English use (script-neutral, measured in characters).
@Suite("FM quote option matcher")
struct FMQuoteOptionMatcherTests {
    private let german = [
        "Heute war ein langer Tag im Büro.",
        "Ich bin am Abend völlig erschöpft nach Hause gekommen.",
    ]

    @Test func sameSentenceIgnoringCaseAndMarksMatches() {
        #expect(FMDailyGuard.matchOption(quote: "heute war ein langer tag im büro", in: german) == german[0])
        #expect(FMDailyGuard.matchOption(quote: "\u{201C}Heute war ein langer Tag im Büro.\u{201D}", in: german) == german[0])
    }

    @Test func aCutLongSentenceStillFindsItsOption() {
        // More than half of the option: the model cut the sentence short.
        #expect(FMDailyGuard.matchOption(quote: "Ich bin am Abend völlig erschöpft", in: german) == german[1])
    }

    @Test func aTinyFragmentIsRejected() {
        #expect(FMDailyGuard.matchOption(quote: "Ich bin am", in: german) == nil)
    }

    @Test func twoSentencesPickTheOptionThatMostOfTheQuoteIs() {
        let both = "Heute war ein langer Tag im Büro. Ich bin am Abend völlig erschöpft nach Hause gekommen."
        #expect(FMDailyGuard.matchOption(quote: both, in: german) != nil)
    }

    @Test func aQuoteThatIsTheWholeEntryBecomesItsFirstSentence() {
        let entry = "Heute hat mein Chef meine Arbeit kritisiert. Ich habe kaum etwas gesagt. Am Abend war ich völlig erschöpft."
        let options = ["Heute hat mein Chef meine Arbeit kritisiert.", "Ich habe kaum etwas gesagt.", "Am Abend war ich völlig erschöpft."]
        #expect(FMDailyGuard.matchOption(quote: entry, in: options) == options[0])
        // Not at the start: the first option the quote holds wins.
        #expect(FMDailyGuard.matchOption(quote: "Ich habe kaum etwas gesagt. Am Abend war ich völlig erschöpft.", in: options) == options[1])
    }

    @Test func aSentenceNotInTheEntryIsRejected() {
        #expect(FMDailyGuard.matchOption(quote: "Der Regen draußen machte mich traurig und still.", in: german) == nil)
    }

    @Test func japaneseAndChineseAreMeasuredInCharacters() {
        let ja = ["今日は仕事が長引いて、とても疲れた。", "夜は早く寝るつもりだ。"]
        #expect(FMDailyGuard.matchOption(quote: "今日は仕事が長引いて、とても疲れた", in: ja) == ja[0])
        let zh = ["今天加班到很晚，我觉得特别累。", "明天想早点睡。"]
        #expect(FMDailyGuard.matchOption(quote: "今天加班到很晚，我觉得特别累。", in: zh) == zh[0])
        #expect(FMDailyGuard.matchOption(quote: "窗外下着雨，让人心情低落。", in: zh) == nil)
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

        @Test func retriesUntilADraftSurvives() async throws {
            var calls = 0
            let text = try await InsightService.structuredFMNudge(source: [sad], recentNudges: [], userMessage: "") {
                calls += 1
                // 1: invented quote; 2: guardrail refusal; 3: good.
                if calls == 1 { return ("The rain kept me inside all evening long.", "You feel sad.") }
                if calls == 2 { throw LocalLLMError.emptyResponse }
                return ("Missing him a lot tonight.", "You feel sad.")
            }
            #expect(calls == 3)
            #expect(text.text?.hasPrefix("You wrote, \"Missing him a lot tonight.\"") == true)
        }

        @Test func nilWhenEveryAttemptFails() async throws {
            var calls = 0
            let text = try await InsightService.structuredFMNudge(source: [sad], recentNudges: [], userMessage: "") {
                calls += 1
                return ("Missing him a lot tonight.", "You feel something like relief.")
            }
            #expect(text.text == nil)
            // The quote was found though, so a fixed mood line can still follow it.
            #expect(text.safeQuote?.quote == "Missing him a lot tonight.")
            #expect(calls == InsightService.structuredNudgeAttempts)
        }

        @Test func fixedLineFollowsAVerifiedQuoteByMood() throws {
            let text = try #require(InsightService.fixedLineNudge(quote: "Missing him a lot tonight.", sourceIndex: 0, source: [sad], recentNudges: []))
            let line = try #require(InsightService.groundedNudgeMoodLines[.sad])
            #expect(text.hasPrefix("You wrote, \"Missing him a lot tonight.\" " + line))
            #expect(InsightService.isGrammarGrounded(text))
            let parts = try #require(InsightService.groundedNudgeParts(of: text))
            // Both the line and the tip are the app's, none of it the model's.
            let authorship = InsightService.groundedRestAuthorship(parts)
            #expect(authorship.modelText == nil)
            #expect(authorship.appText?.hasPrefix(line) == true)
            #expect(InsightService.nudgeTextForOutsideApp(text).hasPrefix(line))
        }

        @Test func noFixedLineWithoutAMood() {
            let unmooded = Entry(text: "Missing him a lot tonight.", mood: nil)
            #expect(InsightService.fixedLineNudge(quote: "Missing him a lot tonight.", sourceIndex: 0, source: [unmooded], recentNudges: []) == nil)
        }

        // A cancelled task (a background task expiring) must not look like a failed reflection.
        @Test func cancellationIsRethrownNotTreatedAsAFailedAttempt() async {
            await #expect(throws: CancellationError.self) {
                _ = try await InsightService.structuredFMNudge(source: [self.sad], recentNudges: [], userMessage: "") {
                    throw CancellationError()
                }
            }
        }

        // Gemma quotes are one quotable sentence; a Foundation Models quote can be two, or a cut start.
        @Test func entryQuotingFindsMultiSentenceAndCutQuotes() {
            let other = Entry(text: "Usual gym, then home.", mood: "Content")
            #expect(InsightService.entryQuoting("Rohan left for Bangalore this morning for the new job. The flat feels too quiet without him.", in: [other, sad]) === sad)
            #expect(InsightService.entryQuoting("Missing him a lot tonight.", in: [other, sad]) === sad)
            #expect(InsightService.entryQuoting("Not in any entry at all.", in: [other, sad]) == nil)
        }

        // MARK: Other languages on Foundation Models

        private func germanDay() -> (entries: [Entry], plan: InsightService.LocalizedGrounded) {
            let entry = Entry(text: "Heute war ein langer Tag im Büro. Ich bin am Abend völlig erschöpft nach Hause gekommen.", mood: "Drained")
            let plan = InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: [])
            return ([entry], plan ?? InsightService.LocalizedGrounded(plan: .unsuitable, validator: nil))
        }

        @Test func aMatchedQuoteGetsTheFixedTranslatedLine() async throws {
            let (_, grounded) = germanDay()
            let validator = try #require(grounded.validator)
            #expect(!grounded.quoteOptions.isEmpty)
            let text = try #require(try await InsightService.structuredFMLocalizedNudge(
                options: grounded.quoteOptions, validator: validator, systemPrompt: "", userMessage: ""
            ) { (quote: "ich bin am abend völlig erschöpft nach hause gekommen", insight: "ignored, never shown") })
            let loc = try #require(InsightService.groundedLocales["de"])
            #expect(text.hasPrefix(loc.youWrote + loc.open + "Ich bin am Abend völlig erschöpft nach Hause gekommen." + loc.close))
            #expect(!text.contains("ignored"))
        }

        @Test func aQuoteThatIsNotTheirsRetriesThenGivesNothing() async throws {
            let (_, grounded) = germanDay()
            let validator = try #require(grounded.validator)
            var calls = 0
            let text = try await InsightService.structuredFMLocalizedNudge(
                options: grounded.quoteOptions, validator: validator, systemPrompt: "", userMessage: ""
            ) { calls += 1; return (quote: "Der Regen draußen machte mich traurig und still.", insight: "x") }
            #expect(text == nil)
            #expect(calls == InsightService.structuredNudgeAttempts)
        }

        @Test func theSheetShowsThePromptThatWasSentForAFoundationModelsRow() async throws {
            // English: written by the structured prompt, so not Gemma's instructions.
            let english = try #require(InsightService.assembleStructuredNudge(
                quote: "missing him a lot tonight.", insight: "You feel sad.", source: [sad], recentNudges: []
            ))
            let fm = InsightService.systemPrompt(for: .dailyNudge, content: english, engine: LLMEngine.foundationModels.rawValue)
            #expect(fm.ref.contains("DAILY_REFLECTION_FM_SYSTEM"))
            #expect(fm.body == DAILY_REFLECTION_FM_SYSTEM)
            let gemma = InsightService.systemPrompt(for: .dailyNudge, content: english, engine: LLMEngine.gemma.rawValue)
            #expect(gemma.ref.contains("DAILY_NUDGE_GEMMA_INSTRUCTIONS"))
            // German written by Foundation Models: the same prompt plus the "respond in German" line.
            let (_, grounded) = germanDay()
            let deValidator = try #require(grounded.validator)
            let german = try #require(try await InsightService.structuredFMLocalizedNudge(
                options: grounded.quoteOptions, validator: deValidator, systemPrompt: "", userMessage: ""
            ) { (quote: "Heute war ein langer Tag im Büro.", insight: "x") })
            let de = InsightService.systemPrompt(for: .dailyNudge, content: german, engine: LLMEngine.foundationModels.rawValue)
            #expect(de.ref.contains("DAILY_REFLECTION_FM_SYSTEM"))
            #expect(de.body.hasPrefix(DAILY_REFLECTION_FM_SYSTEM) && de.body != DAILY_REFLECTION_FM_SYSTEM)
            // The same German row from Gemma still shows Gemma's pick prompt.
            #expect(InsightService.systemPrompt(for: .dailyNudge, content: german, engine: LLMEngine.gemma.rawValue).ref.contains("pickNudge"))
        }

        @Test func aLanguageWithNoGroundedReflectionGetsTheHonestCardWithoutAModel() async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            // Dutch: not English and not one of the nine languages the app writes grounded reflections in.
            let dutch = Entry(text: "Vandaag was een lange dag op kantoor. Ik ben vanavond doodmoe thuisgekomen na het overleg met mijn baas.", mood: "Drained")
            let (text, _, degraded) = try await InsightService.generateNudge(entries: [dutch])
            #expect(text == InsightService.dailyNudgeUnsupportedLanguageNotice)
            #expect(InsightService.isUngroundedFallback(text))
            #expect(InsightService.isUnsupportedLanguageNotice(text))
            #expect(!text.contains("Try"))
            #expect(degraded)
            #expect(calls == 0)
        }

        @Test func aFailedAttemptIsRetried() async throws {
            let (_, grounded) = germanDay()
            let validator = try #require(grounded.validator)
            var calls = 0
            let text = try await InsightService.structuredFMLocalizedNudge(
                options: grounded.quoteOptions, validator: validator, systemPrompt: "", userMessage: ""
            ) {
                calls += 1
                if calls == 1 { throw LocalLLMError.emptyResponse }
                return (quote: "Heute war ein langer Tag im Büro.", insight: "x")
            }
            #expect(text != nil)
            #expect(calls == 2)
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
