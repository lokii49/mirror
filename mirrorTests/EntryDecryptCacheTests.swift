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
}
