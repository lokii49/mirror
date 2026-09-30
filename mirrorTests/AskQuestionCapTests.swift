import Testing
import Foundation
@testable import mirror

@Suite("Ask question cap")
struct AskQuestionCapTests {
    @Test func shortQuestionIsTrimmedOnly() {
        #expect(InsightService.cappedAskQuestion("  How am I?  ") == "How am I?")
    }

    @Test func longQuestionIsCutToTheCap() {
        let long = String(repeating: "a", count: InsightService.maxAskQuestionLength + 300)
        #expect(InsightService.cappedAskQuestion(long).count == InsightService.maxAskQuestionLength)
    }
}
