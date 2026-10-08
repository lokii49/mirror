import Testing
import Foundation
@testable import mirror

// Ask's retrieval switch (2026-10-08): EmbeddingGemma when installed and indexed, keyword search
// otherwise. Synthetic entries only.
@MainActor
struct SemanticAskRetrievalTests {

    private func journal(_ texts: [String]) -> [Entry] {
        texts.map { Entry(text: $0) }
    }

    @Test func withoutTheModelAskUsesKeywordSearch() async throws {
        try #require(!FileManager.default.fileExists(atPath: SemanticSearchService.modelFileURL().path),
                     "this test assumes the simulator has no downloaded embedding model")
        let entries = journal(["Bus was late.", "Went to the gym before work.", "Laundry day."])
        let found = await InsightService.askRelevantEntries(question: "When did I go to the gym?", newestFirst: entries)
        #expect(found.map(\.text) == SearchService.search(query: "When did I go to the gym?", in: entries, limit: 10).map(\.text))
    }

    @Test func embeddedTextIsTrimmedAndCapped() {
        let long = "  " + String(repeating: "a", count: SemanticSearchService.maxEmbeddedCharacters + 50) + "  "
        #expect(SemanticSearchService.embeddedText(long).count == SemanticSearchService.maxEmbeddedCharacters)
        #expect(SemanticSearchService.embeddedText("  walk  ") == "walk")
    }

    @Test func editedTextChangesTheHash() {
        #expect(SemanticSearchService.textHash("Went to the gym.") != SemanticSearchService.textHash("Went to the gym!"))
        #expect(SemanticSearchService.textHash("same") == SemanticSearchService.textHash("same"))
    }

    @Test func modelIsPinnedToTheMeasuredFile() {
        #expect(SemanticSearchService.modelSHA256.count == 64)
        #expect(SemanticSearchService.modelURL.lastPathComponent == SemanticSearchService.modelFileName)
        #expect(SemanticSearchService.modelURL.scheme == "https")
    }

    /// The download is opt-in: without an explicit yes (Ask's offer card or Settings), asking does
    /// nothing on the network.
    @Test func noDownloadStartsWithoutConsent() async throws {
        try #require(!SemanticSearchService.isModelOnDisk, "assumes no downloaded model on this simulator")
        let saved = SemanticSearchService.consent
        defer { SemanticSearchService.consent = saved }
        for answer in [SemanticSearchService.Consent.undecided, .declined] {
            SemanticSearchService.consent = answer
            await SemanticSearchService.shared.ensureModelDownloadStarted()
            #expect(await SemanticSearchService.shared.modelState == .absent, "\(answer)")
        }
    }

    @Test func consentRoundTripsAndDefaultsToUndecided() {
        let saved = UserDefaults.standard.string(forKey: SemanticSearchService.consentKey)
        defer { UserDefaults.standard.set(saved, forKey: SemanticSearchService.consentKey) }
        UserDefaults.standard.removeObject(forKey: SemanticSearchService.consentKey)
        #expect(SemanticSearchService.consent == .undecided)
        SemanticSearchService.consent = .declined
        #expect(SemanticSearchService.consent == .declined)
        SemanticSearchService.consent = .accepted
        #expect(SemanticSearchService.consent == .accepted)
    }
}
