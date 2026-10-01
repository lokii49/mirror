import Testing
@testable import mirror

/// Reading a saved grounded reflection back into its quote and the line after it (used by the
/// Mac Today screen's highlight and "How this was generated" panel).
struct GroundedNudgePartsTests {

    @Test func englishReflectionSplitsIntoQuoteAndRest() throws {
        let text = "You wrote, \"I'm tired more than I'm upset.\" That sounds like a day that asked a lot of you."
        let parts = try #require(InsightService.groundedNudgeParts(of: text))
        #expect(parts.quote == "I'm tired more than I'm upset.")
        #expect(parts.rest == "That sounds like a day that asked a lot of you.")
        #expect(parts.languageCode == "en")
        #expect(parts.open == "\"" && parts.close == "\"")
    }

    @Test func everyLocalizedShapeIsRecognised() throws {
        for (code, loc) in InsightService.groundedLocales {
            let text = loc.youWrote + loc.open + "Quote words go right here" + loc.close + loc.joiner + "Fixed line."
            let parts = try #require(InsightService.groundedNudgeParts(of: text), "\(code)")
            #expect(parts.quote == "Quote words go right here", "\(code)")
            #expect(parts.rest == "Fixed line.", "\(code)")
            #expect(parts.open == loc.open && parts.close == loc.close, "\(code)")
        }
    }

    @Test func freeProseIsNotParsed() {
        #expect(InsightService.groundedNudgeParts(of: "You keep coming back to the conversation you didn't finish.") == nil)
    }

    @Test func followUpAsksAboutAnotherPartOfTheEntry() throws {
        let parts = try #require(InsightService.groundedNudgeParts(of: "You wrote, \"I'm tired more than I'm upset.\" That sounds draining."))
        let entry = "Slow day. Nothing went wrong and I still feel flat. I'm tired more than I'm upset."
        let question = try #require(InsightService.followUpQuestion(for: parts, sourceText: entry))
        #expect(question.contains("Nothing went wrong and I still feel flat"))
        #expect(!question.contains("tired more than"))
    }

    @Test func noFollowUpWhenTheEntryHasNothingElseQuotable() throws {
        let parts = try #require(InsightService.groundedNudgeParts(of: "You wrote, \"I'm tired more than I'm upset.\" That sounds draining."))
        #expect(InsightService.followUpQuestion(for: parts, sourceText: "I'm tired more than I'm upset.") == nil)
    }
}
