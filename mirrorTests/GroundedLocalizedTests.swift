import Testing
import Foundation
@testable import mirror

// Non-English grounded insights on Gemma (2026-09-27): the model only picks sentences; the app
// composes fixed, translated text around them. Synthetic entries only; no model runs.
@Suite(.serialized)
@MainActor
struct GroundedLocalizedTests {

    /// One natural, clearly-identifiable sick-day entry per supported language.
    static let sickDay: [String: String] = [
        "de": "Kaum geschlafen, kam gegen 2 von einem späten Konzert zurück und mein Magen war die ganze Nacht schlecht. Um 10 aufgewacht, viel später als sonst. Saß mit Karan auf dem Balkon für ein kurzes Gespräch.",
        "es": "Casi no dormí, volví de un concierto tarde y tuve el estómago mal toda la noche. Me desperté a las 10, mucho más tarde de lo normal. Me senté con Karan en el balcón para charlar un rato.",
        "fr": "J'ai à peine dormi, je suis rentré tard d'un concert et j'ai eu mal au ventre toute la nuit. Je me suis réveillé à 10 heures, bien plus tard que d'habitude. J'ai discuté un moment avec Karan sur le balcon.",
        "it": "Ho dormito pochissimo, sono tornato tardi da un concerto e ho avuto mal di stomaco tutta la notte. Mi sono svegliato alle 10, molto più tardi del solito. Ho chiacchierato un po' con Karan sul balcone.",
        "pt": "Quase não dormi, voltei tarde de um show e fiquei com dor de estômago a noite toda. Acordei às 10, bem mais tarde do que o normal. Conversei um pouco com o Karan na varanda.",
        "ru": "Почти не спал, вернулся поздно с концерта, и всю ночь болел живот. Проснулся в 10, намного позже обычного. Посидел с Караном на балконе, немного поговорили.",
        "ja": "ほとんど眠れなかった。遅いコンサートから帰ってきて、一晩中お腹の調子が悪かった。いつもよりずっと遅い10時に起きた。バルコニーでカランと少し話した。",
        "ko": "거의 잠을 못 잤다. 늦은 콘서트에서 돌아와서 밤새 배가 아팠다. 평소보다 훨씬 늦은 10시에 일어났다. 발코니에서 카란과 잠깐 이야기를 나눴다.",
        "zh": "几乎没睡，听完晚场音乐会很晚才回来，整晚肚子都不舒服。比平时晚很多，十点才醒。和卡兰在阳台上聊了一会儿。",
    ]

    @Test func cjkSentencesSplitOnTheirOwnPunctuationVerbatim() {
        let ja = Self.sickDay["ja"]!
        let options = InsightService.groundedNudgeQuoteCandidates(in: ja)
        #expect(options.contains("遅いコンサートから帰ってきて、一晩中お腹の調子が悪かった。"))
        #expect(options.allSatisfy { ja.contains($0) })
        let zh = InsightService.groundedNudgeQuoteCandidates(in: Self.sickDay["zh"]!)
        #expect(zh.contains("比平时晚很多，十点才醒。"))
    }

    @Test(arguments: ["de", "es", "fr", "it", "pt", "ru", "ja", "ko", "zh"])
    func nudgeComposesFixedTextAroundThePickedQuote(code: String) throws {
        let entry = Entry(text: Self.sickDay[code]!, mood: "Drained")
        let localized = try #require(InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: []))
        guard case .grammarConstrained(let message, let grammar) = localized.plan else { Issue.record("expected grammar plan for \(code)"); return }
        let loc = try #require(InsightService.groundedLocales[code])
        #expect(message.hasPrefix(loc.pickNudge.replacingOccurrences(of: "{mood}", with: loc.moodWord[.tired]!)))
        #expect(grammar.hasPrefix("root ::= \""))
        let quote = InsightService.groundedNudgeQuoteCandidates(in: entry.text)[0]
        let composed = try #require(try localized.validator?(quote))
        #expect(composed.hasPrefix(loc.youWrote + loc.open + quote + loc.close))
        #expect(loc.feel[.tired]!.contains { composed.hasSuffix($0) })
        // Outside the app only the fixed line remains — never the user's sentence.
        let outside = InsightService.nudgeTextForOutsideApp(composed)
        #expect(loc.feel[.tired]!.contains(outside), "\(code): \(outside)")
        #expect(throws: InsightError.self) { try localized.validator?("Invented sentence that is not in the entry.") }
    }

    @Test func englishEntriesDontTakeTheLocalizedPath() {
        let entry = Entry(text: "Barely slept, got back from a late concert and my stomach was bad all night.", mood: "Drained")
        #expect(InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: []) == nil)
        #expect(InsightService.localizedGroundedDigest(weekEntries: [entry], languageSource: [entry]) == nil)
        #expect(InsightService.localizedGroundedAsk(question: "How did I sleep?", pool: [entry]) == nil)
    }

    @Test func germanDigestComposesSixLocalizedSectionsAndAvoidsARepeatedQuote() throws {
        let hard = Entry(text: "Die Präsentation beim Kunden wurde schon wieder auf Donnerstag verschoben. Ich fühle mich mit allem im Rückstand.", mood: "Overwhelmed")
        let good = Entry(text: "Bin nach der Arbeit mit dem Hund am See spazieren gegangen. Zum ersten Mal diese Woche fühlte ich mich leicht.", mood: "Peaceful")
        good.createdAt = hard.createdAt.addingTimeInterval(-86_400)
        let week = [hard, good]
        let localized = try #require(InsightService.localizedGroundedDigest(weekEntries: week, languageSource: week))
        let hardQuote = "Die Präsentation beim Kunden wurde schon wieder auf Donnerstag verschoben."
        let goodQuote = "Zum ersten Mal diese Woche fühlte ich mich leicht."
        let text = try #require(try localized.validator?("\(hardQuote)\n\(goodQuote)\n\(hardQuote)"))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 6)
        let labels = InsightService.weeklyDigestSectionLabels.map { $0["de"]! }
        for (line, label) in zip(lines, labels) { #expect(line.hasPrefix(label + ": ")) }
        #expect(lines[1].contains("„\(hardQuote)“"))
        #expect(!lines[3].contains(hardQuote), "a repeated quote is swapped for another hard sentence")
        #expect(lines[0] == labels[0] + ": Eine Woche mit Höhen und Tiefen.")
        #expect(throws: InsightError.self) { try localized.validator?("\(goodQuote)\n\(goodQuote)") }
    }

    @Test func spanishAskListsQuotesUnderLocalizedHeadingWithDates() throws {
        let entry = Entry(text: Self.sickDay["es"]!, mood: "Drained")
        let localized = try #require(InsightService.localizedGroundedAsk(question: "¿Cómo he dormido últimamente?", pool: [entry]))
        let quote = InsightService.groundedNudgeQuoteCandidates(in: entry.text)[0]
        let text = try #require(try localized.validator?(quote))
        #expect(text.hasPrefix("Lo más cercano que has escrito:\n"))
        #expect(text.contains("“\(quote)”"))
    }

    @Test(arguments: ["de", "ja"])
    func localizedNudgeSurvivesTheRealPipeline(code: String) async throws {
        let entry = Entry(text: Self.sickDay[code]!, mood: "Drained")
        let quote = InsightService.groundedNudgeQuoteCandidates(in: entry.text)[0]
        var calls = 0
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return (quote, .gemma) }
        defer { LocalLLMService.generateInterceptForTesting = nil }
        let (text, engine, _) = try await InsightService.generateNudge(entries: [entry])
        let loc = try #require(InsightService.groundedLocales[code])
        #expect(text.hasPrefix(loc.youWrote + loc.open + quote + loc.close), "\(code): \(text)")
        #expect(engine == .gemma)
        #expect(calls == 1, "grounding checks must accept a composed localized nudge on the first try")
    }

    @Test func japaneseDigestSurvivesTheRealPipeline() async throws {
        let hard = Entry(text: "クライアントへのプレゼンがまた木曜日に延期された。何もかも遅れている気がする。", mood: "Overwhelmed")
        let good = Entry(text: "仕事のあと犬と湖のそばを散歩した。今週はじめて気持ちが軽くなった。", mood: "Peaceful")
        good.createdAt = hard.createdAt.addingTimeInterval(-3_600)
        let reply = "クライアントへのプレゼンがまた木曜日に延期された。\n今週はじめて気持ちが軽くなった。\n何もかも遅れている気がする。"
        var calls = 0
        LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return (reply, .gemma) }
        defer { LocalLLMService.generateInterceptForTesting = nil }
        let (text, _) = try await InsightService.generateWeeklyDigest(weekEntries: [hard, good], allEntries: [hard, good])
        #expect(calls == 1)
        #expect(text.hasPrefix(InsightService.weeklyDigestSectionLabels[0]["ja"]! + ": "), "\(text)")
        #expect(text.contains("「今週はじめて気持ちが軽くなった。」"))
    }

    // Saved-insight passes (CachedInsightRepair, UngroundedInsightCleanup, the Diagnostics audit)
    // must leave grammar-path content alone.
    @Test func everyGrammarShapeIsRecognizedAndOrdinaryTextIsNot() throws {
        let entry = Entry(text: Self.sickDay["ja"]!, mood: "Drained")
        let jaNudge = try #require(try InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: [])?
            .validator?(InsightService.groundedNudgeQuoteCandidates(in: entry.text)[0]))
        let shapes = [
            #"You wrote, "I felt awful all day." You seem worn down."#,
            "THIS WEEK'S THEME: A week of x.\nWHAT'S BUILDING: You wrote, \"Felt light.\" That sounds good.",
            "YOUR MONTH IN ONE IMAGE: A lamp.\nWHAT YOU'RE BECOMING: You wrote, \"Felt light.\" You seem to be becoming someone who rests.",
            InsightService.groundedAskPrefix + #"On 27 Sep, you wrote, "Barely slept.""#,
            jaNudge,
            "今週のテーマ: つらい一週間。\nあなたのエネルギー: いちばん大変そうだったのは、こう書いたときです：「ほとんど眠れなかった。」",
            "Am nächsten kommt, was du geschrieben hast:\n27. Sept. – „Kaum geschlafen.“",
        ]
        for shape in shapes { #expect(InsightService.isGrammarGrounded(shape), "\(shape)") }
        #expect(!InsightService.isGrammarGrounded("You sat with a friend on the balcony after a long night."))
        #expect(!InsightService.isGrammarGrounded(InsightService.dailyNudgeUngroundedFallback))
    }

    @Test func retroactiveAuditNeverFlagsAGrammarPathJapaneseNudge() throws {
        let entry = Entry(text: Self.sickDay["ja"]!, mood: "Drained")
        let content = try #require(try InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: [])?
            .validator?(InsightService.groundedNudgeQuoteCandidates(in: entry.text)[0]))
        let insight = Insight(type: .dailyNudge, content: content, periodIdentifier: DateHelpers.dayIdentifier(for: entry.createdAt))
        insight.generatedAt = entry.createdAt.addingTimeInterval(60)
        #expect(InsightService.ungroundedDailyNudges(among: [insight], allEntries: [entry]).isEmpty)
    }
}
