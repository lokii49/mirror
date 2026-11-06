import Foundation
import SwiftData
import Testing
@testable import mirror

/// Collections kept out of reflections and insights (Scratch). Synthetic text only.
@Suite("Kept-out collections")
@MainActor
struct InsightScopeTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func entry(in collection: UUID?, _ text: String, context: ModelContext) -> Entry {
        let entry = Entry(text: text)
        entry.collectionID = collection
        context.insert(entry)
        return entry
    }

    @Test func payloadsWrittenBeforeTheFlagStillDecode() throws {
        let old = #"{"version":1,"name":"Work","icon":"folder","colorIndex":2}"#
        let payload = try JSONDecoder().decode(JournalCollection.Payload.self, from: Data(old.utf8))
        #expect(payload.name == "Work")
        #expect(payload.keepOutOfInsights == nil)
        #expect(!payload.keepsOutOfInsights)

        let new = #"{"version":1,"name":"Scratch","icon":"note.text","colorIndex":0,"keepOutOfInsights":true}"#
        #expect(try JSONDecoder().decode(JournalCollection.Payload.self, from: Data(new.utf8)).keepsOutOfInsights)
    }

    @Test func aPayloadWithoutTheFlagDoesNotWriteTheKey() throws {
        // Older versions re-encode what they decode; leaving the key out when off keeps the
        // payload identical to theirs.
        let data = try JSONEncoder().encode(JournalCollection.Payload(name: "Work"))
        #expect(!String(decoding: data, as: UTF8.self).contains("keepOutOfInsights"))
    }

    @Test func archiveRecordsFromBeforeTheFlagStillDecode() throws {
        let id = UUID()
        let old = #"{"id":"\#(id.uuidString)","name":"Work","icon":"folder","colorIndex":0}"#
        let record = try JSONDecoder().decode(ArchivePackage.Manifest.CollectionRecord.self, from: Data(old.utf8))
        #expect(record.keepOutOfInsights == nil)
    }

    @Test func keptOutEntriesAreFilteredAndOthersStay() throws {
        let context = try context()
        let work = try JournalOrganizationStore.createCollection(name: "Work", in: context)
        let scratch = try JournalOrganizationStore.addScratchCollection(in: context)
        let unfiled = entry(in: nil, "A long walk after the meeting.", context: context)
        let filed = entry(in: work.id, "Planning the week ahead.", context: context)
        let note = entry(in: scratch.id, "Milk, eggs, bread.", context: context)

        let scope = InsightScope(context: context)
        #expect(scope.excludedCollectionIDs == [scratch.id])
        #expect(scope.filter([unfiled, filed, note]).map(\.id) == [unfiled.id, filed.id])
        #expect(!scope.includes(note))
        // An entry whose collection is gone (deleted elsewhere) reads as Unfiled: included.
        #expect(scope.includes(collectionID: UUID()))
    }

    @Test func nothingKeptOutReturnsTheSameEntries() throws {
        let context = try context()
        _ = try JournalOrganizationStore.createCollection(name: "Work", in: context)
        let entries = [entry(in: nil, "One.", context: context), entry(in: nil, "Two.", context: context)]
        let scope = InsightScope(context: context)
        #expect(scope.excludesNothing)
        #expect(scope.filter(entries).map(\.id) == entries.map(\.id))
    }

    @Test func togglingTheFlagMovesEntriesInAndOut() throws {
        let context = try context()
        let work = try JournalOrganizationStore.createCollection(name: "Work", in: context)
        let filed = entry(in: work.id, "Planning the week ahead.", context: context)
        try JournalOrganizationStore.setKeepsOutOfInsights(work, true, in: context)
        #expect(work.payload?.keepsOutOfInsights == true)
        #expect(work.payload?.name == "Work")
        #expect(InsightScope(context: context).filter([filed]).isEmpty)
        try JournalOrganizationStore.setKeepsOutOfInsights(work, false, in: context)
        #expect(work.payload?.keepOutOfInsights == nil)
        #expect(InsightScope(context: context).filter([filed]).count == 1)
    }

    @Test func scratchIsCreatedOnceAndReusesAnExistingName() throws {
        let context = try context()
        let first = try JournalOrganizationStore.addScratchCollection(in: context)
        #expect(first.payload?.icon == JournalOrganizationStore.scratchIcon)
        #expect(first.payload?.keepsOutOfInsights == true)
        let again = try JournalOrganizationStore.addScratchCollection(in: context)
        #expect(again.id == first.id)
        #expect(JournalOrganizationStore.collections(in: context).count == 1)

        // A collection the user already called Scratch is switched over, not duplicated.
        let other = try self.context()
        let mine = try JournalOrganizationStore.createCollection(name: JournalOrganizationStore.scratchName.lowercased(), in: other)
        let reused = try JournalOrganizationStore.addScratchCollection(in: other)
        #expect(reused.id == mine.id)
        #expect(reused.payload?.keepsOutOfInsights == true)
        #expect(JournalOrganizationStore.collections(in: other).count == 1)
    }

    @Test func memoFollowsAMoveIntoAKeptOutCollection() throws {
        let context = try context()
        let scratch = try JournalOrganizationStore.addScratchCollection(in: context)
        let a = entry(in: nil, "One.", context: context)
        let b = entry(in: nil, "Two.", context: context)
        let c = entry(in: nil, "Three.", context: context)
        let collections = JournalOrganizationStore.collections(in: context)
        let memo = InsightEntriesMemo()
        #expect(memo.entries([a, b, c], collections: collections).count == 3)
        // Same count and same ends: only the revision tells the memo something moved.
        b.collectionID = scratch.id
        JournalRevision.shared.bump(settle: false)
        #expect(memo.entries([a, b, c], collections: collections).map(\.id) == [a.id, c.id])
    }

    @Test func archiveCarriesTheFlag() async throws {
        let context = try context()
        let scratch = try JournalOrganizationStore.addScratchCollection(in: context)
        let note = entry(in: scratch.id, "Milk, eggs, bread.", context: context)
        try context.save()
        let staged = try await ArchiveTransfer.stageArchive(entries: [note], collections: [scratch]) { _ in }
        defer { try? FileManager.default.removeItem(at: staged.root.deletingLastPathComponent()) }

        let target = try self.context()
        let plan = try await ArchiveTransfer.planImport(folder: staged.root, existing: [])
        _ = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: false, context: target)
        let imported = try #require(JournalOrganizationStore.collections(in: target).first)
        #expect(imported.id == scratch.id)
        #expect(imported.payload?.keepsOutOfInsights == true)
    }
}
