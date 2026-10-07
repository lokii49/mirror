import Testing
import Foundation
@testable import mirror

/// The entry list's in-memory decrypt cache. Synthetic text only.
@Suite("Entry decrypt cache")
struct EntryDecryptCacheTests {
    @Test @MainActor func readableEntryIsCachedAndAnEditIsPickedUp() {
        let cache = EntryDecryptCache()
        let entry = Entry(text: "Studied in the library till nine.", mood: "Content")
        #expect(cache.item(for: entry).searchText.contains("library"))
        #expect(cache.cachedCount == 1)
        entry.text = "Went for a run by the river."
        #expect(cache.item(for: entry).searchText.contains("river"))
        #expect(!cache.item(for: entry).searchText.contains("library"))
    }

    @Test @MainActor func failedDecryptIsNeverCached() {
        let cache = EntryDecryptCache()
        let entry = Entry(text: "")
        // Ciphertext under a key this device doesn't have.
        entry.encryptedText = "mirror:v1:" + Data((0..<64).map { UInt8($0) }).base64EncodedString()
        #expect(entry.textDecryptionFailed)
        #expect(cache.item(for: entry).preview.textDecryptionFailed)
        #expect(cache.cachedCount == 0)
    }

    @Test @MainActor func deletedEntriesArePruned() {
        let cache = EntryDecryptCache()
        let a = Entry(text: "Studied in the library till nine.")
        let b = Entry(text: "Went for a run by the river.")
        _ = cache.item(for: a); _ = cache.item(for: b)
        cache.prune(keeping: [a])
        #expect(cache.cachedCount == 1)
    }

    @Test @MainActor func replacingAnEntryAtTheSameCountPrunesTheOldDocument() {
        let cache = EntryDecryptCache()
        let a = Entry(text: "A synthetic note.")
        let b = Entry(text: "A different synthetic note.")
        _ = cache.item(for: a)
        cache.prune(keeping: [b])
        #expect(cache.cachedCount == 0)
    }

    @Test @MainActor func snapshotSignatureChangesWithSearchableEdits() {
        let entry = Entry(text: "Morning coffee.")
        var previous = EntryDecryptCache.contentSignature(for: [entry])
        entry.text = "Evening tea."
        #expect(previous != EntryDecryptCache.contentSignature(for: [entry]))
        previous = EntryDecryptCache.contentSignature(for: [entry])
        entry.voiceNoteEnglishTranslation = "Went to the library."
        #expect(previous != EntryDecryptCache.contentSignature(for: [entry]))
        previous = EntryDecryptCache.contentSignature(for: [entry])
        entry.isPinned = true
        #expect(previous != EntryDecryptCache.contentSignature(for: [entry]))
        previous = EntryDecryptCache.contentSignature(for: [entry])
        entry.createdAt = entry.createdAt.addingTimeInterval(-86_400)
        #expect(previous != EntryDecryptCache.contentSignature(for: [entry]))
    }

    @Test @MainActor func translationAndAdditionalTranscriptUpdatesInvalidateCache() {
        let cache = EntryDecryptCache()
        let entry = Entry(text: "A quiet day.")
        _ = cache.item(for: entry)
        entry.additionalVoiceNoteTranscripts = ["Visited 東京."]
        #expect(EntrySearch.matches(cache.item(for: entry).document, query: .parse("東京")))
        entry.additionalVoiceNoteEnglishTranslations = ["Visited the library."]
        #expect(EntrySearch.matches(cache.item(for: entry).document, query: .parse("library")))
        entry.additionalVoiceNoteEnglishTranslations = ["Visited the river."]
        #expect(!EntrySearch.matches(cache.item(for: entry).document, query: .parse("library")))
        #expect(EntrySearch.matches(cache.item(for: entry).document, query: .parse("river")))
    }

    @Test @MainActor func emptyAdditionalPhotoArrayDoesNotMatchPhotoFilter() {
        let entry = Entry(text: "A text-only note.")
        entry.additionalPhotoData = []
        let cache = EntryDecryptCache()
        #expect(!EntrySearch.matches(cache.item(for: entry).document, query: .parse("has:photo")))
    }

    @Test @MainActor func unavailableTranscriptIsNeverCachedAsSearchableText() {
        let entry = Entry(text: "A readable legacy entry.")
        entry.encryptedVoiceNoteTranscript = "mirror:v1:" + Data((0..<64).map { UInt8($0) }).base64EncodedString()
        let cache = EntryDecryptCache()
        #expect(!cache.item(for: entry).document.isReadable)
        #expect(cache.cachedCount == 0)
    }
}
