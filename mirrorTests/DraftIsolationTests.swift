import Testing
@testable import mirror

@Suite("Scratch journal draft isolation")
struct DraftIsolationTests {
    @Test @MainActor func scratchJournalsCannotAccessPersistentDrafts() {
        #if DEBUG
        #expect(!WriteView.usesPersistentDraftStorage(arguments: ["MirrorNotes", "--macSnapshot"]))
        #expect(!WriteView.usesPersistentDraftStorage(arguments: ["MirrorNotes", "--perfSeed=5000"]))
        // Ordinary UI editor tests still need to exercise real draft persistence.
        #expect(WriteView.usesPersistentDraftStorage(arguments: ["MirrorNotes", "--uitesting"]))
        #expect(WriteView.usesPersistentDraftStorage(arguments: ["MirrorNotes"]))
        #endif
    }
}
