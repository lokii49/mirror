import Foundation

/// Persists a new entry's photo + voice-note attachments alongside the text
/// draft. `saveDraftToStorage` only ever kept text/style/mood/tags in
/// UserDefaults, so an unsaved draft with a photo or a voice memo lost the
/// attachment on app kill with no trace. Blobs (a voice note can be several MB)
/// go to a file in Application Support, not UserDefaults; contents are encrypted
/// with the same key as the entry itself.
enum DraftAttachmentStore {

    struct Payload: Codable {
        var photos: [Data] = []            // encrypted blobs, insertion order
        var voiceNotes: [VoiceNote] = []
    }

    struct VoiceNote: Codable {
        var data: Data                     // encrypted
        var duration: TimeInterval
        var transcript: String?            // encrypted string, nil if none
        var languageCode: String?          // encrypted string (plaintext before 3.0.9)
        var languageName: String?          // encrypted string (plaintext before 3.0.9)
        var englishTranslation: String?    // encrypted string
    }

    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("mirror-draft-attachments.json")
    }

    /// Encrypts every blob or writes nothing: if the key is unavailable a partial
    /// payload must never replace an earlier complete file.
    static func save(photos: [Data], voiceNotes: [VoiceNote]) {
        guard let fileURL else { return }
        if photos.isEmpty && voiceNotes.isEmpty {
            clear()
            return
        }
        guard let payload = sealed(photos: photos, voiceNotes: voiceNotes),
              let encoded = try? JSONEncoder().encode(payload) else { return }
        try? encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    static func sealed(photos: [Data], voiceNotes: [VoiceNote]) -> Payload? {
        var payload = Payload()
        for photo in photos {
            guard let blob = MirrorEncryption.sealData(photo) else { return nil }
            payload.photos.append(blob)
        }
        for note in voiceNotes {
            guard let audio = MirrorEncryption.sealData(note.data),
                  let transcript = strictString(note.transcript),
                  let languageCode = strictString(note.languageCode),
                  let languageName = strictString(note.languageName),
                  let translation = strictString(note.englishTranslation) else { return nil }
            payload.voiceNotes.append(VoiceNote(
                data: audio,
                duration: note.duration,
                transcript: transcript.value,
                languageCode: languageCode.value,
                languageName: languageName.value,
                englishTranslation: translation.value
            ))
        }
        return payload
    }

    /// Returns decrypted attachments, or nil when there's no draft file or any
    /// blob can't be decrypted right now (key unavailable before first unlock, or
    /// an archived key not synced yet). The file is left untouched for a later
    /// launch; a partial restore would be saved back over the complete original.
    static func load() -> (photos: [Data], voiceNotes: [VoiceNote])? {
        guard let fileURL, let raw = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: raw) else { return nil }
        return opened(payload)
    }

    static func opened(_ payload: Payload) -> (photos: [Data], voiceNotes: [VoiceNote])? {
        var photos: [Data] = []
        for blob in payload.photos {
            guard let decrypted = MirrorEncryption.openData(blob) else { return nil }
            photos.append(decrypted)
        }
        var notes: [VoiceNote] = []
        for note in payload.voiceNotes {
            guard let audio = MirrorEncryption.openData(note.data),
                  let transcript = openString(note.transcript),
                  let languageCode = openString(note.languageCode),
                  let languageName = openString(note.languageName),
                  let translation = openString(note.englishTranslation) else { return nil }
            notes.append(VoiceNote(
                data: audio,
                duration: note.duration,
                transcript: transcript.value,
                languageCode: languageCode.value,
                languageName: languageName.value,
                englishTranslation: translation.value
            ))
        }
        return (photos, notes)
    }

    /// Wrapped so "no value" (nil inside) is distinct from "encryption failed" (nil outside).
    private struct Box { var value: String? }

    private static func strictString(_ value: String?) -> Box? {
        guard let value else { return Box(value: nil) }
        guard let encrypted = MirrorEncryption.encryptStringStrict(value) else { return nil }
        return Box(value: encrypted)
    }

    /// Pre-3.0.9 files stored language code/name as plaintext; those pass through.
    private static func openString(_ value: String?) -> Box? {
        guard let value else { return Box(value: nil) }
        guard let decrypted = MirrorEncryption.decryptOptionalStringValue(value) else { return nil }
        return Box(value: decrypted)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
