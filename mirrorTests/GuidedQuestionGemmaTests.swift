import Testing
@testable import mirror

// writing-roadmap.md Tier 2's "discriminating test, not yet run": every prior test of
// generateFollowUp/generateGuidedQuestion exercised validate(_:for:) against hand-written
// fixtures, never actual model output. This suite calls the real pipeline.
//
// Surprising finding, recorded rather than assumed away: this suite was written expecting the
// simulator to guarantee the Gemma path (FoundationModelEngine "requires iOS 26+ on an
// Apple-Intelligence-eligible device, neither of which the simulator has"). On this Xcode
// 27 beta / iOS 27 SDK simulator that assumption is false — SystemLanguageModel.default
// .availability reports .available here, so LocalLLMService.generate took the Foundation
// Models branch on every run observed, never falling through to Gemma. There's no test seam to
// force the Gemma branch (LocalLLMService.generate has no injection point), so this suite
// validates conversation quality (question shape, no near-duplicates, no validator stalls)
// engine-agnostically and records which engine actually ran instead of asserting one. The
// Gemma-specific version of this question — does the 1B model specifically degrade by turn 3 —
// is still open; it needs either a real non-Apple-Intelligence device or a simulator/OS
// combination where Foundation Models genuinely reports unavailable.
@Suite("generateGuidedQuestion — real on-device inference, simulator-only")
struct GuidedQuestionGemmaTests {

    // Simulates the exact risk the roadmap named: by turn 2-3 the transcript fed back to the
    // model already contains multiple "?"-terminated lines (the seed question, plus answers that
    // themselves end in a question, which is a realistic thing for a user to type). Small models
    // tend to echo context, and validateFollowUp's "exactly one ?" rule turns an echoed or
    // compound reply into a rejection — localGenerate already retries once internally, so this
    // only surfaces if a turn fails validation twice in a row.
    @Test func turn2And3_withQuestionLikeAnswers_engineReportedAndMostlyValidates() async throws {
        // A silent `return` here would be indistinguishable from a real pass — this is the
        // discriminating test the marketing gate depends on, so failure to stage the model must
        // fail loud, not report green having run zero inference. Only relevant when Foundation
        // Models is unavailable and the Gemma fallback needs real weights on disk.
        if !FoundationModelEngine.isAvailable {
            guard GemmaModelTestSupport.ensureModelInstalled() else {
                Issue.record("dev .gguf not staged (mirror/LocalModels/ missing or copy failed) — this test ran no inference")
                return
            }
        }

        let seed = WritingPrompts.all[WritingPrompts.indexForToday()]
        var turns: [(question: String, answer: String)] = [
            (question: seed, answer: "Work's been a lot lately, not sure why?")
        ]
        var seenQuestions = [seed]
        var rejections = 0
        var enginesSeen: Set<LLMEngine> = []
        let attemptedTurns = 2 // turns 2 and 3 of a 3-question guided entry

        for _ in 0..<attemptedTurns {
            do {
                let result = try await InsightService.generateGuidedQuestion(conversationSoFar: turns)
                enginesSeen.insert(result.engine)
                #expect(result.text.hasSuffix("?"))

                for prior in seenQuestions {
                    let overlap = wordOverlapRatio(result.text, prior)
                    #expect(overlap < 0.8, "near-duplicate question: \"\(result.text)\" vs prior \"\(prior)\" (GUIDED_ENTRY_SYSTEM's \"don't repeat a question already asked\" is an unvalidated negative constraint — this is what its failure looks like)")
                }
                seenQuestions.append(result.text)
                turns.append((question: result.text, answer: "Yeah, something like that. What do you mean by that?"))
            } catch {
                rejections += 1
                // Still advance the transcript with a placeholder so the next turn sees the same
                // growing, question-mark-heavy context a real stalled conversation would.
                turns.append((question: "(generation failed)", answer: "Yeah, something like that. What do you mean by that?"))
            }
        }

        #expect(rejections == 0, "\(rejections)/\(attemptedTurns) guided-question turns were rejected by validateFollowUp (engines observed: \(enginesSeen.map(\.rawValue))) even after localGenerate's internal retry — this is the stall writing-roadmap.md's Tier 2 flagged as a risk, not a silent failure.")
        if enginesSeen == [.foundationModels] {
            // Not a failure — see this file's header comment. Printed (not Issue.record) so it
            // doesn't mark the run red, but still shows up in the xcodebuild log for anyone
            // checking whether the Gemma-specific question has actually been answered yet.
            print("[GuidedQuestionGemmaTests] Gemma path NOT exercised this run — every generation used Foundation Models on this simulator/OS.")
        }
    }
}

private func wordOverlapRatio(_ a: String, _ b: String) -> Double {
    let wordsA = Set(a.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    let wordsB = Set(b.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
    return Double(wordsA.intersection(wordsB).count) / Double(min(wordsA.count, wordsB.count))
}
