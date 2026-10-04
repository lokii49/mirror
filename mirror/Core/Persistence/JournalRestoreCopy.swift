import Foundation
import SwiftData

/// Field-for-field copies used when restoring from `LocalJournalBackup`. Ciphertext is copied
/// as-is — never decrypted and re-encrypted — so a restored entry is byte-identical to the
/// backed-up one and reads under whichever key the original was sealed with.
///
/// `copiedProperties` must name every stored property; `JournalRestoreCopyTests` fails when
/// the model gains a property this file doesn't copy.
extension Entry {
    static let copiedProperties: Set<String> = [
        "id", "encryptedText", "encryptedTextStyleData", "encryptedInlineStyleData", "createdAt",
        "wordCount", "encryptedMood", "source", "encryptedPhotoData", "encryptedAdditionalPhotoDataStorage",
        "encryptedVoiceNoteData", "voiceNoteDuration", "encryptedVoiceNoteTranscript",
        "encryptedVoiceNoteLanguageCode", "encryptedVoiceNoteLanguageName",
        "encryptedVoiceNoteEnglishTranslation", "encryptedAdditionalVoiceNoteDataStorage",
        "additionalVoiceNoteDurationsStorage", "encryptedAdditionalVoiceNoteTranscriptsStorage",
        "encryptedAdditionalVoiceNoteLanguageCodesStorage", "encryptedAdditionalVoiceNoteLanguageNamesStorage",
        "encryptedAdditionalVoiceNoteEnglishTranslationsStorage", "weekIdentifier",
        "voiceNoteTranscriptionFailed", "encryptedTagsStorage", "fontChoice", "isPinned",
    ]

    static func restoredCopy(of other: Entry) -> Entry {
        let copy = Entry(text: "")
        copy.id = other.id
        copy.encryptedText = other.encryptedText
        copy.encryptedTextStyleData = other.encryptedTextStyleData
        copy.encryptedInlineStyleData = other.encryptedInlineStyleData
        copy.createdAt = other.createdAt
        copy.wordCount = other.wordCount
        copy.encryptedMood = other.encryptedMood
        copy.source = other.source
        copy.encryptedPhotoData = other.encryptedPhotoData
        copy.encryptedAdditionalPhotoDataStorage = other.encryptedAdditionalPhotoDataStorage
        copy.encryptedVoiceNoteData = other.encryptedVoiceNoteData
        copy.voiceNoteDuration = other.voiceNoteDuration
        copy.encryptedVoiceNoteTranscript = other.encryptedVoiceNoteTranscript
        copy.encryptedVoiceNoteLanguageCode = other.encryptedVoiceNoteLanguageCode
        copy.encryptedVoiceNoteLanguageName = other.encryptedVoiceNoteLanguageName
        copy.encryptedVoiceNoteEnglishTranslation = other.encryptedVoiceNoteEnglishTranslation
        copy.encryptedAdditionalVoiceNoteDataStorage = other.encryptedAdditionalVoiceNoteDataStorage
        copy.additionalVoiceNoteDurationsStorage = other.additionalVoiceNoteDurationsStorage
        copy.encryptedAdditionalVoiceNoteTranscriptsStorage = other.encryptedAdditionalVoiceNoteTranscriptsStorage
        copy.encryptedAdditionalVoiceNoteLanguageCodesStorage = other.encryptedAdditionalVoiceNoteLanguageCodesStorage
        copy.encryptedAdditionalVoiceNoteLanguageNamesStorage = other.encryptedAdditionalVoiceNoteLanguageNamesStorage
        copy.encryptedAdditionalVoiceNoteEnglishTranslationsStorage = other.encryptedAdditionalVoiceNoteEnglishTranslationsStorage
        copy.weekIdentifier = other.weekIdentifier
        copy.voiceNoteTranscriptionFailed = other.voiceNoteTranscriptionFailed
        copy.encryptedTagsStorage = other.encryptedTagsStorage
        copy.fontChoice = other.fontChoice
        copy.isPinned = other.isPinned
        return copy
    }
}

extension MoodCheckIn {
    static let copiedProperties: Set<String> = ["id", "encryptedMood", "createdAt"]

    static func restoredCopy(of other: MoodCheckIn) -> MoodCheckIn {
        let copy = MoodCheckIn(id: other.id, mood: "", createdAt: other.createdAt)
        copy.encryptedMood = other.encryptedMood
        return copy
    }
}
