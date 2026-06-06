import SwiftUI
import UIKit

extension WriteView {
    func appendVoiceNote(data: Data, duration: TimeInterval) {
        let noteIndex: Int
        if voiceNoteData == nil {
            voiceNoteData = data
            voiceNoteDuration = duration
            voiceNoteTranscript = nil
            voiceNoteLanguageCode = nil
            voiceNoteLanguageName = nil
            voiceNoteEnglishTranslation = nil
            noteIndex = 0
        } else {
            additionalVoiceNoteData.append(data)
            additionalVoiceNoteDurations.append(duration)
            additionalVoiceNoteTranscripts.append("")
            additionalVoiceNoteLanguageCodes.append("")
            additionalVoiceNoteLanguageNames.append("")
            additionalVoiceNoteEnglishTranslations.append("")
            noteIndex = additionalVoiceNoteData.count
        }
        transcribeVoiceNote(data: data, index: noteIndex)
    }

    func transcribeVoiceNote(data: Data, index: Int) {
        transcribingVoiceNoteIndexes.insert(index)
        failedTranscriptionIndexes.remove(index)
        let preferred = transcriptionLanguage.isEmpty ? nil : transcriptionLanguage
        Task {
            do {
                let result = try await VoiceTranscriptionService.transcribe(audioData: data, preferredLocaleId: preferred)
                await MainActor.run {
                    applyTranscription(result, toVoiceNoteAt: index)
                    transcribingVoiceNoteIndexes.remove(index)
                    failedTranscriptionIndexes.remove(index)
                }
            } catch {
                await MainActor.run {
                    transcribingVoiceNoteIndexes.remove(index)
                    failedTranscriptionIndexes.insert(index)
                }
            }
        }
    }

    func applyTranscription(_ transcription: VoiceTranscription, toVoiceNoteAt index: Int) {
        if index == 0 {
            voiceNoteTranscript = transcription.transcript
            voiceNoteLanguageCode = transcription.languageCode
            voiceNoteLanguageName = transcription.languageName
            voiceNoteEnglishTranslation = transcription.englishTranslation
        } else {
            let additionalIndex = index - 1
            guard additionalVoiceNoteData.indices.contains(additionalIndex) else { return }
            additionalVoiceNoteTranscripts[additionalIndex] = transcription.transcript
            additionalVoiceNoteLanguageCodes[additionalIndex] = transcription.languageCode
            additionalVoiceNoteLanguageNames[additionalIndex] = transcription.languageName
            additionalVoiceNoteEnglishTranslations[additionalIndex] = transcription.englishTranslation
        }
    }

    func removeVoiceNote(at index: Int) {
        transcribingVoiceNoteIndexes.remove(index)
        if index == 0 {
            voiceNoteData = nil
            voiceNoteDuration = 0
            voiceNoteTranscript = nil
            voiceNoteLanguageCode = nil
            voiceNoteLanguageName = nil
            voiceNoteEnglishTranslation = nil
            if !additionalVoiceNoteData.isEmpty {
                voiceNoteData = additionalVoiceNoteData.removeFirst()
                voiceNoteDuration = additionalVoiceNoteDurations.isEmpty ? 0 : additionalVoiceNoteDurations.removeFirst()
                voiceNoteTranscript = additionalVoiceNoteTranscripts.isEmpty ? nil : additionalVoiceNoteTranscripts.removeFirst()
                voiceNoteLanguageCode = additionalVoiceNoteLanguageCodes.isEmpty ? nil : additionalVoiceNoteLanguageCodes.removeFirst()
                voiceNoteLanguageName = additionalVoiceNoteLanguageNames.isEmpty ? nil : additionalVoiceNoteLanguageNames.removeFirst()
                voiceNoteEnglishTranslation = additionalVoiceNoteEnglishTranslations.isEmpty ? nil : additionalVoiceNoteEnglishTranslations.removeFirst()
            }
        } else {
            let additionalIndex = index - 1
            if additionalVoiceNoteData.indices.contains(additionalIndex) {
                additionalVoiceNoteData.remove(at: additionalIndex)
            }
            if additionalVoiceNoteDurations.indices.contains(additionalIndex) {
                additionalVoiceNoteDurations.remove(at: additionalIndex)
            }
            if additionalVoiceNoteTranscripts.indices.contains(additionalIndex) {
                additionalVoiceNoteTranscripts.remove(at: additionalIndex)
            }
            if additionalVoiceNoteLanguageCodes.indices.contains(additionalIndex) {
                additionalVoiceNoteLanguageCodes.remove(at: additionalIndex)
            }
            if additionalVoiceNoteLanguageNames.indices.contains(additionalIndex) {
                additionalVoiceNoteLanguageNames.remove(at: additionalIndex)
            }
            if additionalVoiceNoteEnglishTranslations.indices.contains(additionalIndex) {
                additionalVoiceNoteEnglishTranslations.remove(at: additionalIndex)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func presentVoiceNoteSheet() {
        editorFocused = false
        isKeyboardVisible = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showVoiceInput = true
        }
    }
}
