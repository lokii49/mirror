import Testing
import Foundation
@testable import mirror

/// 3.0.9: English daily reflections are SHOWN with a second sentence of the person's own, picked by
/// the app (`You also wrote, "…"`). It is built at display time and never stored: reflections sync,
/// and 3.0.8 / Mac 1.0.1 read them with the old parsers. Synthetic text only.
@Suite("Second quote")
struct SecondQuoteTests {
    private let exam = "Exam is on Friday and I've only covered half the syllabus. Studied in the library till nine. My roommate offered to quiz me tomorrow night."
    private let mainQuote = "Exam is on Friday and I've only covered half the syllabus."

    @Test @MainActor func picksTheLongestOtherSentence() {
        let entry = Entry(text: exam, mood: "Anxious")
        #expect(InsightService.secondGroundedQuote(excluding: mainQuote, source: [entry]) == "My roommate offered to quiz me tomorrow night.")
    }

    @Test @MainActor func skipsShortQuotedAndOverlappingSentences() {
        let entry = Entry(text: #"Long day at work today. Mum said "rest up" on the phone. Okay then. Long day at work today and more."#, mood: "Drained")
        // "Okay then." is too short, the Mum sentence has quote marks, the last one contains the main quote.
        #expect(InsightService.secondGroundedQuote(excluding: "Long day at work today.", source: [entry]) == nil)
    }

    @Test @MainActor func runOnChunksAreNeverUsed() {
        let runOn = Entry(text: "so today was kind of a mess honestly I woke up late again and missed the bus and then the whole morning just went sideways because the manager moved the standup and I hadn't prepped anything", mood: "Frustrated")
        let main = InsightService.groundedNudgeQuoteCandidates(in: runOn.text).first ?? ""
        #expect(InsightService.secondGroundedQuote(excluding: main, source: [runOn]) == nil)
    }

    @Test @MainActor func storedReflectionKeepsThe308Shape() throws {
        let entry = Entry(text: exam, mood: "Anxious")
        let stored = try #require(InsightService.assembleStructuredNudge(quote: mainQuote, insight: "You seem anxious about the exam.", source: [entry], recentNudges: []))
        #expect(!stored.contains("also wrote"))
        #expect(!stored.contains("roommate"))
    }

    @Test @MainActor func shownWithTheSecondQuoteBeforeTheTip() throws {
        let entry = Entry(text: exam, mood: "Anxious")
        let stored = try #require(InsightService.assembleStructuredNudge(quote: mainQuote, insight: "You seem anxious about the exam.", source: [entry], recentNudges: []))
        let shown = InsightService.reflectionWithAlsoQuote(stored, entries: [entry], generatedAt: Date().addingTimeInterval(60))
        #expect(shown.text.hasPrefix("You wrote, \"\(mainQuote)\" You seem anxious about the exam. You also wrote, \"My roommate offered to quiz me tomorrow night.\""))
        #expect(shown.parts?.alsoQuote == "My roommate offered to quiz me tomorrow night.")
        // A difficult day's fixed tip stays last.
        let tips = InsightService.groundedNudgeTips.values.joined()
        if tips.contains(where: { stored.hasSuffix($0) }) { #expect(tips.contains { shown.text.hasSuffix($0) }) }
    }

    @Test @MainActor func nothingAddedWithoutAnotherSentenceOrOutsideEnglish() {
        let single = Entry(text: "Studied in the library till nine.", mood: "Content")
        let stored = "You wrote, \"Studied in the library till nine.\" That sounds like a long day."
        let shown = InsightService.reflectionWithAlsoQuote(stored, entries: [single], generatedAt: Date().addingTimeInterval(60))
        #expect(shown.text == stored)
        #expect(shown.parts?.alsoQuote == nil)
        // Not a grounded reflection at all (e.g. the honest card): unchanged.
        let card = "MirrorNotes couldn't find a sentence to reflect on today."
        #expect(InsightService.reflectionWithAlsoQuote(card, entries: [single], generatedAt: Date()).text == card)
    }

    @Test @MainActor func entriesWrittenAfterTheReflectionAreNotUsed() {
        let entry = Entry(text: exam, mood: "Anxious")
        let stored = "You wrote, \"\(mainQuote)\" You seem anxious about the exam."
        let shown = InsightService.reflectionWithAlsoQuote(stored, entries: [entry], generatedAt: Date().addingTimeInterval(-3_600))
        #expect(shown.text == stored)
    }

    @Test func followUpNeverAsksAboutEitherQuote() throws {
        var parts = try #require(InsightService.groundedNudgeParts(of: "You wrote, \"\(mainQuote)\" You seem anxious about the exam."))
        parts.alsoQuote = "My roommate offered to quiz me tomorrow night."
        if let question = InsightService.followUpQuestion(for: parts, sourceText: exam) {
            #expect(!question.contains("roommate offered to quiz me"))
            #expect(!question.contains("covered half the syllabus"))
        }
    }
}
