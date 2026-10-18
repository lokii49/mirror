import Testing
import SwiftData
import Foundation
@testable import mirror

/// 3.1.4: Recently Deleted, Drafts and Duplicates. Synthetic text only.
@Suite(.serialized)
@MainActor
struct TrashDraftsDuplicatesTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: MirrorModelContainer.schema, configurations: config))
    }

    private func entries(_ context: ModelContext) -> [Entry] {
        (try? context.fetch(FetchDescriptor<Entry>())) ?? []
    }

    private func trash(_ context: ModelContext) -> [TrashedEntry] {
        (try? context.fetch(FetchDescriptor<TrashedEntry>())) ?? []
    }

    // MARK: - Recently Deleted

    /// A new stored field on `Entry` must be copied to and from the trash.
    @Test func trashedEntryHasEveryEntryField() {
        let schema = Schema([Entry.self, TrashedEntry.self])
        let entryFields = Set(schema.entitiesByName["Entry"]?.properties.map(\.name) ?? [])
        let trashFields = Set(schema.entitiesByName["TrashedEntry"]?.properties.map(\.name) ?? [])
        #expect(!entryFields.isEmpty)
        #expect(entryFields.subtracting(trashFields).isEmpty, "missing: \(entryFields.subtracting(trashFields))")
        #expect(trashFields.subtracting(entryFields) == ["entryID", "deletedAt"])
    }

    @Test func deleteMovesToTrashAndRestoreBringsBackTheSameEntry() throws {
        let context = try makeContext()
        let entry = Entry(text: "A synthetic morning by the window.", mood: "Calm")
        entry.tags = ["morning"]
        entry.isPinned = true
        entry.photoDataArray = [Data([1, 2, 3])]
        let id = entry.id
        let created = Date(timeIntervalSince1970: 1_000_000)
        entry.createdAt = created
        context.insert(entry)
        try context.save()
        let ciphertext = entry.encryptedText

        try EntryTrash.moveToTrash([entry], in: context)
        #expect(entries(context).isEmpty)
        #expect(trash(context).count == 1)
        #expect(trash(context).first?.encryptedText == ciphertext, "copied as stored, not re-encrypted")

        let restored = try EntryTrash.restore(trash(context), in: context)
        #expect(restored == [id])
        #expect(trash(context).isEmpty)
        let back = try #require(entries(context).first)
        #expect(back.id == id)
        #expect(back.text == "A synthetic morning by the window.")
        #expect(back.mood == "Calm")
        #expect(back.tags == ["morning"])
        #expect(back.isPinned)
        #expect(back.createdAt == created)
        #expect(back.photoDataArray == [Data([1, 2, 3])])
    }

    @Test func restoreOfAnEntryAlreadyBackOnlyRemovesTrashRows() throws {
        let context = try makeContext()
        let entry = Entry(text: "A synthetic note deleted on two devices.")
        context.insert(entry)
        try context.save()
        // Two devices deleted it: two rows for one entry, shown once.
        context.insert(TrashedEntry(copying: entry, deletedAt: Date(timeIntervalSinceNow: -60)))
        try EntryTrash.moveToTrash([entry], in: context)
        #expect(trash(context).count == 2)
        #expect(EntryTrash.items(in: context).count == 1)

        // Restored elsewhere and synced back before this device restores it.
        let rows = trash(context)
        context.insert(rows[0].restoredEntry())
        try context.save()
        let restored = try EntryTrash.restore([rows[1]], in: context)
        #expect(restored.isEmpty)
        #expect(entries(context).count == 1)
        #expect(trash(context).isEmpty)
    }

    @Test func restoreLeavesEntryUnfiledWhenItsCollectionIsGone() throws {
        let context = try makeContext()
        let entry = Entry(text: "A synthetic entry in a collection.")
        entry.collectionID = UUID()
        context.insert(entry)
        try context.save()
        try EntryTrash.moveToTrash([entry], in: context)
        try EntryTrash.restore(trash(context), in: context)
        #expect(entries(context).first?.collectionID == nil)
    }

    @Test func purgeRemovesOnlyRowsOlderThanThirtyDays() throws {
        let context = try makeContext()
        let now = Date()
        let old = Entry(text: "Old synthetic entry.")
        let recent = Entry(text: "Recent synthetic entry.")
        context.insert(TrashedEntry(copying: old, deletedAt: now.addingTimeInterval(-31 * 86_400)))
        context.insert(TrashedEntry(copying: recent, deletedAt: now.addingTimeInterval(-29 * 86_400)))
        try context.save()
        EntryTrash.purgeExpired(in: context, now: now)
        #expect(trash(context).map(\.entryID) == [recent.id])
    }

    @Test func deleteEverythingEmptiesTrashAndMarksItsIDs() throws {
        let context = try makeContext()
        let entry = Entry(text: "A synthetic entry in the trash.")
        context.insert(entry)
        try context.save()
        let id = entry.id
        try EntryTrash.moveToTrash([entry], in: context)
        JournalErase.eraseEverything(context: context)
        #expect(trash(context).isEmpty)
        #expect(JournalErasure.allErasedEntryIDs(in: context).contains(id))
    }

    // MARK: - Duplicates

    private func candidate(_ text: String, daysAgo: Double) -> EntryDuplicates.Candidate {
        .init(id: UUID(), text: text, createdAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
    }

    @Test func sameTextGroupsShortTextNever() {
        let a = candidate("Walked to the market and bought  bread.", daysAgo: 3)
        let b = candidate("Walked to the market and bought bread.\n", daysAgo: 1)
        let c = candidate("Walked to the market and bought milk.", daysAgo: 2)
        let short1 = candidate("Tired.", daysAgo: 5)
        let short2 = candidate("Tired.", daysAgo: 4)
        let groups = EntryDuplicates.groups([b, c, short1, a, short2])
        #expect(groups.count == 1)
        #expect(groups.first?.map(\.id) == [a.id, b.id], "oldest first")
        #expect(EntryDuplicates.spansSeveralDays(groups[0]))
    }

    @Test func mergeKeepsOldestAddsTagsAndTrashesTheRest() throws {
        let context = try makeContext()
        let older = Entry(text: "Walked to the market and bought bread.")
        older.createdAt = Date(timeIntervalSinceNow: -86_400)
        older.tags = ["walk"]
        let newer = Entry(text: "Walked to the market and bought bread.", mood: "Content")
        newer.tags = ["walk", "market"]
        newer.voiceNoteData = Data([9, 9])
        newer.voiceNoteDuration = 2
        context.insert(older); context.insert(newer)
        try context.save()
        let olderID = older.id, newerID = newer.id

        let kept = try EntryDuplicates.merge([newerID, olderID], in: context)
        #expect(kept == olderID)
        let remaining = entries(context)
        #expect(remaining.map(\.id) == [olderID])
        #expect(remaining.first?.tags == ["walk", "market"])
        #expect(remaining.first?.mood == "Content")
        #expect(remaining.first?.voiceNoteData == Data([9, 9]))
        #expect(trash(context).map(\.entryID) == [newerID], "the other copy can be restored")
    }

    // MARK: - Drafts

    private static let fakePrefix = Data("sealed:".utf8)
    private static let crypto = WriteDraftStore.Crypto(
        seal: { fakePrefix + Data($0.reversed()) },
        open: { $0.starts(with: fakePrefix) ? Data($0.dropFirst(fakePrefix.count).reversed()) : nil },
        openLegacyString: { $0 },
        sealString: { $0 }
    )

    @Test func saveToDraftsAndContinueSwapNeverLoseText() {
        let defaults = UserDefaults(suiteName: "TrashDraftsDuplicatesTests.drafts")!
        defaults.removePersistentDomain(forName: "TrashDraftsDuplicatesTests.drafts")
        let crypto = Self.crypto

        WriteDraftStore.save(.init(text: "First synthetic draft."), slot: .newEntry, defaults: defaults, crypto: crypto)
        let first = SavedDraftStore.stash(from: .newEntry, attachments: nil, defaults: defaults, crypto: crypto)
        #expect(first != nil)
        #expect(WriteDraftStore.load(slot: .newEntry, defaults: defaults, crypto: crypto) == .none)

        // Writing something else, then continuing the first: the second goes to Drafts.
        WriteDraftStore.save(.init(text: "Second synthetic draft."), slot: .newEntry, defaults: defaults, crypto: crypto)
        SavedDraftStore.stash(from: .newEntry, attachments: nil, defaults: defaults, crypto: crypto)
        #expect(SavedDraftStore.moveToEditor(first!, slot: .newEntry, attachments: nil, defaults: defaults))

        guard case .payload(let editor) = WriteDraftStore.load(slot: .newEntry, defaults: defaults, crypto: crypto) else {
            Issue.record("editor draft missing"); return
        }
        #expect(editor.text == "First synthetic draft.")
        let saved = SavedDraftStore.summaries(defaults: defaults, crypto: crypto)
        #expect(saved.map { $0.payload?.text } == ["Second synthetic draft."])
        #expect(saved.first?.savedAt != nil)

        SavedDraftStore.deleteAll(defaults: defaults)
        #expect(SavedDraftStore.ids(defaults: defaults).isEmpty)
    }

    @Test func draftPayloadKeepsCollectionAndOldDraftsDecode() throws {
        let id = UUID()
        var payload = WriteDraftStore.Payload(text: "Synthetic.")
        payload.collectionID = id
        let decoded = try JSONDecoder().decode(WriteDraftStore.Payload.self, from: JSONEncoder().encode(payload))
        #expect(decoded.collectionID == id)
        let old = Data(#"{"version":1,"text":"Synthetic.","tags":[]}"#.utf8)
        #expect(try JSONDecoder().decode(WriteDraftStore.Payload.self, from: old).collectionID == nil)
    }
}
