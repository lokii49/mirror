import Testing
@testable import mirror

// Talk It Out fed every answer back to the model uncapped, so a long answer broke CLAUDE.md
// security rule 3 (at most 10,000 characters to the local LLM, oldest first) and overflowed
// Gemma's 4,096-token context. Synthetic text only.
@Suite("Talk It Out prompt budget")
struct GuidedQuestionBudgetTests {

    @Test func shortConversation_isSentWhole() {
        let message = InsightService.guidedQuestionUserMessage(conversationSoFar: [
            (question: "What's on your mind?", answer: "A quiet morning with tea."),
        ])
        #expect(message == "Conversation so far:\nQ: What's on your mind?\nA: A quiet morning with tea.\n\nAsk the next question.")
    }

    @Test func emptyConversation_asksTheFirstQuestion() {
        let message = InsightService.guidedQuestionUserMessage(conversationSoFar: [])
        #expect(message == "This is the start of a new guided journal entry. Ask your first question.")
    }

    @Test func longAnswers_areCutOldestFirst() {
        let turns: [(question: String, answer: String)] = [
            (question: "What's on your mind?", answer: "OLDEST " + String(repeating: "lorem ipsum ", count: 1_500)),
            (question: "What else?", answer: String(repeating: "dolor sit amet ", count: 1_000)),
            (question: "And then?", answer: "The newest answer ends here NEWEST"),
        ]
        let message = InsightService.guidedQuestionUserMessage(conversationSoFar: turns)
        #expect(message.count <= InsightService.guidedTranscriptBudget + 100)
        #expect(message.count <= 10_000)
        #expect(!message.contains("OLDEST"))
        #expect(message.contains("The newest answer ends here NEWEST"))
        #expect(message.hasSuffix("\n\nAsk the next question."))
    }

    @Test func oneHugeAnswer_keepsItsEnd() {
        let answer = String(repeating: "x", count: 20_000) + " END"
        let message = InsightService.guidedQuestionUserMessage(conversationSoFar: [
            (question: "What's on your mind?", answer: answer),
        ])
        #expect(message.count <= 10_000)
        #expect(message.contains("x END\n\nAsk the next question."))
    }
}
