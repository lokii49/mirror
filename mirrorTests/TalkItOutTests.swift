import Testing
@testable import mirror

// composedText(from:) is the one pure, testable seam in TalkItOutView (writing-roadmap.md
// Tier 2) — everything else is either on-device LLM generation (InsightService.generateGuidedQuestion,
// which reuses the already-tested .followUp validator) or UI state (device/hands-only, same
// limitation as the rest of this session's work).
@Suite("TalkItOutView.composedText")
struct TalkItOutTests {

    @Test func singleTurn_isQuestionThenAnswer() {
        let text = TalkItOutView.composedText(from: [(question: "What's on your mind?", answer: "Work stuff.")])
        #expect(text == "What's on your mind?\nWork stuff.")
    }

    @Test func multipleTurns_separatedByBlankLine() {
        let turns: [(question: String, answer: String)] = [
            (question: "What's on your mind?", answer: "Work stuff."),
            (question: "What about work?", answer: "A deadline."),
        ]
        let text = TalkItOutView.composedText(from: turns)
        #expect(text == "What's on your mind?\nWork stuff.\n\nWhat about work?\nA deadline.")
    }

    @Test func emptyTurns_producesEmptyString() {
        #expect(TalkItOutView.composedText(from: []).isEmpty)
    }
}
