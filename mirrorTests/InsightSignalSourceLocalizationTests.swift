import Testing
import Foundation
@testable import mirror

// "How this was generated" built its labels, values and notes as plain English `String`s, so the
// sheet stayed English in every language (backlog B). `resolve` now looks each one up in the
// catalog; these runs pass a language's .lproj bundle, as FallbackLocalizationTests does.
@MainActor
@Suite("How this was generated, localized")
struct InsightSignalSourceLocalizationTests {

    private let asOf = Calendar.current.startOfDay(for: Date()).addingTimeInterval(20 * 3_600)

    private static func lproj(_ language: String) -> Bundle? {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private func entry(_ text: String, _ mood: String, hoursBefore: Double) -> Entry {
        let e = Entry(text: text, mood: mood)
        e.createdAt = asOf.addingTimeInterval(-hoursBefore * 3_600)
        return e
    }

    private func insight(_ type: InsightType, _ content: String, _ engine: LLMEngine, question: String? = nil) -> Insight {
        let i = Insight(type: type, content: content, periodIdentifier: "test", question: question, generatedByEngine: engine)
        i.generatedAt = asOf
        return i
    }

    private var entries: [Entry] {
        [
            entry("Repainted the hallway bookshelf and left it to dry overnight.", "Content", hoursBefore: 2),
            entry("Finished the jigsaw puzzle with Leo after dinner and framed the corner piece.", "Hopeful", hoursBefore: 6),
            entry("Slept badly after the late train home, the carriage heater was stuck on high.", "Drained", hoursBefore: 26),
        ] + (2...6).map { entry("An older entry about an ordinary working day number \($0).", "Content", hoursBefore: Double($0) * 24 + 3) }
    }

    /// One insight per sheet shape: grounded nudge (note), free-prose nudge (context), grounded
    /// digest ("none sent"), free-prose digest ("carried in"), monthly (aggregates note), Ask.
    private var insights: [Insight] {
        [
            insight(.dailyNudge, #"You wrote, "Finished the jigsaw puzzle with Leo after dinner and framed the corner piece." That sounds like a good day."#, .gemma),
            insight(.dailyNudge, "The evening at the flat sounds like it gave you room to breathe.", .foundationModels),
            insight(.weeklyDigest, #"THIS WEEK'S THEME: A heavy week. YOUR ENERGY: x WHAT'S BUILDING: You wrote, "Repainted the hallway bookshelf and left it to dry overnight." WATCH OUT FOR: x"#, .gemma),
            insight(.weeklyDigest, "THIS WEEK'S THEME: The bookshelf kept drying.", .foundationModels),
            insight(.monthlyReport, "THE IMAGE: A month of small repairs.", .foundationModels),
            insight(.askResponse, "You mentioned the bookshelf twice.", .foundationModels, question: "bookshelf"),
        ]
    }

    @Test func englishBundleKeepsTheEnglishText() throws {
        let en = try #require(Self.lproj("en"))
        for i in insights {
            let main = InsightSignalSource.resolve(insight: i, entries: entries, engineLabel: "X")
            let viaEnglish = InsightSignalSource.resolve(insight: i, entries: entries, engineLabel: "X", bundle: en)
            #expect(main.rows.map(\.label) == viaEnglish.rows.map(\.label))
            #expect(main.rows.map(\.value) == viaEnglish.rows.map(\.value))
            #expect(main.note == viaEnglish.note)
        }
        let r = InsightSignalSource.resolve(insight: insights[1], entries: entries, engineLabel: "X", bundle: en)
        #expect(r.rows.first { $0.label == "CONTEXT" }?.value.hasSuffix("summarized · 4 quoted") == true)
    }

    @Test(arguments: ["de", "ru", "ja"])
    func sheetHasNoEnglishLeft(_ language: String) throws {
        let en = try #require(Self.lproj("en"))
        let other = try #require(Self.lproj(language))
        for i in insights {
            let english = InsightSignalSource.resolve(insight: i, entries: entries, engineLabel: "X", bundle: en)
            let translated = InsightSignalSource.resolve(insight: i, entries: entries, engineLabel: "X", bundle: other)
            #expect(english.rows.count == translated.rows.count)
            for (e, t) in zip(english.rows, translated.rows) {
                #expect(e.label != t.label, "\(language) \(i.type): label \(e.label) is still English")
                // Not the sheet's own text: the engine label is passed in, the stamp is a date, the
                // question is the user's, and mood names follow the app's language already.
                if !["ENGINE", "GENERATED", "QUESTION", "MOOD READ", "MOOD ARC"].contains(e.label) {
                    #expect(e.value != t.value, "\(language) \(i.type): \(e.label) value \(e.value) is still English")
                }
            }
            #expect((english.note == nil) == (translated.note == nil))
            if let note = english.note { #expect(note != translated.note, "\(language) \(i.type): note is still English") }
        }
    }
}
