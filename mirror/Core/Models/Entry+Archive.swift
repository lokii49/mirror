import Foundation
import SwiftData

extension Entry {
    /// Every field decrypted strictly, or nil when any of them can't be read on
    /// this device. The ordinary accessors fall back to ciphertext (data) or a
    /// placeholder (tags), which must never end up in an exported file.
    func archiveSnapshot() -> ArchivePackage.ArchiveEntry? {
        func string(_ value: String?) -> String?? {
            guard let value else { return .some(nil) }
            guard let opened = MirrorEncryption.decryptOptionalStringValue(value) else { return nil }
            return .some(opened)
        }
        func strings(_ storage: Data?) -> [String]? {
            var result: [String] = []
            for value in Self.decodedStringArray(from: storage) {
                guard let opened = MirrorEncryption.decryptOptionalStringValue(value) else { return nil }
                result.append(opened)
            }
            return result
        }
        guard let text = decryptedText,
              let mood = string(encryptedMood),
              let tags = strings(encryptedTagsStorage),
              let textStyle = Self.openArchiveData(encryptedTextStyleData),
              let inlineStyle = Self.openArchiveData(encryptedInlineStyleData) else { return nil }

        var photos: [Data] = []
        if let first = encryptedPhotoData {
            guard let opened = Self.openArchiveMedia(first) else { return nil }
            photos.append(opened)
        }
        for blob in Self.decodedDataArray(from: encryptedAdditionalPhotoDataStorage) {
            guard let opened = Self.openArchiveMedia(blob) else { return nil }
            photos.append(opened)
        }

        var notes: [ArchivePackage.VoiceNote] = []
        if let first = encryptedVoiceNoteData {
            guard let audio = Self.openArchiveMedia(first),
                  let transcript = string(encryptedVoiceNoteTranscript),
                  let code = string(encryptedVoiceNoteLanguageCode),
                  let name = string(encryptedVoiceNoteLanguageName),
                  let translation = string(encryptedVoiceNoteEnglishTranslation) else { return nil }
            notes.append(.init(data: audio, duration: voiceNoteDuration, transcript: transcript,
                               languageCode: code, languageName: name, englishTranslation: translation))
        }
        let extraAudio = Self.decodedDataArray(from: encryptedAdditionalVoiceNoteDataStorage)
        if !extraAudio.isEmpty {
            let durations = Self.decodedDoubleArray(from: additionalVoiceNoteDurationsStorage)
            guard let transcripts = strings(encryptedAdditionalVoiceNoteTranscriptsStorage),
                  let codes = strings(encryptedAdditionalVoiceNoteLanguageCodesStorage),
                  let names = strings(encryptedAdditionalVoiceNoteLanguageNamesStorage),
                  let translations = strings(encryptedAdditionalVoiceNoteEnglishTranslationsStorage) else { return nil }
            for (index, blob) in extraAudio.enumerated() {
                guard let audio = Self.openArchiveMedia(blob) else { return nil }
                func at(_ array: [String]) -> String? {
                    array.indices.contains(index) && !array[index].isEmpty ? array[index] : nil
                }
                notes.append(.init(data: audio, duration: durations.indices.contains(index) ? durations[index] : 0,
                                   transcript: at(transcripts), languageCode: at(codes), languageName: at(names),
                                   englishTranslation: at(translations)))
            }
        }

        return ArchivePackage.ArchiveEntry(
            id: id, createdAt: createdAt, text: text, textStyleData: textStyle,
            inlineStyleData: inlineStyle, mood: mood, tags: tags, fontChoice: fontChoice,
            isPinned: isPinned, source: source.rawValue, photos: photos, voiceNotes: notes
        )
    }

    /// `.some(nil)` for no data, nil when it won't decrypt.
    private static func openArchiveData(_ data: Data?) -> Data?? {
        guard let data, !data.isEmpty else { return .some(nil) }
        guard let opened = MirrorEncryption.openData(data) else { return nil }
        return .some(opened)
    }

    /// Older builds stored a recording or photo unencrypted when the key was
    /// missing at save time; those are recognized by their file signature.
    private static func openArchiveMedia(_ data: Data) -> Data? {
        if let opened = MirrorEncryption.openData(data) { return opened }
        let isImage = ArchivePackage.imageExtension(data) != "bin"
        let bytes = [UInt8](data.prefix(8))
        let isMP4 = bytes.count >= 8 && bytes[4...7] == [0x66, 0x74, 0x79, 0x70][...]
        return isImage || isMP4 ? data : nil
    }

    /// Inserts an imported entry exactly as packaged (the given id, or a new one for a copy).
    @discardableResult
    static func insert(_ archived: ArchivePackage.ArchiveEntry, id: UUID, into context: ModelContext) -> Entry {
        let entry = Entry(text: archived.text, mood: archived.mood, source: EntrySource(rawValue: archived.source) ?? .typed)
        entry.id = id
        entry.createdAt = archived.createdAt
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: archived.createdAt)
        entry.textStyleData = archived.textStyleData
        entry.inlineStyleData = archived.inlineStyleData
        entry.tags = archived.tags
        entry.fontChoice = archived.fontChoice
        entry.isPinned = archived.isPinned
        entry.photoDataArray = archived.photos
        if let first = archived.voiceNotes.first {
            entry.voiceNoteData = first.data
            entry.voiceNoteDuration = first.duration
            entry.voiceNoteTranscript = first.transcript
            entry.voiceNoteLanguageCode = first.languageCode
            entry.voiceNoteLanguageName = first.languageName
            entry.voiceNoteEnglishTranslation = first.englishTranslation
        }
        let rest = Array(archived.voiceNotes.dropFirst())
        entry.additionalVoiceNoteData = rest.map(\.data)
        entry.additionalVoiceNoteDurations = rest.map(\.duration)
        entry.additionalVoiceNoteTranscripts = rest.map { $0.transcript ?? "" }
        entry.additionalVoiceNoteLanguageCodes = rest.map { $0.languageCode ?? "" }
        entry.additionalVoiceNoteLanguageNames = rest.map { $0.languageName ?? "" }
        entry.additionalVoiceNoteEnglishTranslations = rest.map { $0.englishTranslation ?? "" }
        context.insert(entry)
        return entry
    }
}
