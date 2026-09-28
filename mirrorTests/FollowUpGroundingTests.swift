import Testing
import Foundation
@testable import mirror

// Follow-up chip on Gemma (2026-09-28): Gemma only picks one numbered part of the draft under a
// literal grammar, and the app composes the question (InsightService.groundedFollowUpPlan). The
// candidate builder and composition are pure; the generateFollowUp cases go through
// LocalLLMService.generateInterceptForTesting, so no model runs here. Measured behaviour lives in
// tools/llmrig/README.md; GroundingSampleHarness.test_followUp_fullPipeline runs the real model.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct FollowUpGroundingTests {

        private static let allRigDrafts = GroundingSampleHarness.followUpRigCases
            + GroundingSampleHarness.followUpPrototypeExtraCases
            + GroundingSampleHarness.followUpHeldOutCases
            + GroundingSampleHarness.followUpFrRuCases

        // MARK: Candidates

        @Test func everyCandidate_isAVerbatimPartOfTheDraft_andShortEnoughToQuote() {
            for c in Self.allRigDrafts {
                let options = InsightService.followUpPhraseCandidates(in: c.draft)
                #expect(!options.isEmpty, "\(c.label)")
                for option in options {
                    #expect(c.draft.contains(option), "\(c.label): \(option)")
                    #expect(option.count <= InsightService.followUpPhraseMaxChars, "\(c.label): \(option)")
                }
            }
        }

        @Test func germanSubordinateClause_staysAttachedToItsSentence() {
            let draft = "Letzte Nacht kaum geschlafen, mein Magen hat bis fast vier Uhr rumort. Ich habe mich krankgemeldet und den ganzen Tag auf dem Sofa verbracht. Dev hat geschrieben, dass er vielleicht später mit Suppe vorbeikommt, aber ich weiß nicht, ob ich Besuch will."
            #expect(InsightService.followUpPhraseCandidates(in: draft) == [
                "Letzte Nacht kaum geschlafen, mein Magen hat bis fast vier Uhr rumort",
                "Ich habe mich krankgemeldet und den ganzen Tag auf dem Sofa verbracht",
                "Dev hat geschrieben, dass er vielleicht später mit Suppe vorbeikommt, aber ich weiß nicht",
                "ob ich Besuch will",
            ])
        }

        @Test func unpunctuatedRunOn_splitsBeforeAConjunction_andKeepsItsLastPart() {
            let draft = "ugh so tired today gym at 7 then back to back meetings till 5 forgot lunch again and still need to sort out the car insurance thing before friday"
            #expect(InsightService.followUpPhraseCandidates(in: draft) == [
                "ugh so tired today gym at 7 then back to back meetings till 5 forgot lunch again",
                "and still need to sort out the car insurance thing before friday",
            ])
        }

        @Test func unspacedJapaneseSentence_isCutIntoVerbatimWindows() {
            let sentence = String(repeating: "今日は朝から会議が続いて昼ごはんを食べる時間もなくて夕方にはもう頭が回らなかった", count: 3) + "。"
            let options = InsightService.followUpPhraseCandidates(in: sentence)
            #expect(options.count > 1)
            for option in options {
                #expect(sentence.contains(option))
                #expect(option.count <= InsightService.followUpPhraseMaxChars)
                #expect(option.count >= InsightService.groundedMinCJKQuoteChars)
            }
        }

        // Tapping the chip appends the composed question to the draft; ~20 words later it would
        // otherwise be a candidate itself: What's underneath "What's underneath "…""?
        @Test(arguments: [
            ("en", "I feel so behind, and I snapped at Omar in standup for no reason.\nWhat's underneath \"I feel so behind, and I snapped at Omar in standup for no reason\"?\nI think it is the deadline more than anything else going on."),
            ("fr", "Je repense sans arrêt à la dispute avec Jonas vendredi.\nTu veux en dire plus sur «\u{00A0}Je repense sans arrêt à la dispute avec Jonas vendredi\u{00A0}»\u{00A0}?\nJe crois que j'ai été injuste avec lui ce jour-là."),
            ("ja", "今日は会議が続いて昼ごはんを食べる時間もなかった。\n「今日は会議が続いて昼ごはんを食べる時間もなかった」について、もう少し書いてみませんか？\n夕方にはもう頭が回らなかった。"),
        ])
        func anInsertedChipQuestion_isNeverOfferedAsAPart(code: String, draft: String) {
            let options = InsightService.followUpPhraseCandidates(in: draft)
            #expect(!options.isEmpty, "\(code)")
            #expect(!options.contains { $0.contains("underneath") || $0.contains("Tu veux en dire plus") || $0.contains("もう少し書いてみませんか") }, "\(code): \(options)")
        }

        @Test func longDraft_keepsOnlyItsLastParts() {
            let draft = (1...20).map { "Sentence number \($0) is about something else entirely." }.joined(separator: " ")
            let options = InsightService.followUpPhraseCandidates(in: draft)
            #expect(options.count == InsightService.followUpMaxPhrases)
            #expect(options.last == "Sentence number 20 is about something else entirely")
        }

        // MARK: Plan

        @Test func englishPlan_numbersTheParts_andConstrainsTheOutputToThem() throws {
            let draft = "Slow Sunday. Read on the balcony for a while. Keep replaying the argument with Jonas from Friday, I think I was unfair to him. Made pasta for dinner."
            let grounded = InsightService.groundedFollowUpPlan(draft: draft, languageCode: "en")
            guard case .grammarConstrained(let message, let grammar) = grounded.plan else {
                Issue.record("expected a grammar-constrained plan, got \(grounded.plan)")
                return
            }
            #expect(message.hasPrefix("Journal entry:\n\(draft)\n\nParts of the entry:\n1. Read on the balcony for a while\n2. "))
            #expect(message.hasSuffix(FOLLOW_UP_GEMMA_INSTRUCTIONS))
            #expect(grammar.hasPrefix("root ::= "))
            #expect(grammar.contains(#""Keep replaying the argument with Jonas from Friday, I think I was unfair to him""#))
        }

        @Test func photoTokens_neverReachThePromptOrTheParts() throws {
            let draft = "Took Bruno for a long walk around the lake. [[mirror-photo-0]] I should call Anu tomorrow, it's been weeks."
            let grounded = InsightService.groundedFollowUpPlan(draft: draft, languageCode: "en")
            guard case .grammarConstrained(let message, let grammar) = grounded.plan else {
                Issue.record("expected a grammar-constrained plan")
                return
            }
            #expect(!message.contains("mirror-photo"))
            #expect(!grammar.contains("mirror-photo"))
        }

        @Test(arguments: ["nl", "hi", "sv"])
        func languagesOutsideTheGroundedTen_getNoGemmaFollowUp(code: String) {
            let grounded = InsightService.groundedFollowUpPlan(draft: "Vandaag was een lange dag op kantoor en ik ben moe.", languageCode: code)
            guard case .unsuitable = grounded.plan else { Issue.record("\(code): expected .unsuitable"); return }
        }

        @Test func draftWithNothingQuotable_getsNoGemmaFollowUp() {
            guard case .unsuitable = InsightService.groundedFollowUpPlan(draft: "ok", languageCode: "en").plan else {
                Issue.record("expected .unsuitable")
                return
            }
        }

        // MARK: Validator + composition

        @Test func validator_composesTheQuestion_andRejectsAnythingNotOffered() throws {
            let draft = "The client presentation got moved up to Thursday and the dashboard bug still isn't fixed. Nisha wants to review everything on Monday. I feel so behind, and I snapped at Omar in standup for no reason."
            let validator = try #require(InsightService.groundedFollowUpPlan(draft: draft, languageCode: "en").validator)
            let question = try validator("I feel so behind, and I snapped at Omar in standup for no reason")
            #expect(question.contains(#""I feel so behind, and I snapped at Omar in standup for no reason""#))
            #expect(question.hasSuffix("?"))
            #expect(throws: InsightError.self) { try validator("The rain outside feels heavy tonight") }
        }

        @Test func composition_dropsALeadingConjunctionAndInvertedMark() throws {
            let english = InsightService.composedFollowUpQuestion(
                phrase: "and ben said hes being bullied at school again",
                templates: ["What's underneath {quote}?"], open: "\"", close: "\""
            )
            #expect(english == #"What's underneath "ben said hes being bullied at school again"?"#)
            let es = try #require(InsightService.groundedLocales["es"])
            let spanish = InsightService.composedFollowUpQuestion(
                phrase: "¡Me llegó el correo de aceptación del programa de Lisboa",
                templates: es.followUpQuestion, open: es.open, close: es.close
            )
            #expect(spanish.contains("“Me llegó el correo de aceptación del programa de Lisboa”"))
            // A short phrase keeps its conjunction rather than lose half its words.
            let short = InsightService.composedFollowUpQuestion(phrase: "and it rained", templates: ["{quote}?"], open: "", close: "")
            #expect(short == "and it rained?")
        }

        @Test func everyGroundedLanguage_hasTwoTemplatesWithOneQuoteSlot() {
            for (code, loc) in InsightService.groundedLocales {
                #expect(loc.followUpQuestion.count == 2, "\(code)")
                for template in loc.followUpQuestion {
                    #expect(template.components(separatedBy: "{quote}").count == 2, "\(code): \(template)")
                }
                #expect(!loc.pickFollowUp.isEmpty && !loc.partsLabel.isEmpty, "\(code)")
            }
        }

        @Test func frenchAndRussianQuestions_sayTuAndTy() throws {
            let fr = try #require(InsightService.groundedLocales["fr"])
            let frQuestions = fr.followUpQuestion.map { $0.replacingOccurrences(of: "{quote}", with: fr.open + "x" + fr.close) }
            #expect(frQuestions.allSatisfy { !$0.contains("vous") })
            #expect(frQuestions.contains { $0.contains("Tu ") })
            let ru = try #require(InsightService.groundedLocales["ru"])
            #expect(ru.followUpQuestion.allSatisfy { !$0.lowercased().contains("вы ") && !$0.contains("Вам") })
        }

        // MARK: Through generateFollowUp

        @Test func gemmaPick_comesBackAsTheComposedQuestion() async throws {
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in
                ("I feel so behind, and I snapped at Omar in standup for no reason", .gemma)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let result = try await InsightService.generateFollowUp(currentText: "The client presentation got moved up to Thursday. I feel so behind, and I snapped at Omar in standup for no reason.")
            #expect(result.engine == .gemma)
            #expect(result.text.contains(#""I feel so behind, and I snapped at Omar in standup for no reason""#))
        }

        @Test func gemmaOutputThatIsNotAPart_neverBecomesAChip() async {
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in ("What specific feeling did the rain evoke?", .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let result = try? await InsightService.generateFollowUp(currentText: "ugh so tired today gym at 7 then back to back meetings till 5 forgot lunch again")
            #expect(result?.text == nil)
        }

        @Test func foundationModels_keepsWritingItsOwnQuestion() async throws {
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in ("What's underneath that tiredness?", .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let result = try await InsightService.generateFollowUp(currentText: "So tired today, back to back meetings until five and I forgot lunch again.")
            #expect(result.engine == .foundationModels)
            #expect(result.text == "What's underneath that tiredness?")
        }
    }
}
