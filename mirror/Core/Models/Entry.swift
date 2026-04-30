import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case typed, voice
}

@Model final class Entry {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var wordCount: Int = 0
    var mood: String? = nil
    var source: EntrySource = EntrySource.typed
    var photoData: Data? = nil  // one photo, stored as data
    var voiceNoteData: Data? = nil
    var voiceNoteDuration: Double = 0
    var voiceNoteTranscript: String? = nil
    var voiceNoteLanguageCode: String? = nil
    var voiceNoteLanguageName: String? = nil
    var voiceNoteEnglishTranslation: String? = nil
    var additionalVoiceNoteData: [Data] = []
    var additionalVoiceNoteDurations: [Double] = []
    var additionalVoiceNoteTranscripts: [String] = []
    var additionalVoiceNoteLanguageCodes: [String] = []
    var additionalVoiceNoteLanguageNames: [String] = []
    var additionalVoiceNoteEnglishTranslations: [String] = []
    var weekIdentifier: String = ""

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
        self.text = text
        self.createdAt = Date()
        self.wordCount = text.split(separator: " ").count
        self.mood = mood
        self.source = source
        self.photoData = nil
        self.voiceNoteData = nil
        self.voiceNoteDuration = 0
        self.voiceNoteTranscript = nil
        self.voiceNoteLanguageCode = nil
        self.voiceNoteLanguageName = nil
        self.voiceNoteEnglishTranslation = nil
        self.additionalVoiceNoteData = []
        self.additionalVoiceNoteDurations = []
        self.additionalVoiceNoteTranscripts = []
        self.additionalVoiceNoteLanguageCodes = []
        self.additionalVoiceNoteLanguageNames = []
        self.additionalVoiceNoteEnglishTranslations = []
        self.weekIdentifier = DateHelpers.weekIdentifier(for: Date())
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
