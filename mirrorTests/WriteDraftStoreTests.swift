import Foundation
import Testing
@testable import mirror

/// Synthetic text only. Each test uses its own UserDefaults suite.
@Suite("Encrypted write draft store")
struct WriteDraftStoreTests {

    private static let fakePrefix = Data("sealed:".utf8)

    /// Reversible stand-in for AES so tests can switch the "key" off.
    private static func crypto(available: Bool = true) -> WriteDraftStore.Crypto {
        WriteDraftStore.Crypto(
            seal: { available ? fakePrefix + Data($0.reversed()) : nil },
            open: { data in
                guard available, data.starts(with: fakePrefix) else { return nil }
                return Data(data.dropFirst(fakePrefix.count).reversed())
            },
            openLegacyString: { value in
                guard value.hasPrefix("legacy:") else { return value }
                return available ? String(value.dropFirst("legacy:".count)) : nil
            }
        )
    }

    private static func defaults() -> UserDefaults {
        let name = "WriteDraftStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let sample = WriteDraftStore.Payload(
        text: "Synthetic draft about a quiet afternoon.",
        textStyleData: Data("style".utf8),
        inlineStyleData: Data("https://example.com/link".utf8),
        mood: "Calm",
        tags: ["walk", "notes"]
    )

    private static func writeLegacy(_ defaults: UserDefaults) {
        defaults.set("legacy:Synthetic legacy draft.", forKey: WriteDraftStore.legacyTextKey)
        defaults.set(Data("style".utf8), forKey: WriteDraftStore.legacyTextStyleKey)
        defaults.set(Data("https://example.com".utf8), forKey: WriteDraftStore.legacyInlineStyleKey)
        defaults.set("Tired", forKey: WriteDraftStore.legacyMoodKey)
        defaults.set(try! JSONEncoder().encode(["legacy:errands"]), forKey: WriteDraftStore.legacyTagsKey)
    }

    @Test func roundTripStoresNoPlaintextMetadata() throws {
        let defaults = Self.defaults()
        #expect(WriteDraftStore.save(Self.sample, defaults: defaults, crypto: Self.crypto()))
        let stored = try #require(defaults.data(forKey: WriteDraftStore.Slot.newEntry.key))
        let readable = String(decoding: stored, as: UTF8.self)
        #expect(!readable.contains("Calm"))
        #expect(!readable.contains("example.com"))
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .payload(Self.sample))
    }

    @Test func legacyDraftMigratesAndLegacyKeysAreRemoved() {
        let defaults = Self.defaults()
        Self.writeLegacy(defaults)
        guard case .payload(let draft) = WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) else {
            Issue.record("legacy draft not restored")
            return
        }
        #expect(draft.text == "Synthetic legacy draft.")
        #expect(draft.mood == "Tired")
        #expect(draft.tags == ["errands"])
        #expect(draft.inlineStyleData == Data("https://example.com".utf8))
        for key in WriteDraftStore.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .payload(draft))
    }

    @Test func interruptedMigrationTrustsTheNewBlob() {
        let defaults = Self.defaults()
        Self.writeLegacy(defaults)
        WriteDraftStore.save(Self.sample, defaults: defaults, crypto: Self.crypto())
        // save() already drops legacy keys; recreate the crash-in-between state.
        Self.writeLegacy(defaults)
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .payload(Self.sample))
        for key in WriteDraftStore.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test func unavailableKeyLeavesLegacyDraftUntouched() {
        let defaults = Self.defaults()
        Self.writeLegacy(defaults)
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto(available: false)) == .unavailable)
        for key in WriteDraftStore.legacyKeys {
            #expect(defaults.object(forKey: key) != nil)
        }
        #expect(defaults.data(forKey: WriteDraftStore.Slot.newEntry.key) == nil)
    }

    @Test func failedEncryptionNeitherOverwritesNorClears() {
        let defaults = Self.defaults()
        WriteDraftStore.save(Self.sample, defaults: defaults, crypto: Self.crypto())
        let before = defaults.data(forKey: WriteDraftStore.Slot.newEntry.key)
        var changed = Self.sample
        changed.text = "Different synthetic text."
        #expect(!WriteDraftStore.save(changed, defaults: defaults, crypto: Self.crypto(available: false)))
        #expect(defaults.data(forKey: WriteDraftStore.Slot.newEntry.key) == before)
    }

    @Test func unreadableBlobIsPreservedAndRestoredOnceReadable() {
        let defaults = Self.defaults()
        WriteDraftStore.save(Self.sample, defaults: defaults, crypto: Self.crypto())
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto(available: false)) == .unavailable)

        // A new draft written meanwhile must not destroy the held-back one.
        var other = Self.sample
        other.text = "Newer synthetic draft."
        WriteDraftStore.save(other, defaults: defaults, crypto: Self.crypto())
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .payload(other))
        WriteDraftStore.clear(defaults: defaults)

        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .payload(Self.sample))
        #expect(defaults.data(forKey: WriteDraftStore.Slot.newEntry.preservedKey) == nil)
    }

    @Test func emptyDraftClearsEverything() {
        let defaults = Self.defaults()
        Self.writeLegacy(defaults)
        WriteDraftStore.save(Self.sample, defaults: defaults, crypto: Self.crypto())
        #expect(WriteDraftStore.save(WriteDraftStore.Payload(), defaults: defaults, crypto: Self.crypto()))
        #expect(defaults.data(forKey: WriteDraftStore.Slot.newEntry.key) == nil)
        for key in WriteDraftStore.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .none)
    }

    @Test func eraseDropsPreservedDrafts() {
        let defaults = Self.defaults()
        WriteDraftStore.save(Self.sample, defaults: defaults, crypto: Self.crypto())
        _ = WriteDraftStore.load(defaults: defaults, crypto: Self.crypto(available: false))
        WriteDraftStore.clearIncludingPreserved(defaults: defaults)
        #expect(WriteDraftStore.load(defaults: defaults, crypto: Self.crypto()) == .none)
    }

    @Test func attachmentsRoundTripWithLanguageMetadataEncrypted() throws {
        let note = DraftAttachmentStore.VoiceNote(
            data: Data([1, 2, 3, 4]), duration: 3,
            transcript: "Synthetic transcript", languageCode: "de",
            languageName: "German", englishTranslation: "Synthetic translation"
        )
        let sealed = try #require(DraftAttachmentStore.sealed(photos: [Data([9, 9, 9])], voiceNotes: [note]))
        let encoded = String(decoding: try JSONEncoder().encode(sealed), as: UTF8.self)
        #expect(!encoded.contains("German"))
        #expect(!encoded.contains("\"de\""))
        let opened = try #require(DraftAttachmentStore.opened(sealed))
        #expect(opened.photos == [Data([9, 9, 9])])
        #expect(opened.voiceNotes.first?.languageCode == "de")
        #expect(opened.voiceNotes.first?.languageName == "German")
        #expect(opened.voiceNotes.first?.transcript == "Synthetic transcript")
    }

    @Test func attachmentsWithUndecryptableBlobRestoreNothing() {
        let payload = DraftAttachmentStore.Payload(photos: [Data("not ciphertext".utf8)], voiceNotes: [])
        #expect(DraftAttachmentStore.opened(payload) == nil)
    }
}
