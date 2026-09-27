import Testing
import Foundation
@testable import mirror

// The Gemma daily-nudge path (2026-09-26 root-cause fix): quote options cut verbatim from the
// entry, a GBNF grammar that only allows those quotes, and a validator that re-checks the shape
// after generation. All entries synthetic. No model runs — the intercept seam stands in for one.
@Suite(.serialized)
@MainActor
struct GroundedNudgeTests {

    private let sickDay = """
        Barely slept, got back from a late concert around 2 and my stomach was bad all night, \
        up four or five times. Woke at 10, way later than usual, drank ORS like Meera said. \
        Had lunch, slept again, got up at 5:30 and had some soup. Sat with Karan on the balcony \
        for a short chat. Came back to my room and showered, Dev texted that he'd come over, \
        let's see what happens.
        """

    // MARK: Quote options

    @Test func sentencesAreSplitVerbatim() {
        let options = InsightService.groundedNudgeQuoteCandidates(in: sickDay)
        #expect(options == [
            "Barely slept, got back from a late concert around 2 and my stomach was bad all night, up four or five times.",
            "Woke at 10, way later than usual, drank ORS like Meera said.",
            "Had lunch, slept again, got up at 5:30 and had some soup.",
            "Sat with Karan on the balcony for a short chat.",
            "Came back to my room and showered, Dev texted that he'd come over, let's see what happens.",
        ])
    }

    @Test func unpunctuatedRunOnIsChunkedVerbatimWithinTheLimit() {
        let runOn = "so today was kind of a mess honestly I woke up late again and missed the bus and then the whole morning just went sideways because the manager moved the standup and I hadn't prepped anything and by lunch I was just exhausted and kind of annoyed at myself for not sleeping earlier like I keep saying I will"
        let options = InsightService.groundedNudgeQuoteCandidates(in: runOn)
        #expect(!options.isEmpty)
        for option in options {
            #expect(option.count <= InsightService.groundedNudgeMaxQuoteChars)
            #expect(option.split(separator: " ").count >= InsightService.groundedNudgeMinQuoteWords)
            #expect(runOn.contains(option), "every chunk must be a verbatim substring")
        }
    }

    @Test func longSentenceSplitsAtClausesVerbatim() {
        let long = "After the meeting ran over by an hour, I walked to the station in the rain, missed the 6:10, waited forty minutes on the cold platform, and finally got home around nine, too tired to cook, so I ate cereal standing at the counter and went straight to bed."
        let options = InsightService.groundedNudgeQuoteCandidates(in: long)
        #expect(options.count >= 2)
        for option in options {
            #expect(option.count <= InsightService.groundedNudgeMaxQuoteChars)
            #expect(long.contains(option))
        }
    }

    @Test func listMarkersAreStrippedAndShortLinesDropped() {
        let text = "Things to sort this week\n- call the landlord about the leak\n- finish the tax forms\n☐ book the dentist now\n2. pay the phone bill today\nOk."
        let options = InsightService.groundedNudgeQuoteCandidates(in: text)
        #expect(options.contains("call the landlord about the leak"))
        #expect(options.contains("finish the tax forms"))
        #expect(options.contains("book the dentist now"))
        #expect(options.contains("pay the phone bill today"))
        #expect(!options.contains { $0.hasPrefix("-") || $0.hasPrefix("☐") || $0.hasPrefix("2.") })
        #expect(!options.contains("Ok."))
    }

    @Test func optionsAreCappedAndRecentQuotesExcluded() {
        let many = (1...40).map { "This is test sentence number \($0) today." }.joined(separator: " ")
        let entry = Entry(text: many, mood: "Content")
        let all = InsightService.groundedNudgeQuoteOptions(from: [entry])
        #expect(all.count == InsightService.groundedNudgeMaxQuoteOptions)

        let recentNudge = #"You wrote, "This is test sentence number 1 today." You seem settled."#
        let fresh = InsightService.groundedNudgeQuoteOptions(from: [entry], excludingQuotesIn: [recentNudge])
        #expect(!fresh.contains("This is test sentence number 1 today."))
    }

    @Test func exclusionNeverEmptiesTheOptions() {
        let entry = Entry(text: "Usual gym, then worked from home all day.", mood: "Content")
        let recent = [#"You wrote, "Usual gym, then worked from home all day." You seem steady."#]
        #expect(InsightService.groundedNudgeQuoteOptions(from: [entry], excludingQuotesIn: recent) == ["Usual gym, then worked from home all day."])
    }

    @Test func sourceIsNewestEntryPlusSameDayOnly() {
        let evening = Entry(text: "Evening was rough, argued with my brother on the phone.", mood: "Frustrated")
        let morning = Entry(text: "Ran 5k before work, legs felt heavy but I finished.", mood: "Energized")
        morning.createdAt = evening.createdAt.addingTimeInterval(-60)
        let yesterday = Entry(text: "Quiet day at home, watched a film with my flatmate.", mood: "Content")
        yesterday.createdAt = evening.createdAt.addingTimeInterval(-86_400)
        let source = InsightService.groundedNudgeSourceEntries([evening, morning, yesterday])
        #expect(source.map(\.text) == [evening.text, morning.text])
    }

    // MARK: Plan

    @Test func tooShortEntryHasNoGemmaSafeForm() {
        let (plan, options) = InsightService.groundedNudgePlan(recent: [Entry(text: "Tired.", mood: "Drained")], background: [], recentNudges: [])
        #expect(options.isEmpty)
        guard case .unsuitable = plan else { Issue.record("expected .unsuitable, got \(plan)"); return }
    }

    @Test func nonEnglishKeepsTheSharedPrompt() {
        let german = Entry(text: "Heute war ein langer Tag im Büro, aber am Abend bin ich mit meiner Schwester spazieren gegangen und habe mich endlich entspannt.", mood: "Content")
        let (plan, _) = InsightService.groundedNudgePlan(recent: [german], background: [], recentNudges: [])
        guard case .samePrompt = plan else { Issue.record("expected .samePrompt, got \(plan)"); return }
    }

    @Test func englishGetsGrammarWithEscapedLiterals() {
        let text = #"Mum said "don't worry about it" but I still feel bad 😔. The recipe called for half a cup and I used a whole one \ oops."#
        let (plan, options) = InsightService.groundedNudgePlan(recent: [Entry(text: text, mood: "Content")], background: [], recentNudges: [])
        guard case .grammarConstrained(let message, let grammar) = plan else { Issue.record("expected grammar plan, got \(plan)"); return }
        #expect(message.contains(DAILY_NUDGE_GEMMA_INSTRUCTIONS))
        #expect(options.contains(#"Mum said "don't worry about it" but I still feel bad 😔."#))
        #expect(grammar.contains(#""Mum said \"don't worry about it\" but I still feel bad 😔.""#))
        #expect(grammar.contains(#"one \\ oops."#))
        #expect(grammar.hasPrefix(#"root ::= "You wrote, \"" quote "\" " feel (" " tip)?"#))
    }

    // MARK: Validator

    private var sickOptions: [String] { InsightService.groundedNudgeQuoteCandidates(in: sickDay) }

    @Test func validatorAcceptsTheGrammarShape() throws {
        let good = #"You wrote, "Barely slept, got back from a late concert around 2 and my stomach was bad all night, up four or five times." You seem incredibly weary and depleted after a long, difficult night. Maybe keep today slow and gentle."#
        #expect(try InsightService.validateGroundedNudge(good, quoteOptions: sickOptions) == good)
    }

    @Test func validatorRejectsInventedOrMalformedQuotes() {
        let invented = #"You wrote, "Spent a quiet afternoon with Dev, laughing." You seem warm and settled."#
        let noPrefix = #"The rain outside feels heavy tonight. You seem tired."#
        let firstPersonAfter = #"You wrote, "Sat with Karan on the balcony for a short chat." You seem tired and my stomach still hurts."#
        let wrongShape = #"You wrote, "Sat with Karan on the balcony for a short chat." It was a lovely evening."#
        for bad in [invented, noPrefix, firstPersonAfter, wrongShape] {
            #expect(throws: InsightError.self) { try InsightService.validateGroundedNudge(bad, quoteOptions: sickOptions) }
        }
    }

    // MARK: Through generateNudge (intercepted, no model)

    @Test func gemmaQuoteSurvivesThePipelineUnmodified() async throws {
        let entry = Entry(text: "I felt awful after the long shift and I was too tired to cook dinner.", mood: "Drained")
        let reply = #"You wrote, "I felt awful after the long shift and I was too tired to cook dinner." You seem worn down. Maybe eat something simple and rest early."#
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in (reply, .gemma) }
        defer { LocalLLMService.generateInterceptForTesting = nil }
        let (text, engine, _) = try await InsightService.generateNudge(entries: [entry])
        // The generic cleaner would have rewritten "I felt"/"I was" inside the quote.
        #expect(text == reply)
        #expect(engine == .gemma)
    }

    // Routine entries start alike ("Usual gym, went to…"), so two different quotes share the
    // 7-word opening repeatsPriorOpening compares. On the grammar path a retry is the same prompt
    // with a new seed — it picks the same quote, so all 3 attempts would fail identically and a
    // perfectly good reflection would come back degraded. Recently-quoted-sentence exclusion is
    // the repeat guard for this format instead.
    @Test func similarRoutineOpeningIsNotTreatedAsARepeat() async throws {
        let entry = Entry(text: "Usual gym, went to the barber for a haircut and came back to the flat.", mood: "Content")
        let yesterday = #"You wrote, "Usual gym, went to the office and stayed late for the release." You seem steady and a little tired."#
        let reply = #"You wrote, "Usual gym, went to the barber for a haircut and came back to the flat." You seem settled and at ease today."#
        var calls = 0
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return (reply, .gemma) }
        defer { LocalLLMService.generateInterceptForTesting = nil }
        let (text, _, degraded) = try await InsightService.generateNudge(entries: [entry], recentNudges: [yesterday])
        #expect(calls == 1)
        #expect(text == reply)
        #expect(!degraded)
    }

    @Test func unquotableEntryOnGemmaOnlyDeviceSkipsTheModel() async throws {
        var calls = 0
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .gemma) }
        LocalLLMService.forceGemmaForTesting = true
        defer {
            LocalLLMService.generateInterceptForTesting = nil
            LocalLLMService.forceGemmaForTesting = false
        }
        let (text, _, degraded) = try await InsightService.generateNudge(entries: [Entry(text: "Tired.", mood: "Drained")])
        #expect(calls == 0)
        #expect(text == InsightService.dailyNudgeUngroundedFallback)
        #expect(degraded)
    }
}
