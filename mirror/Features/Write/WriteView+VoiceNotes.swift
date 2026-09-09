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
        transcriptionTasks[index]?.cancel()
        transcribingVoiceNoteIndexes.insert(index)
        failedTranscriptionIndexes.remove(index)
        let preferred = transcriptionLanguage.isEmpty ? nil : transcriptionLanguage
        let task = Task {
            do {
                let result = try await VoiceTranscriptionService.transcribe(audioData: data, preferredLocaleId: preferred)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    applyTranscription(result, toVoiceNoteAt: index)
                    transcribingVoiceNoteIndexes.remove(index)
                    failedTranscriptionIndexes.remove(index)
                    transcriptionTasks[index] = nil
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    transcribingVoiceNoteIndexes.remove(index)
                    failedTranscriptionIndexes.insert(index)
                    transcriptionTasks[index] = nil
                }
            }
        }
        transcriptionTasks[index] = task
    }

    /// Cancel every in-flight transcription. Voice-note indexes are positional,
    /// so any structural change (delete) shifts them — a task that resolves
    /// against its captured index then writes its transcript onto the wrong
    /// note (and CloudKit-syncs it). Callers re-kick what still needs it.
    func cancelAllTranscriptions() {
        for task in transcriptionTasks.values { task.cancel() }
        transcriptionTasks.removeAll()
        transcribingVoiceNoteIndexes.removeAll()
        failedTranscriptionIndexes.removeAll()
    }

    /// Re-run transcription for any note that has audio but no transcript.
    /// Used after a delete reshuffles indexes, and on opening a saved entry so
    /// notes that failed (including on a build before this fix) get another
    /// pass and their Retry affordance back. Skips sub-second clips that almost
    /// certainly hold no speech, so a silent note isn't re-decoded every open.
    func rekickPendingTranscriptions() {
        for (i, note) in draftVoiceNotes.enumerated() {
            let emptyTranscript = (note.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard emptyTranscript, !note.data.isEmpty, note.duration >= 1.0 else { continue }
            guard !transcribingVoiceNoteIndexes.contains(i) else { continue }
            transcribeVoiceNote(data: note.data, index: i)
        }
    }

    func applyTranscription(_ transcription: VoiceTranscription, toVoiceNoteAt index: Int) {
        if index == 0 {
            guard voiceNoteData != nil else { return }
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
        cancelAllTranscriptions()
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
        rekickPendingTranscriptions()
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
