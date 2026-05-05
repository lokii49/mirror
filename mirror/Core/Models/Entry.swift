import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case typed, voice
}

@Model final class Entry {
    var id: UUID = UUID()
    var encryptedText: String = ""
    var createdAt: Date = Date()
    var wordCount: Int = 0
    var encryptedMood: String? = nil
    var source: EntrySource = EntrySource.typed
    var encryptedPhotoData: Data? = nil
    var encryptedVoiceNoteData: Data? = nil
    var voiceNoteDuration: Double = 0
    var encryptedVoiceNoteTranscript: String? = nil
    var encryptedVoiceNoteLanguageCode: String? = nil
    var encryptedVoiceNoteLanguageName: String? = nil
    var encryptedVoiceNoteEnglishTranslation: String? = nil
    var encryptedAdditionalVoiceNoteData: [Data] = []
    var additionalVoiceNoteDurations: [Double] = []
    var encryptedAdditionalVoiceNoteTranscripts: [String] = []
    var encryptedAdditionalVoiceNoteLanguageCodes: [String] = []
    var encryptedAdditionalVoiceNoteLanguageNames: [String] = []
    var encryptedAdditionalVoiceNoteEnglishTranslations: [String] = []
    var weekIdentifier: String = ""

    var text: String {
        get { MirrorEncryption.decryptString(encryptedText) }
        set {
            encryptedText = MirrorEncryption.encryptString(newValue)
            wordCount = newValue.split(separator: " ").count
        }
    }

    var mood: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedMood) }
        set { encryptedMood = MirrorEncryption.encryptOptionalString(newValue) }
    }

    var photoData: Data? {
        get { MirrorEncryption.decryptOptionalData(encryptedPhotoData) }
        set { encryptedPhotoData = MirrorEncryption.encryptOptionalData(newValue) }
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
        get { MirrorEncryption.decryptDataArray(encryptedAdditionalVoiceNoteData) }
        set { encryptedAdditionalVoiceNoteData = MirrorEncryption.encryptDataArray(newValue) }
    }

    var additionalVoiceNoteTranscripts: [String] {
        get { encryptedAdditionalVoiceNoteTranscripts.map(MirrorEncryption.decryptString) }
        set { encryptedAdditionalVoiceNoteTranscripts = newValue.map(MirrorEncryption.encryptString) }
    }

    var additionalVoiceNoteLanguageCodes: [String] {
        get { encryptedAdditionalVoiceNoteLanguageCodes.map(MirrorEncryption.decryptString) }
        set { encryptedAdditionalVoiceNoteLanguageCodes = newValue.map(MirrorEncryption.encryptString) }
    }

    var additionalVoiceNoteLanguageNames: [String] {
        get { encryptedAdditionalVoiceNoteLanguageNames.map(MirrorEncryption.decryptString) }
        set { encryptedAdditionalVoiceNoteLanguageNames = newValue.map(MirrorEncryption.encryptString) }
    }

    var additionalVoiceNoteEnglishTranslations: [String] {
        get { encryptedAdditionalVoiceNoteEnglishTranslations.map(MirrorEncryption.decryptString) }
        set { encryptedAdditionalVoiceNoteEnglishTranslations = newValue.map(MirrorEncryption.encryptString) }
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

    init(text: String, mood: String? = nil, source: EntrySource = .typed) {
        self.id = UUID()
        self.encryptedText = MirrorEncryption.encryptString(text)
        self.createdAt = Date()
        self.wordCount = text.split(separator: " ").count
        self.encryptedMood = MirrorEncryption.encryptOptionalString(mood)
        self.source = source
        self.encryptedPhotoData = nil
        self.encryptedVoiceNoteData = nil
        self.voiceNoteDuration = 0
        self.encryptedVoiceNoteTranscript = nil
        self.encryptedVoiceNoteLanguageCode = nil
        self.encryptedVoiceNoteLanguageName = nil
        self.encryptedVoiceNoteEnglishTranslation = nil
        self.encryptedAdditionalVoiceNoteData = []
        self.additionalVoiceNoteDurations = []
        self.encryptedAdditionalVoiceNoteTranscripts = []
        self.encryptedAdditionalVoiceNoteLanguageCodes = []
        self.encryptedAdditionalVoiceNoteLanguageNames = []
        self.encryptedAdditionalVoiceNoteEnglishTranslations = []
        self.weekIdentifier = DateHelpers.weekIdentifier(for: Date())
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
