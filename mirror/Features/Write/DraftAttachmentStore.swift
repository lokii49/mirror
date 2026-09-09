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
        var languageCode: String?
        var languageName: String?
        var englishTranslation: String?    // encrypted string
    }

    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("mirror-draft-attachments.json")
    }

    static func save(photos: [Data], voiceNotes: [VoiceNote]) {
        guard let fileURL else { return }
        if photos.isEmpty && voiceNotes.isEmpty {
            clear()
            return
        }
        let payload = Payload(
            photos: photos.compactMap { MirrorEncryption.encryptOptionalData($0) },
            voiceNotes: voiceNotes.compactMap { note in
                guard let encData = MirrorEncryption.encryptOptionalData(note.data) else { return nil }
                return VoiceNote(
                    data: encData,
                    duration: note.duration,
                    transcript: MirrorEncryption.encryptOptionalString(note.transcript),
                    languageCode: note.languageCode,
                    languageName: note.languageName,
                    englishTranslation: MirrorEncryption.encryptOptionalString(note.englishTranslation)
                )
            }
        )
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        try? encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// Returns decrypted attachments, or nil when there's no draft file or the
    /// key is transiently unavailable (before first unlock) — same "leave it for
    /// a later launch" contract as the text draft.
    static func load() -> (photos: [Data], voiceNotes: [VoiceNote])? {
        guard let fileURL, let raw = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: raw) else { return nil }

        var photos: [Data] = []
        for blob in payload.photos {
            guard let decrypted = MirrorEncryption.decryptOptionalData(blob) else { return nil }
            photos.append(decrypted)
        }

        var notes: [VoiceNote] = []
        for note in payload.voiceNotes {
            guard let audio = MirrorEncryption.decryptOptionalData(note.data) else { return nil }
            notes.append(VoiceNote(
                data: audio,
                duration: note.duration,
                transcript: MirrorEncryption.decryptOptionalString(note.transcript),
                languageCode: note.languageCode,
                languageName: note.languageName,
                englishTranslation: MirrorEncryption.decryptOptionalString(note.englishTranslation)
            ))
        }
        return (photos, notes)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
