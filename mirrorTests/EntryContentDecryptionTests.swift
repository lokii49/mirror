import Testing
import Foundation
@testable import mirror

/// `Entry.contentDecryptionFailed`: the editor's gate for entries whose fields this device
/// can't open (backlog A2). Synthetic text and bytes only.
@Suite("Entry content decryption")
struct EntryContentDecryptionTests {
    /// Sealed bytes under a key this device doesn't have: long enough to parse as an AES-GCM box
    /// (12-byte nonce + tag), but no key opens it. Starts with 0x00, not a known plaintext magic.
    private static let foreignCiphertext = Data((0..<64).map { UInt8($0) })
    private static let foreignString = "mirror:v1:" + foreignCiphertext.base64EncodedString()

    @Test func readableTypedEntryIsNotFlagged() {
        let entry = Entry(text: "Walked to the bakery before work.", mood: "Content")
        entry.tags = ["morning"]
        #expect(!entry.contentDecryptionFailed)
    }

    @Test func readableVoiceOnlyEntryIsNotFlagged() {
        let entry = Entry(text: "")
        entry.voiceNoteData = Data([0, 0, 0, 0x20] + Array("ftypM4A ".utf8) + Array(repeating: 7, count: 40))
        entry.voiceNoteTranscript = "A short synthetic note."
        #expect(!entry.contentDecryptionFailed)
    }

    @Test func voiceOnlyEntryFromAnotherKeyIsFlagged() {
        let entry = Entry(text: "")
        entry.encryptedVoiceNoteData = Self.foreignCiphertext
        entry.voiceNoteDuration = 4
        // The bug: the text guard alone passes this entry, so the editor would save it back.
        #expect(!entry.textDecryptionFailed)
        #expect(entry.contentDecryptionFailed)
    }

    @Test func foreignAdditionalVoiceNoteIsFlagged() {
        let entry = Entry(text: "")
        entry.encryptedAdditionalVoiceNoteDataStorage = try? JSONEncoder().encode([Self.foreignCiphertext])
        #expect(entry.contentDecryptionFailed)
    }

    @Test func foreignTagIsFlagged() throws {
        let entry = Entry(text: "Readable text.")
        entry.encryptedTagsStorage = try JSONEncoder().encode([Self.foreignString])
        #expect(entry.contentDecryptionFailed)
    }

    @Test func foreignMoodOrTranscriptIsFlagged() {
        let mood = Entry(text: "")
        mood.encryptedMood = Self.foreignString
        #expect(mood.contentDecryptionFailed)

        let transcript = Entry(text: "")
        transcript.encryptedVoiceNoteTranscript = Self.foreignString
        #expect(transcript.contentDecryptionFailed)
    }

    @Test func plaintextMediaStoredUnencryptedIsNotFlagged() throws {
        let entry = Entry(text: "")
        entry.encryptedPhotoData = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 1, count: 60))
        entry.encryptedVoiceNoteData = Data([0, 0, 0, 0x20] + Array("ftypM4A ".utf8) + Array(repeating: 2, count: 60))
        entry.encryptedInlineStyleData = try JSONEncoder().encode(["ranges": [String]()])
        #expect(!entry.contentDecryptionFailed)
    }

    @Test func plaintextPayloadSniffing() {
        #expect(MirrorEncryption.looksLikePlaintextPayload(Data([0x89, 0x50, 0x4E, 0x47, 0x0D])))
        #expect(MirrorEncryption.looksLikePlaintextPayload(Data("{\"a\":1}".utf8)))
        #expect(!MirrorEncryption.looksLikePlaintextPayload(Self.foreignCiphertext))
        #expect(!MirrorEncryption.looksLikePlaintextPayload(Data()))
    }
}
