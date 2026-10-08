import Foundation
import SwiftData
import Testing
@testable import mirror

/// Synthetic text only.
@Suite("Collections and saved views")
@MainActor
struct JournalOrganizationTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        return container.mainContext
    }

    private func document(collection: UUID?, readable: Bool = true) -> EntrySearchDocument {
        EntrySearchDocument(passages: [.init("Synthetic.", source: .body)], tags: [], moods: [],
                            createdAt: Date(), hasPhoto: false, hasAudio: false, isPinned: false,
                            isReadable: readable, collectionID: collection)
    }

    @Test func collectionScopeFiltersByMembership() {
        let work = UUID()
        var criteria = EntryFilterCriteria()
        criteria.collection = .collection(work)
        #expect(criteria.matches(document(collection: work)))
        #expect(!criteria.matches(document(collection: nil)))
        #expect(!criteria.matches(document(collection: UUID())))
        // Membership is readable without the key.
        #expect(criteria.matches(document(collection: work, readable: false)))
        criteria.collection = .unfiled
        #expect(criteria.matches(document(collection: nil)))
        #expect(!criteria.matches(document(collection: work)))
        criteria.collection = .all
        #expect(!criteria.isActive)
    }

    @Test func entriesInAnUnknownCollectionShowAsUnfiled() {
        let gone = UUID()
        var unfiled = EntryFilterCriteria()
        unfiled.collection = .unfiled
        let results = EntrySearch.evaluate([(UUID(), document(collection: gone))], query: .parse(""),
                                           filters: unfiled, knownCollections: [])
        #expect(results.ids.count == 1)
        var missing = EntryFilterCriteria()
        missing.collection = .collection(gone)
        #expect(EntrySearch.evaluate([(UUID(), document(collection: gone))], query: .parse(""),
                                     filters: missing, knownCollections: []).ids.isEmpty)
    }

    @Test func savedDatesStayOnTheSameCalendarDaysAcrossTimeZones() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        var criteria = EntryFilterCriteria()
        criteria.dateScope = .range
        criteria.startDate = losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 22))
        criteria.endDate = losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 30))
        criteria.tags = ["work"]
        criteria.tagMatch = .all
        criteria.collection = .unfiled
        let stored = try JSONEncoder().encode(SavedCriteria(criteria, calendar: losAngeles))
        let reopened = try JSONDecoder().decode(SavedCriteria.self, from: stored).criteria(calendar: tokyo)
        let start = try #require(reopened.startDate)
        #expect(tokyo.dateComponents([.year, .month, .day, .hour], from: start) == DateComponents(year: 2026, month: 9, day: 1, hour: 0))
        #expect(tokyo.component(.day, from: try #require(reopened.endDate)) == 30)
        #expect(reopened.tagMatch == .all && reopened.tags == ["work"] && reopened.collection == .unfiled)
    }

    @Test func olderSavedCriteriaWithMissingKeysStillDecode() throws {
        let decoded = try JSONDecoder().decode(SavedCriteria.self, from: Data(#"{"moods":["Calm"]}"#.utf8))
        #expect(decoded.moods == ["Calm"] && decoded.collection == .all && !decoded.pinnedOnly)
    }

    @Test func deletingACollectionKeepsItsEntriesAsUnfiled() throws {
        let context = try context()
        let collection = try JournalOrganizationStore.createCollection(name: "Synthetic work", in: context)
        let entry = Entry(text: "Synthetic entry.")
        entry.isPinned = true
        entry.tags = ["keep"]
        context.insert(entry)
        try JournalOrganizationStore.move([entry], to: collection.id, in: context)
        #expect(JournalOrganizationStore.entryCount(in: collection.id, context: context) == 1)

        try JournalOrganizationStore.delete(collection, in: context)
        let survivor = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(survivor.id == entry.id && survivor.collectionID == nil && survivor.isPinned && survivor.tags == ["keep"])
        #expect(try context.fetchCount(FetchDescriptor<JournalCollection>()) == 0)
    }

    @Test func namesAreEncryptedAndRenamable() throws {
        let context = try context()
        let collection = try JournalOrganizationStore.createCollection(name: "Synthetic private name", in: context)
        let raw = try #require(collection.encryptedPayload)
        #expect(!String(decoding: raw, as: UTF8.self).contains("Synthetic"))
        try JournalOrganizationStore.rename(collection, to: "Renamed", in: context)
        #expect(collection.payload?.name == "Renamed")
    }

    @Test func savedViewsOrderAndDeleteWithoutTouchingEntries() throws {
        let context = try context()
        context.insert(Entry(text: "Synthetic entry."))
        let criteria = SavedCriteria(EntryFilterCriteria())
        let first = try JournalOrganizationStore.saveView(.init(name: "A", query: "river", criteria: criteria, sort: "Best Match"), in: context)
        let second = try JournalOrganizationStore.saveView(.init(name: "B", query: "", criteria: criteria, sort: "Newest First"), in: context)
        #expect(JournalOrganizationStore.savedViews(in: context).map(\.id) == [first.id, second.id])
        try JournalOrganizationStore.reorderViews([second, first], in: context)
        #expect(JournalOrganizationStore.savedViews(in: context).compactMap { $0.payload?.name } == ["B", "A"])
        try JournalOrganizationStore.delete(first, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(JournalOrganizationStore.savedViews(in: context).count == 1)
    }

    @Test func duplicateIdsFromRestoreAreCollapsed() throws {
        let context = try context()
        let original = try JournalOrganizationStore.createCollection(name: "Synthetic", in: context)
        context.insert(JournalCollection.restoredCopy(of: original))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<JournalCollection>()) == 2)
        JournalOrganizationStore.removeDuplicates(in: context)
        #expect(try context.fetchCount(FetchDescriptor<JournalCollection>()) == 1)
    }

    @Test func archiveRoundTripsMembershipAndCreatesMissingCollections() async throws {
        let source = try context()
        let collection = try JournalOrganizationStore.createCollection(name: "Synthetic trips", icon: "airplane", in: source)
        let entry = Entry(text: "Synthetic entry in a collection.")
        entry.collectionID = collection.id
        source.insert(entry)
        try source.save()
        // The same staging the Settings export zips.
        let staged = try await ArchiveTransfer.stageArchive(entries: [entry], collections: [collection]) { _ in }
        let root = staged.root
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let path = root.appendingPathComponent("entries/\(ArchivePackage.fileName(for: try #require(entry.archiveSnapshot())))")
        #expect(try String(contentsOf: path, encoding: .utf8).contains("collection: \"Synthetic trips\""))

        let target = try context()
        let plan = try await ArchiveTransfer.planImport(folder: root, existing: [])
        let batch = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: false, context: target)
        let imported = try #require(try target.fetch(FetchDescriptor<Entry>()).first)
        #expect(imported.collectionID == collection.id)
        #expect(JournalOrganizationStore.collections(in: target).first?.payload?.name == "Synthetic trips")

        _ = try ArchiveTransfer.undoImport(batch, context: target)
        #expect(try target.fetchCount(FetchDescriptor<JournalCollection>()) == 0)
    }
    @Test func archiveRoundTripsSavedViewsOnceAndUndoRemovesThem() async throws {
        let source = try context()
        var criteria = EntryFilterCriteria()
        criteria.moods = ["Anxious"]
        criteria.tags = ["synthetic-work"]
        criteria.dateScope = .range
        criteria.startDate = CivilDate(year: 2026, month: 9, day: 1).date()
        criteria.endDate = CivilDate(year: 2026, month: 9, day: 30).date()
        let view = try JournalOrganizationStore.saveView(
            .init(name: "Synthetic hard Septembers", query: "synthetic phrase", criteria: SavedCriteria(criteria), sort: "oldest"),
            in: source)
        let entry = Entry(text: "Synthetic entry.")
        source.insert(entry)
        try source.save()
        let staged = try await ArchiveTransfer.stageArchive(entries: [entry], collections: [], savedViews: [view]) { _ in }
        let root = staged.root
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let target = try context()
        let plan = try await ArchiveTransfer.planImport(folder: root, existing: [])
        #expect(plan.savedViews.count == 1)
        let batch = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: false, context: target)
        let imported = try #require(JournalOrganizationStore.savedViews(in: target).first)
        #expect(imported.id == view.id)
        #expect(imported.payload == view.payload)

        // Importing the same package again adds no second view.
        let again = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: false, context: target)
        #expect(again.createdSavedViews.isEmpty)
        #expect(JournalOrganizationStore.savedViews(in: target).count == 1)

        _ = try ArchiveTransfer.undoImport(batch, context: target)
        #expect(try target.fetchCount(FetchDescriptor<SavedEntryView>()) == 0)
    }

    @Test func manifestWithoutSavedViewsStillDecodes() throws {
        let json = """
        {"format":"mirrornotes-archive","version":1,"appVersion":"3.0.8","exportedAt":"2026-10-01T00:00:00Z",
         "exportedTimeZone":"UTC","entries":[],"unreadable":[]}
        """
        let manifest = try ArchivePackage.decoder.decode(ArchivePackage.Manifest.self, from: Data(json.utf8))
        #expect(manifest.savedViews == nil)
    }
}
