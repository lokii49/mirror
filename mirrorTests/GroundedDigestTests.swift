import Testing
import Foundation
@testable import mirror

// The Gemma weekly-digest path (2026-09-27): same grammar approach as GroundedNudgeTests, with
// quote options split by entry mood. Synthetic entries only; no model runs.
@Suite(.serialized)
@MainActor
struct GroundedDigestTests {

    private func week() -> [Entry] {
        let hard = Entry(text: "Client presentation got pushed to Thursday again. Feel behind on everything and the review is due Monday.", mood: "Overwhelmed")
        let good = Entry(text: "Walked by the lake after work with the dog. Felt light for the first time this week.", mood: "Peaceful")
        good.createdAt = hard.createdAt.addingTimeInterval(-86_400)
        return [hard, good]
    }

    private let validDigest = """
        THIS WEEK'S THEME: A week of deadlines shifting and one calm evening by the water.
        YOUR ENERGY: You seemed most stressed when you wrote, "Feel behind on everything and the review is due Monday." It sounds like the pressure is stacking up.
        WHAT'S BUILDING: You wrote, "Felt light for the first time this week." That sounds like a small reset worth protecting.
        WATCH OUT FOR: You wrote, "Client presentation got pushed to Thursday again." Watch whether the moving target keeps eating your evenings.
        MOOD BOOST: Try another short walk by the water after work tomorrow.
        NEXT WEEK: Maybe block one evening that stays free of work, whatever happens thursday.
        """

    @Test func quotesAreSplitByMoodIntoTheGrammar() {
        let (plan, options) = InsightService.groundedDigestPlan(weekEntries: week(), languageSource: week())
        guard case .grammarConstrained(let message, let grammar) = plan else { Issue.record("expected grammar plan, got \(plan)"); return }
        #expect(message.contains(WEEKLY_DIGEST_GEMMA_INSTRUCTIONS))
        #expect(options.contains("Felt light for the first time this week."))
        let goodLine = grammar.components(separatedBy: "\n").first { $0.hasPrefix("goodq ::=") } ?? ""
        let hardLine = grammar.components(separatedBy: "\n").first { $0.hasPrefix("hardq ::=") } ?? ""
        #expect(goodLine.contains("Felt light for the first time this week."))
        #expect(!goodLine.contains("Client presentation"))
        #expect(hardLine.contains("Client presentation got pushed to Thursday again."))
        #expect(!hardLine.contains("Felt light"))
        // Energy's adjective is bound to the quote's mood bucket.
        #expect(grammar.contains(#"(("drained" | "stressed" | "tired") " when you wrote, \"" hardq"#))
        #expect(grammar.contains(#"| ("light" | "calm" | "content") " when you wrote, \"" goodq)"#))
    }

    @Test func singleMoodWeekStillFillsBothBuckets() {
        let only = [Entry(text: "Spent the whole afternoon fixing the dashboard bug and finally found it.", mood: "Frustrated")]
        let (plan, _) = InsightService.groundedDigestPlan(weekEntries: only, languageSource: only)
        guard case .grammarConstrained(_, let grammar) = plan else { Issue.record("expected grammar plan, got \(plan)"); return }
        let goodLine = grammar.components(separatedBy: "\n").first { $0.hasPrefix("goodq ::=") } ?? ""
        #expect(goodLine.contains("dashboard bug"))
    }

    @Test func unquotableWeekHasNoGemmaSafeForm() {
        let tiny = [Entry(text: "Tired.", mood: "Drained"), Entry(text: "Ok day.", mood: "Content")]
        let (plan, _) = InsightService.groundedDigestPlan(weekEntries: tiny, languageSource: tiny)
        guard case .unsuitable = plan else { Issue.record("expected .unsuitable, got \(plan)"); return }
    }

    @Test func nonEnglishKeepsTheSharedPrompt() {
        let german = [Entry(text: "Heute war ein langer Tag im Büro, aber am Abend bin ich mit meiner Schwester spazieren gegangen.", mood: "Content")]
        let (plan, _) = InsightService.groundedDigestPlan(weekEntries: german, languageSource: german)
        guard case .samePrompt = plan else { Issue.record("expected .samePrompt, got \(plan)"); return }
    }

    @Test func validatorAcceptsTheGrammarShape() throws {
        let (_, options) = InsightService.groundedDigestPlan(weekEntries: week(), languageSource: week())
        let out = try InsightService.validateGroundedDigest(validDigest, quoteOptions: options)
        #expect(out == validDigest)
        // The card/widget parser still finds every section.
        #expect(InsightService.firstSectionBody(of: out, labels: InsightService.weeklyDigestSectionLabels)?.hasPrefix("A week of") == true)
    }

    @Test func validatorRejectsInventedQuotesMissingSectionsAndFirstPerson() {
        let (_, options) = InsightService.groundedDigestPlan(weekEntries: week(), languageSource: week())
        let invented = validDigest.replacingOccurrences(of: "Felt light for the first time this week.", with: "Spent the evening organizing my photography workflow.")
        let missing = validDigest.components(separatedBy: "\n").dropLast().joined(separator: "\n")
        let firstPerson = validDigest.replacingOccurrences(of: "Try another short walk by the water after work tomorrow.", with: "Try another walk, my evenings need it.")
        for bad in [invented, missing, firstPerson] {
            #expect(throws: InsightError.self) { try InsightService.validateGroundedDigest(bad, quoteOptions: options) }
        }
    }

    @Test func gemmaDigestSurvivesThePipelineUnmodified() async throws {
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in (self.validDigest, .gemma) }
        defer { LocalLLMService.generateInterceptForTesting = nil }
        let (text, engine) = try await InsightService.generateWeeklyDigest(weekEntries: week(), allEntries: week())
        #expect(text == validDigest)
        #expect(engine == .gemma)
    }

    @Test func provenanceShowsTheGemmaInstructionsForGrammarDigests() {
        #expect(InsightService.systemPrompt(for: .weeklyDigest, content: validDigest).body == WEEKLY_DIGEST_GEMMA_INSTRUCTIONS)
        #expect(InsightService.systemPrompt(for: .weeklyDigest, content: "THIS WEEK'S THEME: Settling in.").body != WEEKLY_DIGEST_GEMMA_INSTRUCTIONS)
    }
}
