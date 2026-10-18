import Testing
import Foundation
@testable import mirror

// Backlog A15: Russian on a device with Foundation Models runs only on Gemma. Without Gemma
// downloaded the generation threw `modelMissing`, the runner swallowed it, and the card said
// "generates tonight" forever with no download offer. `nudgeNeedsGemma` lets the card show the
// model-download card instead. Foundation Models' language list is injected, so this runs on a
// simulator. Synthetic text only.
@MainActor
struct NudgeNeedsGemmaTests {
    private let fmLanguages: (String) -> Bool = { ["de", "es", "fr", "it", "pt", "ja", "ko", "zh"].contains($0) }

    private func entries(_ texts: [String]) -> [Entry] {
        let now = Date()
        return texts.enumerated().map { i, text in
            let e = Entry(text: text, mood: "Content")
            e.createdAt = now.addingTimeInterval(Double(-i) * 600)
            return e
        }
    }

    @Test func russianEntries_needGemma() {
        let russian = entries([
            "Сегодня я долго гулял по парку и думал о работе и о планах на выходные.",
            "Вечером мы с другом пили чай и разговаривали о книгах, которые читали летом.",
            "Утром было холодно, но я всё равно пошёл на пробежку вдоль реки.",
        ])
        #expect(InsightService.nudgeNeedsGemma(entries: russian, foundationModelsSupports: fmLanguages))
    }

    @Test func englishAndGermanEntries_doNotNeedGemma() {
        let english = entries([
            "I walked through the park for a long time today and thought about work.",
            "In the evening a friend and I drank tea and talked about the books we read.",
            "It was cold this morning, but I still went for a run along the river.",
        ])
        let german = entries([
            "Heute bin ich lange durch den Park gelaufen und habe über die Arbeit nachgedacht.",
            "Am Abend haben ein Freund und ich Tee getrunken und über Bücher gesprochen.",
            "Heute Morgen war es kalt, aber ich bin trotzdem am Fluss entlang gelaufen.",
        ])
        #expect(!InsightService.nudgeNeedsGemma(entries: english, foundationModelsSupports: fmLanguages))
        #expect(!InsightService.nudgeNeedsGemma(entries: german, foundationModelsSupports: fmLanguages))
    }

    /// Too short to detect: the device language decides, as in `generateNudge`.
    @Test func shortEntriesOnARussianDevice_needGemma() {
        let short = entries(["Долгий день.", "Чай с другом.", "Пробежка."])
        let needs = InsightService.$deviceLanguageForTesting.withValue("ru") {
            InsightService.nudgeNeedsGemma(entries: short, foundationModelsSupports: fmLanguages)
        }
        #expect(needs)
    }

    @Test func noReadableEntries_doNotNeedGemma() {
        #expect(!InsightService.nudgeNeedsGemma(entries: [], foundationModelsSupports: fmLanguages))
    }
}

extension NudgeNeedsGemmaTests {
    /// Only the newest readable entries decide (the 23 the reflection reads): older ones in
    /// another language don't change the answer.
    @Test func olderEntriesBeyondTheContextDontCount() {
        let now = Date()
        var entries: [Entry] = (0..<25).map { i in
            let e = Entry(text: "A synthetic English note about the walk home number \(i).")
            e.createdAt = now.addingTimeInterval(Double(-i) * 3_600)
            return e
        }
        let old = Entry(text: "Сегодня был длинный день на работе, и вечером я долго гулял по парку.")
        old.createdAt = now.addingTimeInterval(-60 * 86_400)
        entries.append(old)
        #expect(!InsightService.nudgeNeedsGemma(entries: entries, foundationModelsSupports: { $0 != "ru" }))
    }
}
