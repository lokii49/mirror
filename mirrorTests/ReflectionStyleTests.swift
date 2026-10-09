import Testing
import Foundation
@testable import mirror

/// Reflection styles change only the fixed wording after the verified quote, at display
/// time. Synthetic text only.
@Suite("Reflection style")
struct ReflectionStyleTests {
    private let exam = "Exam is on Friday and I've only covered half the syllabus. Studied in the library till nine. My roommate offered to quiz me tomorrow night."
    private let mainQuote = "Exam is on Friday and I've only covered half the syllabus."
    private let stored = "You wrote, \"Exam is on Friday and I've only covered half the syllabus.\" You seem anxious about the exam."

    @MainActor private func shown(_ style: ReflectionStyle, content: String? = nil, entries: [Entry]? = nil) -> (text: String, parts: InsightService.GroundedNudgeParts?) {
        let entry = Entry(text: exam, mood: "Anxious")
        return InsightService.reflectionForDisplay(content ?? stored, entries: entries ?? [entry],
                                                   generatedAt: Date().addingTimeInterval(60), style: style)
    }

    @Test @MainActor func gentleIsTodaysShape() {
        let gentle = shown(.gentle)
        let entry = Entry(text: exam, mood: "Anxious")
        let base = InsightService.reflectionWithAlsoQuote(stored, entries: [entry], generatedAt: Date().addingTimeInterval(60))
        #expect(gentle.text == base.text)
    }

    @Test @MainActor func quietKeepsOnlyTheQuoteAndTheSecondQuote() {
        let quiet = shown(.quiet)
        #expect(quiet.text == "You wrote, \"\(mainQuote)\" You also wrote, \"My roommate offered to quiz me tomorrow night.\"")
        #expect(!quiet.text.contains("anxious"))
        #expect(quiet.parts?.quote == mainQuote)
    }

    @Test @MainActor func quietDropsAHardDayTip() throws {
        let tip = try #require(InsightService.groundedNudgeTips[.stressed]?.first)
        let quiet = shown(.quiet, content: stored + " " + tip)
        #expect(!quiet.text.contains(tip))
        #expect(quiet.text.hasPrefix("You wrote, \"\(mainQuote)\""))
    }

    @Test @MainActor func curiousAsksAboutAnotherPartAndKeepsTheQuote() throws {
        let curious = shown(.curious)
        #expect(curious.text.hasPrefix("You wrote, \"\(mainQuote)\" "))
        let question = String(curious.text.dropFirst("You wrote, \"\(mainQuote)\" ".count))
        #expect(question.hasSuffix("?"))
        // The question never repeats the quote itself.
        #expect(!question.contains("covered half the syllabus"))
        #expect(!curious.text.contains("anxious"))
    }

    @Test @MainActor func fallsBackToGentleWhenTheStyleCannotBeBuilt() {
        // Not a grounded reflection (honest card): unchanged for every style.
        let card = "MirrorNotes couldn't find a sentence to reflect on today."
        for style in ReflectionStyle.allCases {
            #expect(shown(style, content: card).text == card)
        }
        // A single-sentence entry has nothing else to ask about: Curious falls back.
        let single = Entry(text: "Studied in the library till nine.", mood: "Content")
        let content = "You wrote, \"Studied in the library till nine.\" That sounds like a long day."
        let curious = shown(.curious, content: content, entries: [single])
        #expect(curious.text == content)
    }

    @Test func storedValueDefaultsToGentle() {
        #expect(ReflectionStyle(storedValue: nil) == .gentle)
        #expect(ReflectionStyle(storedValue: "nonsense") == .gentle)
        #expect(ReflectionStyle(storedValue: "quiet") == .quiet)
    }

    /// Localized reflections use the locale's own quote marks (fr « », ja 「」). Quiet and Curious
    /// must keep the verified quote with those marks and never add English text.
    @Test @MainActor func localizedStylesKeepTheLocalesQuoteMarks() throws {
        let cases: [(code: String, text: String, quote: String)] = [
            ("fr", "L'examen est vendredi et je n'ai revu que la moitié du programme. J'ai étudié à la bibliothèque jusqu'à neuf heures. Mon colocataire a proposé de m'interroger demain soir.",
             "L'examen est vendredi et je n'ai revu que la moitié du programme."),
            ("ja", "試験は金曜日なのに、範囲の半分しか終わっていない。図書館で九時まで勉強した。ルームメイトが明日の夜に問題を出してくれると言った。",
             "試験は金曜日なのに、範囲の半分しか終わっていない。"),
        ]
        for c in cases {
            let loc = try #require(InsightService.groundedLocales[c.code])
            let head = loc.youWrote + loc.open + c.quote + loc.close
            let content = head + loc.joiner + "fixed line"
            let entry = Entry(text: c.text, mood: "Anxious")
            let when = Date().addingTimeInterval(60)

            let quiet = InsightService.reflectionForDisplay(content, entries: [entry], generatedAt: when, style: .quiet)
            #expect(quiet.text == head, "\(c.code): Quiet is the head only, got: \(quiet.text)")
            #expect(quiet.parts?.quote == c.quote)

            let curious = InsightService.reflectionForDisplay(content, entries: [entry], generatedAt: when, style: .curious)
            #expect(curious.text.hasPrefix(head), "\(c.code): Curious keeps the head")
            #expect(!curious.text.contains("fixed line"))
            if curious.text != content {
                let question = String(curious.text.dropFirst(head.count)).trimmingCharacters(in: .whitespaces)
                #expect(question.contains(loc.open), "\(c.code): the question quotes with the locale's marks, got: \(question)")
                #expect(!question.contains(c.quote))
            }
        }
    }
}
