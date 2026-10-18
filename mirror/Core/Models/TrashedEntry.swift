import Foundation
import SwiftData

/// An entry in Recently Deleted. Deleting moves the entry here and removes the `Entry`, so
/// insights, Ask, widgets and older app versions (which don't know this type) never see it.
///
/// Every stored `Entry` field is copied as it is stored: ciphertext stays ciphertext, so an
/// entry this device can't decrypt can still be deleted and restored, and nothing is ever
/// re-encrypted under a different key. `TrashedEntryTests` fails when `Entry` gains a field
/// this type doesn't have.
///
/// CloudKit rules as for `JournalCollection`: every property has a default, no unique
/// attributes, no relationships. Two devices deleting the same entry can leave two rows with
/// the same `entryID`; restore and delete handle every row for an id.
@Model final class TrashedEntry {
    /// Its own record id; the entry's is `entryID`.
    var id: UUID = UUID()
    var entryID: UUID = UUID()
    var deletedAt: Date = Date()

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
    var fontChoice: String? = nil
    var isPinned: Bool = false
    var collectionID: UUID? = nil

    init(copying entry: Entry, deletedAt: Date = Date()) {
        self.id = UUID()
        self.entryID = entry.id
        self.deletedAt = deletedAt
        encryptedText = entry.encryptedText
        encryptedTextStyleData = entry.encryptedTextStyleData
        encryptedInlineStyleData = entry.encryptedInlineStyleData
        createdAt = entry.createdAt
        wordCount = entry.wordCount
        encryptedMood = entry.encryptedMood
        source = entry.source
        encryptedPhotoData = entry.encryptedPhotoData
        encryptedAdditionalPhotoDataStorage = entry.encryptedAdditionalPhotoDataStorage
        encryptedVoiceNoteData = entry.encryptedVoiceNoteData
        voiceNoteDuration = entry.voiceNoteDuration
        encryptedVoiceNoteTranscript = entry.encryptedVoiceNoteTranscript
        encryptedVoiceNoteLanguageCode = entry.encryptedVoiceNoteLanguageCode
        encryptedVoiceNoteLanguageName = entry.encryptedVoiceNoteLanguageName
        encryptedVoiceNoteEnglishTranslation = entry.encryptedVoiceNoteEnglishTranslation
        encryptedAdditionalVoiceNoteDataStorage = entry.encryptedAdditionalVoiceNoteDataStorage
        additionalVoiceNoteDurationsStorage = entry.additionalVoiceNoteDurationsStorage
        encryptedAdditionalVoiceNoteTranscriptsStorage = entry.encryptedAdditionalVoiceNoteTranscriptsStorage
        encryptedAdditionalVoiceNoteLanguageCodesStorage = entry.encryptedAdditionalVoiceNoteLanguageCodesStorage
        encryptedAdditionalVoiceNoteLanguageNamesStorage = entry.encryptedAdditionalVoiceNoteLanguageNamesStorage
        encryptedAdditionalVoiceNoteEnglishTranslationsStorage = entry.encryptedAdditionalVoiceNoteEnglishTranslationsStorage
        weekIdentifier = entry.weekIdentifier
        voiceNoteTranscriptionFailed = entry.voiceNoteTranscriptionFailed
        encryptedTagsStorage = entry.encryptedTagsStorage
        fontChoice = entry.fontChoice
        isPinned = entry.isPinned
        collectionID = entry.collectionID
    }

    /// A new `Entry` with the original id and every stored field as it was.
    func restoredEntry() -> Entry {
        let entry = Entry(text: "")
        entry.id = entryID
        entry.encryptedText = encryptedText
        entry.encryptedTextStyleData = encryptedTextStyleData
        entry.encryptedInlineStyleData = encryptedInlineStyleData
        entry.createdAt = createdAt
        entry.wordCount = wordCount
        entry.encryptedMood = encryptedMood
        entry.source = source
        entry.encryptedPhotoData = encryptedPhotoData
        entry.encryptedAdditionalPhotoDataStorage = encryptedAdditionalPhotoDataStorage
        entry.encryptedVoiceNoteData = encryptedVoiceNoteData
        entry.voiceNoteDuration = voiceNoteDuration
        entry.encryptedVoiceNoteTranscript = encryptedVoiceNoteTranscript
        entry.encryptedVoiceNoteLanguageCode = encryptedVoiceNoteLanguageCode
        entry.encryptedVoiceNoteLanguageName = encryptedVoiceNoteLanguageName
        entry.encryptedVoiceNoteEnglishTranslation = encryptedVoiceNoteEnglishTranslation
        entry.encryptedAdditionalVoiceNoteDataStorage = encryptedAdditionalVoiceNoteDataStorage
        entry.additionalVoiceNoteDurationsStorage = additionalVoiceNoteDurationsStorage
        entry.encryptedAdditionalVoiceNoteTranscriptsStorage = encryptedAdditionalVoiceNoteTranscriptsStorage
        entry.encryptedAdditionalVoiceNoteLanguageCodesStorage = encryptedAdditionalVoiceNoteLanguageCodesStorage
        entry.encryptedAdditionalVoiceNoteLanguageNamesStorage = encryptedAdditionalVoiceNoteLanguageNamesStorage
        entry.encryptedAdditionalVoiceNoteEnglishTranslationsStorage = encryptedAdditionalVoiceNoteEnglishTranslationsStorage
        entry.weekIdentifier = weekIdentifier
        entry.voiceNoteTranscriptionFailed = voiceNoteTranscriptionFailed
        entry.encryptedTagsStorage = encryptedTagsStorage
        entry.fontChoice = fontChoice
        entry.isPinned = isPinned
        entry.collectionID = collectionID
        return entry
    }

    /// The text for the Recently Deleted row; nil when this device can't decrypt it.
    var decryptedText: String? {
        MirrorEncryption.decryptOptionalStringValue(encryptedText)
    }

    var hasPhoto: Bool { encryptedPhotoData != nil }
    var hasVoiceNote: Bool { encryptedVoiceNoteData != nil }
}
