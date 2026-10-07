import Foundation

/// Persists a new entry's photo + voice-note attachments alongside the text
/// draft. `saveDraftToStorage` only ever kept text/style/mood/tags in
/// UserDefaults, so an unsaved draft with a photo or a voice memo lost the
/// attachment on app kill with no trace. Blobs (a voice note can be several MB)
/// go to a file in Application Support, not UserDefaults; contents are encrypted
/// with the same key as the entry itself.
///
/// Same rule as `WriteDraftStore`: nothing that can't be decrypted right now is
/// ever overwritten or deleted, except by Delete Everything.
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

    typealias Attachments = (photos: [Data], voiceNotes: [VoiceNote])

    enum LoadResult {
        case none
        /// A file exists but can't be decrypted right now; it has been set aside.
        case unavailable
        case attachments(Attachments)
    }

    struct Location {
        var file: URL
        /// Holds a file that couldn't be decrypted when found, until its key arrives.
        var preserved: URL

        static var live: Location? {
            guard let dir = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ) else { return nil }
            return Location(
                file: dir.appendingPathComponent("mirror-draft-attachments.json"),
                preserved: dir.appendingPathComponent("mirror-draft-attachments.unreadable.json")
            )
        }
    }

    // MARK: - Save

    /// Encrypts every blob or writes nothing: if the key is unavailable a partial
    /// payload must never replace an earlier complete file. Returns whether the
    /// current attachments are stored.
    @discardableResult
    static func save(photos: [Data], voiceNotes: [VoiceNote],
                     at location: Location? = .live, crypto: WriteDraftStore.Crypto = .live) -> Bool {
        guard let location else { return false }
        if photos.isEmpty && voiceNotes.isEmpty {
            clear(at: location, crypto: crypto)
            return true
        }
        // A file this launch couldn't read is moved aside before anything replaces it.
        if FileManager.default.fileExists(atPath: location.file.path), read(location.file, crypto: crypto) == nil {
            preserve(location)
        }
        guard let payload = sealed(photos: photos, voiceNotes: voiceNotes, crypto: crypto),
              let encoded = try? JSONEncoder().encode(payload) else { return false }
        do {
            try encoded.write(to: location.file, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    static func sealed(photos: [Data], voiceNotes: [VoiceNote], crypto: WriteDraftStore.Crypto = .live) -> Payload? {
        var payload = Payload()
        for photo in photos {
            guard let blob = crypto.seal(photo) else { return nil }
            payload.photos.append(blob)
        }
        for note in voiceNotes {
            guard let audio = crypto.seal(note.data),
                  let transcript = strictString(note.transcript, crypto),
                  let languageCode = strictString(note.languageCode, crypto),
                  let languageName = strictString(note.languageName, crypto),
                  let translation = strictString(note.englishTranslation, crypto) else { return nil }
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

    // MARK: - Load

    /// Decrypted attachments, or nil when there are none or they can't be read yet.
    static func load() -> Attachments? {
        guard case .attachments(let attachments) = load(at: .live) else { return nil }
        return attachments
    }

    /// A file that won't decrypt is set aside (never returned partially: a partial
    /// restore would be saved back over the complete original) and offered again
    /// on a later launch once no newer attachment draft exists.
    static func load(at location: Location?, crypto: WriteDraftStore.Crypto = .live) -> LoadResult {
        guard let location else { return .none }
        let fm = FileManager.default
        if fm.fileExists(atPath: location.file.path) {
            guard let attachments = read(location.file, crypto: crypto) else {
                preserve(location)
                return .unavailable
            }
            return .attachments(attachments)
        }
        if fm.fileExists(atPath: location.preserved.path), let attachments = read(location.preserved, crypto: crypto) {
            try? fm.moveItem(at: location.preserved, to: location.file)
            return .attachments(attachments)
        }
        return .none
    }

    static func opened(_ payload: Payload, crypto: WriteDraftStore.Crypto = .live) -> Attachments? {
        var photos: [Data] = []
        for blob in payload.photos {
            guard let decrypted = crypto.open(blob) else { return nil }
            photos.append(decrypted)
        }
        var notes: [VoiceNote] = []
        for note in payload.voiceNotes {
            guard let audio = crypto.open(note.data),
                  let transcript = openString(note.transcript, crypto),
                  let languageCode = openString(note.languageCode, crypto),
                  let languageName = openString(note.languageName, crypto),
                  let translation = openString(note.englishTranslation, crypto) else { return nil }
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

    // MARK: - Clear

    /// Removes the current attachment draft if it can be read (or is corrupt
    /// JSON). A file that only lacks its key is set aside instead.
    static func clear(at location: Location? = .live, crypto: WriteDraftStore.Crypto = .live) {
        guard let location, FileManager.default.fileExists(atPath: location.file.path) else { return }
        if isUndecodable(location.file) || read(location.file, crypto: crypto) != nil {
            try? FileManager.default.removeItem(at: location.file)
        } else {
            preserve(location)
        }
    }

    /// Delete Everything and test-state reset: removes readable and unreadable files.
    static func clearIncludingPreserved(at location: Location? = .live) {
        guard let location else { return }
        try? FileManager.default.removeItem(at: location.file)
        try? FileManager.default.removeItem(at: location.preserved)
    }

    // MARK: - Private

    private static func read(_ url: URL, crypto: WriteDraftStore.Crypto) -> Attachments? {
        guard let raw = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: raw) else { return nil }
        return opened(payload, crypto: crypto)
    }

    private static func isUndecodable(_ url: URL) -> Bool {
        guard let raw = try? Data(contentsOf: url) else { return false }
        return (try? JSONDecoder().decode(Payload.self, from: raw)) == nil
    }

    /// Keeps the first unreadable file; never replaces one already held.
    private static func preserve(_ location: Location) {
        let fm = FileManager.default
        if fm.fileExists(atPath: location.preserved.path) {
            try? fm.removeItem(at: location.file)
        } else {
            try? fm.moveItem(at: location.file, to: location.preserved)
        }
    }

    /// Wrapped so "no value" (nil inside) is distinct from "encryption failed" (nil outside).
    private struct Box { var value: String? }

    private static func strictString(_ value: String?, _ crypto: WriteDraftStore.Crypto) -> Box? {
        guard let value else { return Box(value: nil) }
        guard let encrypted = crypto.sealString(value) else { return nil }
        return Box(value: encrypted)
    }

    /// Pre-3.0.9 files stored language code/name as plaintext; those pass through.
    private static func openString(_ value: String?, _ crypto: WriteDraftStore.Crypto) -> Box? {
        guard let value else { return Box(value: nil) }
        guard let decrypted = crypto.openLegacyString(value) else { return nil }
        return Box(value: decrypted)
    }
}
