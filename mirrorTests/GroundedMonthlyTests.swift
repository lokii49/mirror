import Testing
import Foundation
@testable import mirror

// The Gemma monthly-report path (2026-09-27): dated moment quotes, mood-split quotes, word-level
// free text. Synthetic entries only; no model runs.
@Suite(.serialized)
@MainActor
struct GroundedMonthlyTests {

    private func month() -> [Entry] {
        let calendar = Calendar(identifier: .gregorian)
        func entry(_ text: String, _ mood: String, day: Int) -> Entry {
            let e = Entry(text: text, mood: mood)
            e.createdAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
            return e
        }
        return [
            entry("Walked by the lake after work with the dog. Felt light for the first time this week.", "Peaceful", day: 23),
            entry("Landlord emailed that the rent goes up in November. Redid the budget and it still doesn't add up.", "Anxious", day: 18),
            entry("Annoyed that I stayed so long at that place. Packing up the old desk took all evening.", "Frustrated", day: 6),
        ]
    }

    private let validReport = """
        YOUR MONTH IN ONE IMAGE: A lighthouse beam sweeping over a restless sea.
        THE TENSION AT THE CENTER: You seem pulled between the pull of the new job and the weight of money worries.
        A MOMENT THAT SHIFTED SOMETHING: On 23 Sep, you wrote, "Felt light for the first time this week." It seems to have reminded you that calm is still reachable.
        WHAT YOU'RE BECOMING: You wrote, "Walked by the lake after work with the dog." You seem to be becoming someone who protects small quiet moments.
        WHAT WANTS TO BE RELEASED: You wrote, "Annoyed that I stayed so long at that place." Maybe it's time to let go of blaming yourself for the timing.
        YOUR QUESTION FOR NEXT MONTH: What would it take for you to plan one more lake walk each week?
        """

    @Test func momentsCarryTheirEntrysDateAndQuestionIsAQuestion() {
        let (plan, options) = InsightService.groundedMonthlyPlan(monthEntries: month())
        guard case .grammarConstrained(let message, let grammar) = plan else { Issue.record("expected grammar plan, got \(plan)"); return }
        #expect(message.contains(MONTHLY_REPORT_GEMMA_INSTRUCTIONS))
        #expect(options.contains(#"On 23 Sep, you wrote, "Felt light for the first time this week.""#))
        #expect(options.contains(#"On 18 Sep, you wrote, "Landlord emailed that the rent goes up in November.""#))
        #expect(!options.contains(#"On 23 Sep, you wrote, "Landlord emailed that the rent goes up in November.""#))
        #expect(grammar.contains(#"phrase "?""#))
    }

    @Test func optionsAreRoundRobinAcrossTheMonth() {
        let busy = Entry(text: (1...30).map { "Busy sentence number \($0) at work today." }.joined(separator: " "), mood: "Overwhelmed")
        let quiet = Entry(text: "Quiet Sunday, finished the novel I started in July.", mood: "Content")
        quiet.createdAt = busy.createdAt.addingTimeInterval(-20 * 86_400)
        let (_, options) = InsightService.groundedMonthlyPlan(monthEntries: [busy, quiet])
        #expect(options.contains { $0.contains("finished the novel") }, "an older entry must still be quotable")
    }

    @Test func griefEntriesNeverFeedTheLetGoSection() {
        let grief = Entry(text: "Grandpa's birthday would have been today. Made his dal recipe for dinner.", mood: "Sad")
        let (plan, options) = InsightService.groundedMonthlyPlan(monthEntries: month() + [grief])
        guard case .grammarConstrained(_, let grammar) = plan else { Issue.record("expected grammar plan"); return }
        let hardLine = grammar.components(separatedBy: "\n").first { $0.hasPrefix("hardq ::=") } ?? ""
        #expect(!hardLine.contains("Grandpa"))
        #expect(options.contains { $0.contains("Grandpa's birthday") }, "still quotable as a moment")
    }

    @Test func validatorAcceptsTheGrammarShape() throws {
        let (_, options) = InsightService.groundedMonthlyPlan(monthEntries: month())
        #expect(try InsightService.validateGroundedMonthly(validReport, quoteOptions: options) == validReport)
    }

    @Test func validatorRejectsWrongDatesInventedQuotesFirstPersonAndNonQuestions() {
        let (_, options) = InsightService.groundedMonthlyPlan(monthEntries: month())
        let wrongDate = validReport.replacingOccurrences(of: "On 23 Sep, you wrote", with: "On 6 Sep, you wrote")
        let invented = validReport.replacingOccurrences(of: "Annoyed that I stayed so long at that place.", with: "During a conversation with Bruno, I realized.")
        let firstPerson = validReport.replacingOccurrences(of: "blaming yourself", with: "blaming myself")
        let noQuestion = validReport.replacingOccurrences(of: "each week?", with: "each week.")
        for bad in [wrongDate, invented, firstPerson, noQuestion] {
            #expect(throws: InsightError.self) { try InsightService.validateGroundedMonthly(bad, quoteOptions: options) }
        }
    }

    @Test func gemmaReportSurvivesThePipelineUnmodified() async throws {
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in (self.validReport, .gemma) }
        defer { LocalLLMService.generateInterceptForTesting = nil }
        let (text, engine) = try await InsightService.generateMonthlyReport(monthEntries: month(), allEntries: month())
        #expect(text == validReport)
        #expect(engine == .gemma)
    }

    @Test func provenanceShowsTheGemmaInstructionsForGrammarReports() {
        #expect(InsightService.systemPrompt(for: .monthlyReport, content: validReport).body == MONTHLY_REPORT_GEMMA_INSTRUCTIONS)
    }
}
