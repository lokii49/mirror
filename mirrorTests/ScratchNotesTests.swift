import Foundation
import SwiftData
import Testing
@testable import mirror

/// Quick notes into Scratch (sheet, Siri, Control Center). Synthetic text only.
@Suite("Scratch notes")
@MainActor
struct ScratchNotesTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func entries(_ context: ModelContext) -> [Entry] {
        (try? context.fetch(FetchDescriptor<Entry>())) ?? []
    }

    @Test func firstNoteCreatesScratchKeptOut() throws {
        let context = try context()
        let entry = try ScratchNotes.save("  Milk, eggs, bread.  ", in: context)
        let collections = JournalOrganizationStore.collections(in: context)
        #expect(collections.count == 1)
        let scratch = try #require(collections.first)
        #expect(scratch.payload?.name == JournalOrganizationStore.scratchName)
        #expect(scratch.payload?.keepsOutOfInsights == true)
        #expect(entry.collectionID == scratch.id)
        #expect(entry.text == "Milk, eggs, bread.")
        #expect(!InsightScope(context: context).includes(entry))
    }

    @Test func laterNotesReuseTheSameCollection() throws {
        let context = try context()
        let a = try ScratchNotes.save("Call the plumber.", in: context)
        let b = try ScratchNotes.save("Gate code 4412.", in: context)
        #expect(a.collectionID == b.collectionID)
        #expect(JournalOrganizationStore.collections(in: context).count == 1)
        #expect(entries(context).count == 2)
    }

    @Test func blankTextSavesNothing() throws {
        let context = try context()
        #expect(throws: ScratchNotes.SaveError.empty) { try ScratchNotes.save(" \n\t ", in: context) }
        #expect(entries(context).isEmpty)
        #expect(JournalOrganizationStore.collections(in: context).isEmpty)
    }

    @Test func aRenamedKeptOutCollectionIsUsedInsteadOfANewScratch() throws {
        let context = try context()
        let scratch = try JournalOrganizationStore.addScratchCollection(in: context)
        try JournalOrganizationStore.rename(scratch, to: "Lists", in: context)
        let entry = try ScratchNotes.save("Batteries.", in: context)
        #expect(entry.collectionID == scratch.id)
        #expect(JournalOrganizationStore.collections(in: context).count == 1)
    }

    @Test func scratchWithKeepingOutTurnedOffIsUsedAndLeftAsIs() throws {
        let context = try context()
        let scratch = try JournalOrganizationStore.addScratchCollection(in: context)
        try JournalOrganizationStore.setKeepsOutOfInsights(scratch, false, in: context)
        let entry = try ScratchNotes.save("Batteries.", in: context)
        #expect(entry.collectionID == scratch.id)
        #expect(scratch.payload?.keepsOutOfInsights == false, "their choice stays")
    }

    @Test func aKeptOutScratchWinsOverAnotherKeptOutCollection() throws {
        let context = try context()
        let other = try JournalOrganizationStore.createCollection(name: "Work notes", keepOutOfInsights: true, in: context)
        let scratch = try JournalOrganizationStore.createCollection(name: JournalOrganizationStore.scratchName, keepOutOfInsights: true, in: context)
        #expect(try ScratchNotes.target(in: context).id == scratch.id)
        #expect(other.id != scratch.id)
    }

    @Test func scratchDraftHasItsOwnSlot() {
        let slot = WriteDraftStore.Slot.scratchNote
        #expect(slot.isNewEntry, "an emptied quick note clears its draft")
        #expect(slot.key != WriteDraftStore.Slot.newEntry.key)
        #expect(slot.key != WriteDraftStore.Slot.newEntryWindow.key)
    }

    @Test func scratchDraftRoundTripsAndClears() {
        let defaults = UserDefaults(suiteName: "ScratchNotesTests.\(UUID().uuidString)")!
        let crypto = WriteDraftStore.Crypto(seal: { $0 }, open: { $0 }, openLegacyString: { $0 }, sealString: { $0 })
        var draft = WriteDraftStore.Payload()
        draft.text = "Gate code 4412."
        #expect(WriteDraftStore.save(draft, slot: .scratchNote, defaults: defaults, crypto: crypto))
        #expect(WriteDraftStore.load(slot: .scratchNote, defaults: defaults, crypto: crypto) == .payload(draft))
        #expect(WriteDraftStore.load(slot: .newEntry, defaults: defaults, crypto: crypto) == .none, "Write's draft untouched")
        #expect(WriteDraftStore.save(WriteDraftStore.Payload(), slot: .scratchNote, defaults: defaults, crypto: crypto))
        #expect(defaults.data(forKey: WriteDraftStore.Slot.scratchNote.key) == nil)
    }
}
