import Testing
import Foundation
@testable import mirror

/// Covers `WriteView.applyTranscription(_:to:atIndex:)` (1.4) — the index
/// arithmetic that writes a transcript straight onto a persisted `Entry`
/// after "save anyway" restarts the pass independent of the view. This is
/// the same index-0-vs-additional-array-offset-by-one class of bug as
/// 1.1/1.5, so it's worth pinning down directly.
struct VoiceNoteTranscriptionTests {

    private func makeEntryWithThreeAdditionalNotes() -> Entry {
        let entry = Entry(text: "body", source: .voice)
        entry.voiceNoteData = Data([0])
        entry.voiceNoteTranscript = "primary original"
        entry.additionalVoiceNoteData = [Data([1]), Data([2]), Data([3])]
        entry.additionalVoiceNoteTranscripts = ["note1 original", "note2 original", "note3 original"]
        entry.additionalVoiceNoteLanguageCodes = ["en", "en", "en"]
        entry.additionalVoiceNoteLanguageNames = ["English", "English", "English"]
        entry.additionalVoiceNoteEnglishTranslations = ["", "", ""]
        return entry
    }

    @Test func indexZeroWritesPrimaryFieldsOnly() {
        let entry = makeEntryWithThreeAdditionalNotes()
        let result = VoiceTranscription(transcript: "primary new", languageCode: "fr", languageName: "French", englishTranslation: "translated")

        WriteView.applyTranscription(result, to: entry, atIndex: 0)

        #expect(entry.voiceNoteTranscript == "primary new")
        #expect(entry.voiceNoteLanguageCode == "fr")
        #expect(entry.voiceNoteLanguageName == "French")
        #expect(entry.voiceNoteEnglishTranslation == "translated")
        #expect(entry.voiceNoteTranscriptionFailed == false)
        // Additional notes untouched.
        #expect(entry.additionalVoiceNoteTranscripts == ["note1 original", "note2 original", "note3 original"])
    }

    @Test func indexTwoPatchesOnlySlotOneOfAdditionalArrays() {
        // atIndex: 2 → additionalIndex 1 (the middle of the three additional notes).
        let entry = makeEntryWithThreeAdditionalNotes()
        let result = VoiceTranscription(transcript: "note2 new", languageCode: "de", languageName: "German", englishTranslation: "übersetzt")

        WriteView.applyTranscription(result, to: entry, atIndex: 2)

        #expect(entry.additionalVoiceNoteTranscripts == ["note1 original", "note2 new", "note3 original"])
        #expect(entry.additionalVoiceNoteLanguageCodes == ["en", "de", "en"])
        #expect(entry.additionalVoiceNoteLanguageNames == ["English", "German", "English"])
        #expect(entry.additionalVoiceNoteEnglishTranslations == ["", "übersetzt", ""])
        // Primary (index 0) and the sibling additional slots untouched.
        #expect(entry.voiceNoteTranscript == "primary original")
    }

    @Test func indexZeroWithNoPrimaryAudioIsANoOp() {
        // Guards against writing a transcript onto a note that isn't there —
        // e.g. the primary note was deleted between transcription start and
        // this write landing.
        let entry = Entry(text: "body", source: .typed)
        let result = VoiceTranscription(transcript: "stray", languageCode: "en", languageName: "English", englishTranslation: "")

        WriteView.applyTranscription(result, to: entry, atIndex: 0)

        #expect(entry.voiceNoteTranscript == nil)
    }

    @Test func outOfRangeAdditionalIndexIsANoOp() {
        let entry = makeEntryWithThreeAdditionalNotes()
        let result = VoiceTranscription(transcript: "stray", languageCode: "en", languageName: "English", englishTranslation: "")

        // atIndex: 5 → additionalIndex 4, past the 3-element arrays.
        WriteView.applyTranscription(result, to: entry, atIndex: 5)

        #expect(entry.additionalVoiceNoteTranscripts == ["note1 original", "note2 original", "note3 original"])
    }
}
