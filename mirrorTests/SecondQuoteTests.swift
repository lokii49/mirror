import Testing
import Foundation
@testable import mirror

/// 3.0.9: English daily reflections end with a second sentence of the person's own, picked by the
/// app (`You also wrote, "…"`). Synthetic text only.
@Suite("Second quote")
struct SecondQuoteTests {
    private let exam = "Exam is on Friday and I've only covered half the syllabus. Studied in the library till nine. My roommate offered to quiz me tomorrow night."

    @Test @MainActor func picksTheLongestOtherSentence() {
        let entry = Entry(text: exam, mood: "Anxious")
        let also = InsightService.secondGroundedQuote(excluding: "Exam is on Friday and I've only covered half the syllabus.", source: [entry])
        #expect(also == "My roommate offered to quiz me tomorrow night.")
    }

    @Test @MainActor func skipsShortQuotedAndOverlappingSentences() {
        let entry = Entry(text: #"Long day at work today. Mum said "rest up" on the phone. Okay then. Long day at work today and more."#, mood: "Drained")
        // "Okay then." is too short, the Mum sentence has quote marks, the last one contains the main quote.
        #expect(InsightService.secondGroundedQuote(excluding: "Long day at work today.", source: [entry]) == nil)
    }

    @Test @MainActor func nothingElseToQuoteMeansNoLine() {
        let entry = Entry(text: "Studied in the library till nine.", mood: "Content")
        #expect(InsightService.groundedAlsoLine(excluding: "Studied in the library till nine.", source: [entry]) == "")
    }

    @Test @MainActor func structuredReflectionAddsTheLineBeforeTheTip() throws {
        let entry = Entry(text: exam, mood: "Anxious")
        let text = try #require(InsightService.assembleStructuredNudge(
            quote: "Exam is on Friday and I've only covered half the syllabus.",
            insight: "You seem anxious about the exam.",
            source: [entry], recentNudges: []))
        #expect(text.hasPrefix("You wrote, \"Exam is on Friday and I've only covered half the syllabus.\" You seem anxious about the exam. You also wrote, \"My roommate offered to quiz me tomorrow night.\""))

        let parts = try #require(InsightService.groundedNudgeParts(of: text))
        #expect(parts.quote == "Exam is on Friday and I've only covered half the syllabus.")
        #expect(parts.alsoQuote == "My roommate offered to quiz me tomorrow night.")
        #expect(!parts.rest.contains("also wrote"))
        let authorship = InsightService.groundedRestAuthorship(parts)
        #expect(authorship.modelText == "You seem anxious about the exam.")
        // A difficult mood still gets its fixed tip, credited to the app.
        let tips = Set(InsightService.groundedNudgeTips.values.joined())
        if let app = authorship.appText { #expect(tips.contains(app)) }
    }

    @Test @MainActor func neitherQuoteLeavesTheApp() throws {
        let entry = Entry(text: exam, mood: "Anxious")
        let text = try #require(InsightService.assembleStructuredNudge(
            quote: "Exam is on Friday and I've only covered half the syllabus.",
            insight: "You seem anxious about the exam.",
            source: [entry], recentNudges: []))
        let outside = InsightService.nudgeTextForOutsideApp(text)
        #expect(outside.hasPrefix("You seem anxious about the exam."))
        #expect(!outside.contains("syllabus"))
        #expect(!outside.contains("roommate"))
        #expect(!outside.contains("also wrote"))
    }

    @Test func reflectionsSavedBeforeThisKeepParsing() throws {
        let old = "You wrote, \"Studied in the library till nine.\" That sounds like a long day."
        let parts = try #require(InsightService.groundedNudgeParts(of: old))
        #expect(parts.quote == "Studied in the library till nine.")
        #expect(parts.rest == "That sounds like a long day.")
        #expect(parts.alsoQuote == nil)
        #expect(InsightService.nudgeTextForOutsideApp(old) == "That sounds like a long day.")
    }

    @Test func followUpNeverAsksAboutEitherQuote() throws {
        let text = "You wrote, \"Exam is on Friday and I've only covered half the syllabus.\" You seem anxious about the exam. You also wrote, \"My roommate offered to quiz me tomorrow night.\""
        let parts = try #require(InsightService.groundedNudgeParts(of: text))
        let question = InsightService.followUpQuestion(for: parts, sourceText: exam)
        if let question {
            #expect(!question.contains("roommate offered to quiz me"))
            #expect(!question.contains("covered half the syllabus"))
        }
    }
}
