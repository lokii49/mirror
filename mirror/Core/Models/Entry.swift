import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case typed, voice
}

@Model final class Entry {
    var id: UUID = UUID()
    var encryptedText: String = ""
    var encryptedTextStyleData: Data? = nil
    var encryptedInlineStyleData: Data? = nil
    var createdAt: Date = Date()
    var wordCount: Int = 0
    var encryptedMood: String? = nil
    var source: EntrySource = EntrySource.typed
    var encryptedPhotoData: Data? = nil
    var encryptedAdditionalPhotoDataStorage: Data? = nil
    var encryptedVoiceNoteData: Data? = nil
    var voiceNoteDuration: Double = 0
    var encryptedVoiceNoteTranscript: String? = nil
    var encryptedVoiceNoteLanguageCode: String? = nil
    var encryptedVoiceNoteLanguageName: String? = nil
    var encryptedVoiceNoteEnglishTranslation: String? = nil
    var encryptedAdditionalVoiceNoteDataStorage: Data? = nil
    var additionalVoiceNoteDurationsStorage: Data? = nil
    var encryptedAdditionalVoiceNoteTranscriptsStorage: Data? = nil
    var encryptedAdditionalVoiceNoteLanguageCodesStorage: Data? = nil
    var encryptedAdditionalVoiceNoteLanguageNamesStorage: Data? = nil
    var encryptedAdditionalVoiceNoteEnglishTranslationsStorage: Data? = nil
    var weekIdentifier: String = ""
    var voiceNoteTranscriptionFailed: Bool = false
    var encryptedTagsStorage: Data? = nil

    var text: String {
        get { decryptedText ?? "" }
        set {
            encryptedText = MirrorEncryption.encryptString(newValue)
            wordCount = strippedWordCount(newValue)
        }
    }

    var decryptedText: String? {
        MirrorEncryption.decryptOptionalStringValue(encryptedText)
    }

    var textDecryptionFailed: Bool {
        MirrorEncryption.encryptedStringNeedsUnavailableKey(encryptedText)
    }

    var textStyleData: Data? {
        get { MirrorEncryption.decryptOptionalData(encryptedTextStyleData) }
        set { encryptedTextStyleData = MirrorEncryption.encryptOptionalData(newValue) }
    }

    var inlineStyleData: Data? {
        get { MirrorEncryption.decryptOptionalData(encryptedInlineStyleData) }
        set { encryptedInlineStyleData = MirrorEncryption.encryptOptionalData(newValue) }
    }

    var mood: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedMood) }
        set { encryptedMood = MirrorEncryption.encryptOptionalString(newValue) }
    }

    var photoData: Data? {
        get { MirrorEncryption.decryptOptionalData(encryptedPhotoData) }
        set { encryptedPhotoData = MirrorEncryption.encryptOptionalData(newValue) }
    }

    var hasPhoto: Bool {
        encryptedPhotoData != nil
    }

    var additionalPhotoData: [Data] {
        get { MirrorEncryption.decryptDataArray(Self.decodedDataArray(from: encryptedAdditionalPhotoDataStorage)) }
        set { encryptedAdditionalPhotoDataStorage = Self.encoded(MirrorEncryption.encryptDataArray(newValue)) }
    }

    // All photos in insertion order: [photoData (index 0), additionalPhotoData...]
    var photoDataArray: [Data] {
        get {
            var arr: [Data] = []
            if let p = photoData { arr.append(p) }
            arr.append(contentsOf: additionalPhotoData)
            return arr
        }
        set {
            photoData = newValue.first
            additionalPhotoData = newValue.count > 1 ? Array(newValue.dropFirst()) : []
        }
    }

    var voiceNoteData: Data? {
        get { MirrorEncryption.decryptOptionalData(encryptedVoiceNoteData) }
        set { encryptedVoiceNoteData = MirrorEncryption.encryptOptionalData(newValue) }
    }

    var voiceNoteTranscript: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedVoiceNoteTranscript) }
        set { encryptedVoiceNoteTranscript = MirrorEncryption.encryptOptionalString(newValue) }
    }

    var voiceNoteLanguageCode: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedVoiceNoteLanguageCode) }
        set { encryptedVoiceNoteLanguageCode = MirrorEncryption.encryptOptionalString(newValue) }
    }

    var voiceNoteLanguageName: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedVoiceNoteLanguageName) }
        set { encryptedVoiceNoteLanguageName = MirrorEncryption.encryptOptionalString(newValue) }
    }

    var voiceNoteEnglishTranslation: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedVoiceNoteEnglishTranslation) }
        set { encryptedVoiceNoteEnglishTranslation = MirrorEncryption.encryptOptionalString(newValue) }
    }

    var additionalVoiceNoteData: [Data] {
        get { MirrorEncryption.decryptDataArray(Self.decodedDataArray(from: encryptedAdditionalVoiceNoteDataStorage)) }
        set { encryptedAdditionalVoiceNoteDataStorage = Self.encoded(MirrorEncryption.encryptDataArray(newValue)) }
    }

    var additionalVoiceNoteDurations: [Double] {
        get { Self.decodedDoubleArray(from: additionalVoiceNoteDurationsStorage) }
        set { additionalVoiceNoteDurationsStorage = Self.encoded(newValue) }
    }

    var additionalVoiceNoteTranscripts: [String] {
        get { Self.decodedStringArray(from: encryptedAdditionalVoiceNoteTranscriptsStorage).map { MirrorEncryption.decryptString($0) } }
        set { encryptedAdditionalVoiceNoteTranscriptsStorage = Self.encoded(newValue.map { MirrorEncryption.encryptString($0) }) }
    }

    var additionalVoiceNoteLanguageCodes: [String] {
        get { Self.decodedStringArray(from: encryptedAdditionalVoiceNoteLanguageCodesStorage).map { MirrorEncryption.decryptString($0) } }
        set { encryptedAdditionalVoiceNoteLanguageCodesStorage = Self.encoded(newValue.map { MirrorEncryption.encryptString($0) }) }
    }

    var additionalVoiceNoteLanguageNames: [String] {
        get { Self.decodedStringArray(from: encryptedAdditionalVoiceNoteLanguageNamesStorage).map { MirrorEncryption.decryptString($0) } }
        set { encryptedAdditionalVoiceNoteLanguageNamesStorage = Self.encoded(newValue.map { MirrorEncryption.encryptString($0) }) }
    }

    var additionalVoiceNoteEnglishTranslations: [String] {
        get { Self.decodedStringArray(from: encryptedAdditionalVoiceNoteEnglishTranslationsStorage).map { MirrorEncryption.decryptString($0) } }
        set { encryptedAdditionalVoiceNoteEnglishTranslationsStorage = Self.encoded(newValue.map { MirrorEncryption.encryptString($0) }) }
    }

    var voiceNotes: [(data: Data, duration: Double, transcript: String?, languageCode: String?, languageName: String?, englishTranslation: String?)] {
        var notes: [(Data, Double, String?, String?, String?, String?)] = []
        if let voiceNoteData {
            notes.append((
                voiceNoteData,
                voiceNoteDuration,
                voiceNoteTranscript,
                voiceNoteLanguageCode,
                voiceNoteLanguageName,
                voiceNoteEnglishTranslation
            ))
        }
        for (index, data) in additionalVoiceNoteData.enumerated() {
            notes.append((
                data,
                additionalVoiceNoteDurations[safe: index] ?? 0,
                additionalVoiceNoteTranscripts[safe: index],
                additionalVoiceNoteLanguageCodes[safe: index],
                additionalVoiceNoteLanguageNames[safe: index],
                additionalVoiceNoteEnglishTranslations[safe: index]
            ))
        }
        return notes
    }

    var tags: [String] {
        get { Self.decodedStringArray(from: encryptedTagsStorage).map { MirrorEncryption.decryptString($0) } }
        set { encryptedTagsStorage = Self.encoded(newValue.map { MirrorEncryption.encryptString($0) }) }
    }

    var voiceNoteCount: Int {
        let primary = encryptedVoiceNoteData == nil ? 0 : 1
        guard encryptedAdditionalVoiceNoteDataStorage != nil else { return primary }
        return primary + Self.decodedDataArray(from: encryptedAdditionalVoiceNoteDataStorage).count
    }

    var hasVoiceNotes: Bool {
        voiceNoteCount > 0
    }

    var voiceNotePreview: (count: Int, duration: Double, transcript: String?) {
        guard encryptedVoiceNoteData != nil || encryptedAdditionalVoiceNoteDataStorage != nil else {
            return (0, 0, nil)
        }
        let additionalCount = Self.decodedDataArray(from: encryptedAdditionalVoiceNoteDataStorage).count
        let count = (encryptedVoiceNoteData == nil ? 0 : 1) + additionalCount
        let fallbackDuration = encryptedVoiceNoteData == nil
            ? Self.decodedDoubleArray(from: additionalVoiceNoteDurationsStorage).first ?? 0
            : voiceNoteDuration
        let primaryTranslation = voiceNoteEnglishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primaryTranscript = voiceNoteTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primaryTranslation.isEmpty || !primaryTranscript.isEmpty {
            return (count, fallbackDuration, primaryTranslation.isEmpty ? primaryTranscript : primaryTranslation)
        }

        let transcripts = additionalVoiceNoteTranscripts
        let translations = additionalVoiceNoteEnglishTranslations
        for index in 0..<max(transcripts.count, translations.count) {
            let translation = translations[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let transcript = transcripts[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !translation.isEmpty || !transcript.isEmpty {
                return (count, fallbackDuration, translation.isEmpty ? transcript : translation)
            }
        }

        return (count, fallbackDuration, nil)
    }

    init(text: String, mood: String? = nil, source: EntrySource = .typed) {
        self.id = UUID()
        self.encryptedText = MirrorEncryption.encryptString(text)
        self.encryptedTextStyleData = nil
        self.encryptedInlineStyleData = nil
        self.createdAt = Date()
        self.wordCount = strippedWordCount(text)
        self.encryptedMood = MirrorEncryption.encryptOptionalString(mood)
        self.source = source
        self.encryptedPhotoData = nil
        self.encryptedAdditionalPhotoDataStorage = nil
        self.encryptedVoiceNoteData = nil
        self.voiceNoteDuration = 0
        self.encryptedVoiceNoteTranscript = nil
        self.encryptedVoiceNoteLanguageCode = nil
        self.encryptedVoiceNoteLanguageName = nil
        self.encryptedVoiceNoteEnglishTranslation = nil
        self.encryptedAdditionalVoiceNoteDataStorage = nil
        self.additionalVoiceNoteDurationsStorage = nil
        self.encryptedAdditionalVoiceNoteTranscriptsStorage = nil
        self.encryptedAdditionalVoiceNoteLanguageCodesStorage = nil
        self.encryptedAdditionalVoiceNoteLanguageNamesStorage = nil
        self.encryptedAdditionalVoiceNoteEnglishTranslationsStorage = nil
        self.weekIdentifier = DateHelpers.weekIdentifier(for: Date())
        self.voiceNoteTranscriptionFailed = false
        self.encryptedTagsStorage = nil
    }

    private static func encoded<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decodedDataArray(from data: Data?) -> [Data] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Data].self, from: data)) ?? []
    }

    private static func decodedDoubleArray(from data: Data?) -> [Double] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
    }

    private static func decodedStringArray(from data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
