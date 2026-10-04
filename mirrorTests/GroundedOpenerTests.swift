import Testing
import Foundation
@testable import mirror

@Suite("Grounded nudge openers")
struct GroundedOpenerTests {
    private let quote = "Finished the report and went for a long walk afterwards."
    private func nudge(_ opener: String) -> String { "\(opener)\(quote)\" You seem calm and a little proud." }

    @Test func firstOpenerStaysTheOriginal() {
        #expect(InsightService.groundedNudgeOpeners.first == InsightService.groundedNudgePrefix)
        #expect(InsightService.groundedNudgePrefix == "You wrote, \"")
    }

    @Test func rotationAdvancesAndWraps() {
        let o = InsightService.groundedNudgeOpeners
        #expect(InsightService.nextGroundedNudgeOpener(after: []) == o[0])
        #expect(InsightService.nextGroundedNudgeOpener(after: ["not a grounded nudge"]) == o[0])
        for (i, opener) in o.enumerated() {
            #expect(InsightService.nextGroundedNudgeOpener(after: [nudge(opener)]) == o[(i + 1) % o.count])
        }
    }

    @Test func everyOpenerIsRecognisedAsGrounded() {
        for opener in InsightService.groundedNudgeOpeners {
            #expect(InsightService.isGrammarGrounded(nudge(opener)))
        }
    }

    @Test func validatorAcceptsEveryOpener() throws {
        for opener in InsightService.groundedNudgeOpeners {
            #expect(try InsightService.validateGroundedNudge(nudge(opener), quoteOptions: [quote]) == nudge(opener))
        }
    }

    @Test func validatorStillRejectsAnUnknownOpener() {
        #expect(throws: (any Error).self) {
            try InsightService.validateGroundedNudge(self.nudge("Here is what you said, \""), quoteOptions: [self.quote])
        }
    }

    @Test func widgetTextDropsTheQuoteForEveryOpener() {
        for opener in InsightService.groundedNudgeOpeners {
            #expect(InsightService.nudgeTextForOutsideApp(nudge(opener)) == "You seem calm and a little proud.")
        }
    }

    @Test func grammarAndInstructionsUseTheChosenOpener() {
        for opener in InsightService.groundedNudgeOpeners {
            let grammar = InsightService.groundedNudgeGrammar(quotes: [quote], opener: opener)
            let escaped = String(opener.dropLast()) + "\\\""
            #expect(grammar.hasPrefix("root ::= \"\(escaped)\" quote"))
            #expect(InsightService.groundedNudgeInstructions(opener: opener).contains("\(opener)<copy"))
        }
        // The default still matches the original grammar exactly.
        #expect(InsightService.groundedNudgeGrammar(quotes: [quote]).hasPrefix(#"root ::= "You wrote, \"" quote "\" " feel"#))
    }

    @Test func moodOfQuotedEntryFindsTheQuoteUnderAnyOpener() {
        let entry = Entry(text: quote, mood: "Content")
        for opener in InsightService.groundedNudgeOpeners {
            #expect(InsightService.moodOfQuotedEntry(nudge(opener), source: [entry]) == "Content")
        }
    }

    @Test func recentQuotesAreExcludedUnderAnyOpener() {
        let entry = Entry(text: "Made a big pot of soup for the whole week ahead. Then I cleaned the kitchen.", mood: nil)
        let all = InsightService.groundedNudgeQuoteOptions(from: [entry])
        #expect(all.count >= 2)
        for opener in InsightService.groundedNudgeOpeners {
            let recent = ["\(opener)\(all[0])\" You seem steady."]
            let options = InsightService.groundedNudgeQuoteOptions(from: [entry], excludingQuotesIn: recent)
            #expect(!options.contains(all[0]))
        }
    }
}
