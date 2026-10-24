import Testing
import Foundation
@testable import mirror

// The Gemma Ask path (2026-09-27): answers are only the user's own dated sentences, with
// deterministic relevance help. Synthetic entries only; no model runs.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct GroundedAskTests {

        private func pool() -> [Entry] {
            let calendar = Calendar(identifier: .gregorian)
            func entry(_ text: String, _ mood: String, day: Int) -> Entry {
                let e = Entry(text: text, mood: mood)
                e.createdAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
                return e
            }
            return [
                entry("Barely slept, my stomach was bad all night. Woke at 10, way later than usual.", "Drained", day: 27),
                entry("Client presentation got pushed to Thursday again. Feel behind on everything this week.", "Overwhelmed", day: 24),
                entry("Walked by the lake after work with the dog. Felt light for the first time this week.", "Peaceful", day: 23),
                entry("Usual gym session in the morning, then worked from home all day.", "Content", day: 22),
            ]
        }

        // A "not written about this" verdict was measured unsafe (false for "Do I exercise?" over a
        // gym entry, "How are my finances?" over a rent entry) and removed: an unrelated question
        // still gets the closest sentences, under a heading that says exactly that.
        @Test func questionAboutSomethingNeverWrittenStillGetsClosestSentences() {
            let plan = InsightService.groundedAskPlan(question: "How is my guitar practice going?", pool: pool(), languageCode: "en")
            #expect(!plan.noAnswer)
            #expect(!plan.quoteOptions.isEmpty)
            for question in ["Do I exercise?", "How are my finances?", "What was my mood like?"] {
                #expect(!InsightService.groundedAskPlan(question: question, pool: pool(), languageCode: "en").noAnswer, "\(question)")
            }
        }

        @Test func stemmingMatchesIrregularAndSuffixedForms() {
            #expect(InsightService.askStem("slept") == "sleep")
            #expect(InsightService.askStem("sleeping") == "sleep")
            #expect(InsightService.askStem("worked") == "work")
            #expect(InsightService.askTerms(for: "How has my sleep been?").contains("sleep"))
        }

        @Test func sleepQuestionFindsTheEntryThatSaysSlept() {
            let plan = InsightService.groundedAskPlan(question: "How has my sleep been lately?", pool: pool(), languageCode: "en")
            #expect(!plan.noAnswer)
            #expect(plan.quoteOptions.first?.contains("Barely slept") == true, "entries mentioning the question's terms are offered first")
        }

        @Test func stressQuestionOnlyOffersHardMoodEntries() {
            let plan = InsightService.groundedAskPlan(question: "What has been stressing me at work?", pool: pool(), languageCode: "en")
            #expect(!plan.noAnswer)
            #expect(plan.quoteOptions.contains { $0.contains("Client presentation") })
            #expect(!plan.quoteOptions.contains { $0.contains("Walked by the lake") })
            #expect(!plan.quoteOptions.contains { $0.contains("Usual gym") })
        }

        @Test func happyQuestionOnlyOffersGoodMoodEntries() {
            let plan = InsightService.groundedAskPlan(question: "When was I happy this week?", pool: pool(), languageCode: "en")
            #expect(plan.quoteOptions.contains { $0.contains("Walked by the lake") })
            #expect(!plan.quoteOptions.contains { $0.contains("Barely slept") })
        }

        // The English plan steps aside for other languages; localizedGroundedAsk owns those
        // (GroundedLocalizedTests).
        @Test func englishPlanStepsAsideForOtherLanguages() {
            let plan = InsightService.groundedAskPlan(question: "Wie schlafe ich?", pool: pool(), languageCode: "de")
            guard case .samePrompt = plan.plan else { Issue.record("expected .samePrompt"); return }
            #expect(!plan.noAnswer)
        }

        @Test func validatorAcceptsOneOrTwoQuotesAndNothingElse() throws {
            let options = InsightService.groundedAskPlan(question: "How has my sleep been lately?", pool: pool(), languageCode: "en").quoteOptions
            let one = InsightService.groundedAskPrefix + options[0]
            let two = one + " " + options[1]
            #expect(try InsightService.validateGroundedAsk(one, quoteOptions: options) == one)
            #expect(try InsightService.validateGroundedAsk(two, quoteOptions: options) == two)
            #expect(try InsightService.validateGroundedAsk(one + " " + options[0], quoteOptions: options) == one, "a repeated quote is dropped")
            let commentary = one + " That sounds like you spent time with friends."
            let invented = InsightService.groundedAskPrefix + #"On 27 Sep, you wrote, "Spent the evening with friends after the concert.""#
            let three = two + " " + options[2]
            for bad in [commentary, invented, three, options[0]] {
                #expect(throws: InsightError.self) { try InsightService.validateGroundedAsk(bad, quoteOptions: options) }
            }
        }

        // English Ask on Gemma (2026-10-24, tools/llmrig/ask/RUBRIC.md): the closest sentence, no model run.
        @Test func englishAskOnGemmaShowsTheClosestSentenceWithoutAModel() async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .gemma) }
            LocalLLMService.forceGemmaForTesting = true
            defer {
                LocalLLMService.generateInterceptForTesting = nil
                LocalLLMService.forceGemmaForTesting = false
            }
            let (text, engine) = try await InsightService.ask(question: "How has my sleep been lately?", entries: pool())
            #expect(calls == 0)
            #expect(engine == .search)
            // Either sentence of the sleep entry: with Smart Search's model in the test host (AskPickRigDump
            // leaves it in the simulator) the semantic score may pick its second one.
            let sleepEntry = ["Barely slept, my stomach was bad all night.", "Woke at 10, way later than usual."]
            #expect(sleepEntry.contains { text == InsightService.groundedAskPrefix + "On 27 Sep, you wrote, \"\($0)\"" }, "\(text)")
            #expect(InsightService.isGrammarGrounded(text), "same shape as Gemma's grounded answers, so saved-insight passes leave it alone")
        }

        @Test func rankedAnswerKeepsTheMoodRouting() async throws {
            let text = try #require(await InsightService.rankedAskAnswer(question: "What has been stressing me at work?", pool: pool()))
            #expect(!text.contains("Walked by the lake"))
            #expect(!text.contains("Usual gym"))
        }

        @Test func rankedAnswerIsOneVerbatimSentence() async throws {
            let text = try #require(await InsightService.rankedAskAnswer(question: "Did I go to the gym?", pool: pool()))
            let options = InsightService.groundedAskPlan(question: "Did I go to the gym?", pool: pool(), languageCode: "en").quoteOptions
            #expect(try InsightService.validateGroundedAsk(text, quoteOptions: options) == text)
            #expect(text.contains("Usual gym session"))
            #expect(await InsightService.rankedAskAnswer(question: "Anything?", pool: [Entry(text: "Tired.", mood: "Drained")]) == nil)
        }

        // Round 2 (tools/llmrig/ask/RUBRIC.md): a second sentence only on Smart Search scores at or above the floor.
        @Test func secondSentenceNeedsTheFloorAndTheSearchModel() async throws {
            let question = "How has my sleep been lately?"
            func scorer(second: Float) -> (String, [String]) async -> [Float]? {
                { _, quotes in quotes.map { $0.hasPrefix("Barely slept") ? 0.7 : $0.hasPrefix("Woke at 10") ? second : 0.1 } }
            }
            let prefix = InsightService.groundedAskPrefix + #"On 27 Sep, you wrote, "Barely slept, my stomach was bad all night.""#
            let two = try #require(await InsightService.rankedAskAnswer(question: question, pool: pool(), scorer: scorer(second: InsightService.askSecondQuoteFloor)))
            #expect(two == prefix + #" On 27 Sep, you wrote, "Woke at 10, way later than usual.""#)
            let options = InsightService.groundedAskPlan(question: question, pool: pool(), languageCode: "en").quoteOptions
            #expect(try InsightService.validateGroundedAsk(two, quoteOptions: options) == two, "same two-quote shape Gemma's grammar allowed")
            #expect(InsightService.isGrammarGrounded(two))
            #expect(await InsightService.rankedAskAnswer(question: question, pool: pool(), scorer: scorer(second: 0.44)) == prefix)
            let wordMatch = try #require(await InsightService.rankedAskAnswer(question: question, pool: pool(), scorer: { _, _ in nil }))
            #expect(wordMatch.components(separatedBy: ", you wrote, ").count == 2, "word-match scores show one sentence")
        }

        @Test func howThisWasGeneratedSaysNoModelRan() {
            let prompt = InsightService.systemPrompt(for: .askResponse, content: InsightService.groundedAskPrefix + "x", engine: LLMEngine.search.rawValue)
            #expect(prompt.ref.hasSuffix("rankedAskAnswer"))
            #expect(prompt.body.hasPrefix("No language model wrote or picked this answer."))
        }

        @Test func noQuotableEntriesOnGemmaOnlyDeviceSkipsTheModel() async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .gemma) }
            LocalLLMService.forceGemmaForTesting = true
            defer {
                LocalLLMService.generateInterceptForTesting = nil
                LocalLLMService.forceGemmaForTesting = false
            }
            let (text, _) = try await InsightService.ask(question: "How is my guitar practice going?", entries: [Entry(text: "Tired.", mood: "Drained")])
            #expect(calls == 0)
            #expect(text == "You haven't written about this yet.")
        }
    }
}
