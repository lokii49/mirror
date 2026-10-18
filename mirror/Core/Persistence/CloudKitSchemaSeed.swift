#if DEBUG
import Foundation
import SwiftData

/// DEBUG `--seedCloudKitSchema`: makes CloudKit's Development environment learn the `CD_JournalErasure`
/// record type without running "Delete Everything". Inserts two erase markers holding only random UUIDs
/// (never real entry IDs): a small one, which creates the scalar fields, and one over 1 MB, which makes
/// NSPersistentCloudKitContainer store the blob as an asset and so creates the `_ckAsset` companion
/// fields too. Once they've exported, Deploy Schema Changes in CloudKit Console copies them to
/// Production. Run on a simulator signed into iCloud: a development build syncs to the Development
/// environment, so it must not run against a store that holds real data. The markers are harmless:
/// restore only skips the IDs they list, and these match no entry.
enum CloudKitSchemaSeed {
    static var isRequested: Bool { CommandLine.arguments.contains("--seedCloudKitSchema") }
    static var isRemovalRequested: Bool { CommandLine.arguments.contains("--removeCloudKitSchemaSeed") }

    static let seedEntryText = "CloudKit schema seed. Safe to delete."
    static let seedName = "Schema seed"
    /// 3.1.4: `entryID` of the seeded Recently Deleted rows (no real entry has it).
    static let seedTrashedEntryID = UUID(uuidString: "5EED7A54-0000-4000-8000-000000000314")!

    /// `--removeCloudKitSchemaSeed`: deletes only what `run` added (the seed entry, the
    /// "Schema seed" collection and saved view, and the 3.1.4 Recently Deleted rows with
    /// `seedTrashedEntryID`), matched by exact text/name/id.
    /// Erase markers stay: they list random UUIDs only. Keep the app open ~2 minutes.
    @MainActor
    static func removeSeed(context: ModelContext) {
        let entries = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).filter { $0.decryptedText == seedEntryText }
        let collections = ((try? context.fetch(FetchDescriptor<JournalCollection>())) ?? []).filter { $0.payload?.name == seedName }
        let views = ((try? context.fetch(FetchDescriptor<SavedEntryView>())) ?? []).filter { $0.payload?.name == seedName }
        let trashed = ((try? context.fetch(FetchDescriptor<TrashedEntry>())) ?? []).filter { $0.entryID == seedTrashedEntryID }
        trashed.forEach(context.delete)
        entries.forEach(context.delete)
        collections.forEach(context.delete)
        views.forEach(context.delete)
        try? context.save()
        NSLog("CloudKitSchemaSeed: removed %d seed entries, %d collections, %d saved views, %d Recently Deleted rows; keep the app open ~2 minutes so the deletions export",
              entries.count, collections.count, views.count, trashed.count)
    }

    @MainActor
    static func run(context: ModelContext) {
        let small = JournalErasure(erasedEntryIDs: [UUID()], erasedCheckInIDs: [UUID()])
        let big = (0..<70_000).map { _ in UUID() }   // 70,000 × 16 bytes ≈ 1.1 MB
        let large = JournalErasure(erasedEntryIDs: big, erasedCheckInIDs: big)
        context.insert(small)
        context.insert(large)
        // 3.0.9: CD_JournalCollection, CD_SavedEntryView and Entry's CD_collectionID field.
        // Synthetic names only; delete the seed entry afterwards (it is a normal entry).
        let collection = JournalCollection(payload: .init(name: seedName), sortIndex: 0)
        context.insert(collection)
        context.insert(SavedEntryView(payload: .init(name: seedName, query: "seed",
                                                     criteria: SavedCriteria(EntryFilterCriteria()), sort: "Newest First"),
                                      sortIndex: 0))
        let entry = Entry(text: seedEntryText)
        entry.collectionID = collection.id
        context.insert(entry)
        // 3.1.4: CD_TrashedEntry. A small row creates the scalar fields; a second with every Data
        // field over 1 MB (random bytes, not journal data) creates their `_ckAsset` companions.
        let smallTrashed = TrashedEntry(copying: entry)
        smallTrashed.entryID = seedTrashedEntryID
        context.insert(smallTrashed)
        let largeTrashed = TrashedEntry(copying: entry)
        largeTrashed.entryID = seedTrashedEntryID
        let blob = { Data((0..<1_100_000).map { _ in UInt8.random(in: 0...255) }) }
        largeTrashed.encryptedTextStyleData = blob()
        largeTrashed.encryptedInlineStyleData = blob()
        largeTrashed.encryptedPhotoData = blob()
        largeTrashed.encryptedAdditionalPhotoDataStorage = blob()
        largeTrashed.encryptedVoiceNoteData = blob()
        largeTrashed.encryptedAdditionalVoiceNoteDataStorage = blob()
        largeTrashed.additionalVoiceNoteDurationsStorage = blob()
        largeTrashed.encryptedAdditionalVoiceNoteTranscriptsStorage = blob()
        largeTrashed.encryptedAdditionalVoiceNoteLanguageCodesStorage = blob()
        largeTrashed.encryptedAdditionalVoiceNoteLanguageNamesStorage = blob()
        largeTrashed.encryptedAdditionalVoiceNoteEnglishTranslationsStorage = blob()
        largeTrashed.encryptedTagsStorage = blob()
        context.insert(largeTrashed)
        try? context.save()
        // 3.1.4 (part 2): UserProfile's CD_trashRetentionDays. CloudKit learns a field only from a
        // record that exports it, so change each profile and change it back (two saves, two exports).
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        for profile in profiles {
            let kept = profile.trashRetentionDays
            profile.trashRetentionDays = kept == 90 ? 7 : 90
            try? context.save()
            profile.trashRetentionDays = kept
            try? context.save()
        }
        NSLog("CloudKitSchemaSeed: touched %d profiles for trashRetentionDays", profiles.count)
        NSLog("CloudKitSchemaSeed: inserted erase markers, a collection, a saved view, one seed entry and two Recently Deleted rows; keep the app open ~2 minutes so they export")
    }
}
#endif
