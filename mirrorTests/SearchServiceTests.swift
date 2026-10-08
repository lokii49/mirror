import Testing
import Foundation
@testable import mirror

// Ask's retrieval (SearchService.search), reworked 2026-10-08 after tools/llmrig/retrieval:
// whole-word stems, IDF ranking, generic keywords dropped. Synthetic entries only.
@MainActor
struct SearchServiceTests {

    /// Entries newest first, as both call sites pass them.
    private func journal(_ texts: [String]) -> [Entry] {
        texts.map { Entry(text: $0) }
    }

    private func filler(_ count: Int, _ text: (Int) -> String) -> [String] {
        (0..<count).map(text)
    }

    @Test func pluralQuestionFindsSingularEntry() {
        let entries = journal(["Repainted the fence.", "Third migraine this week, lay in the dark.", "Bus was late."])
        let found = SearchService.search(query: "What did I write about migraines?", in: entries, limit: 10)
        #expect(found.first?.text == "Third migraine this week, lay in the dark.")
    }

    @Test func keywordInsideAnotherWordNoLongerMatches() {
        let entries = journal(["Vacuumed the carpet and the stairs.", "Took my pet hamster to the vet."])
        let found = SearchService.search(query: "How is my pet?", in: entries, limit: 10)
        #expect(found.map(\.text) == ["Took my pet hamster to the vet."])
    }

    @Test func genericWordsDoNotBuryTheTopicInALargeJournal() {
        // "ich" and "war" are in every entry (SearchService's stopwords are English); only the
        // oldest entry mentions the gym.
        let texts = filler(24) { "Heute war ich im Büro, Tag \($0)." } + ["Heute war ich im Fitnessstudio."]
        let found = SearchService.search(query: "Wann war ich im Fitnessstudio?", in: journal(texts), limit: 10)
        #expect(found.first?.text == "Heute war ich im Fitnessstudio.")
    }

    @Test func smallJournalKeepsTopicWordsAboveTheGenericShare() {
        // 2 of 5 entries is 40%, above the generic share; a journal this small must still match.
        let entries = journal(["Bus was late.", "Gym before work, legs.", "Laundry day.", "Skipped the gym again.", "Fog all morning."])
        let found = SearchService.search(query: "When did I go to the gym?", in: entries, limit: 10)
        #expect(Set(found.map(\.text)) == ["Gym before work, legs.", "Skipped the gym again."])
    }

    @Test func entryWithMoreRareKeywordsRanksFirst() {
        let entries = journal(["Called Mom about the holidays.", "Mom and I argued about the holiday flights.", "Bus was late."])
        let found = SearchService.search(query: "Did Mom mention holiday flights?", in: entries, limit: 10)
        #expect(found.first?.text == "Mom and I argued about the holiday flights.")
        #expect(found.count == 2)
    }

    @Test func tagsAreSearchedAsWords() {
        let entry = Entry(text: "Ear drops twice a day.")
        entry.tags = ["Biscuit"]
        let found = SearchService.search(query: "How is Biscuit?", in: journal(["Bus was late."]) + [entry], limit: 10)
        #expect(found.first === entry)
    }

    @Test func noMatchFallsBackToTheFirstEntries() {
        let entries = journal(["One.", "Two.", "Three."])
        let found = SearchService.search(query: "What about the lighthouse?", in: entries, limit: 2)
        #expect(found.map(\.text) == ["One.", "Two."])
    }

    @Test func stemsMeetAcrossTrailingE() {
        #expect(SearchService.searchStem("migraines") == SearchService.searchStem("migraine"))
        #expect(SearchService.searchStem("argued") == SearchService.searchStem("argue"))
        #expect(SearchService.searchStem("phones") == SearchService.searchStem("phone"))
    }

    @Test(arguments: ["Called Mom's sister.", "Called Mom’s sister."])
    func possessiveStillMatches(_ text: String) {
        let found = SearchService.search(query: "How is Mom?", in: journal(["Bus was late.", text]), limit: 10)
        #expect(found.first?.text == text)
    }

    @Test func curlyApostropheInQueryStillMatches() {
        let found = SearchService.search(query: "What did Mom’s doctor say?", in: journal(["Bus was late.", "Mom's doctor called back."]), limit: 10)
        #expect(found.first?.text == "Mom's doctor called back.")
    }

    @Test func frenchElisionStillMatches() {
        let found = SearchService.search(query: "Comment s'est passé l'entretien ?", in: journal(["Le bus était en retard.", "Deuxième entretien au studio."]), limit: 10)
        #expect(found.first?.text == "Deuxième entretien au studio.")
        let elided = SearchService.search(query: "Et l'entretien ?", in: journal(["Le bus était en retard.", "J'ai raté l'entretien."]), limit: 10)
        #expect(elided.first?.text == "J'ai raté l'entretien.")
    }

    @Test func spanishInvertedQuestionMarkIsNotPartOfTheWord() {
        let found = SearchService.search(query: "¿Dinero?", in: journal(["Llovió.", "Estoy preocupada por el dinero."]), limit: 10)
        #expect(found.first?.text == "Estoy preocupada por el dinero.")
    }

    @Test func tiesKeepNewestFirstOrder() {
        let entries = journal(["Gym, upper body.", "Bus was late.", "Gym, legs."])
        let found = SearchService.search(query: "gym", in: entries, limit: 10)
        #expect(found.map(\.text) == ["Gym, upper body.", "Gym, legs."])
    }

    /// "How this was generated" runs this on the main actor; a long journal must stay cheap.
    @Test func twoThousandEntriesSearchQuickly() {
        let texts = filler(2_000) { "Day \($0): bus was late, did laundry, called about the boiler, quiet evening with tea." }
        let entries = journal(texts + ["Third migraine this week, lay in the dark."])
        let clock = ContinuousClock()
        var found: [Entry] = []
        let elapsed = clock.measure {
            found = SearchService.search(query: "What did I write about migraines?", in: entries, limit: 10)
        }
        #expect(found.first?.text == "Third migraine this week, lay in the dark.")
        print("SearchService 2001 entries: \(elapsed)")
        #expect(elapsed < .seconds(1))
    }
}
