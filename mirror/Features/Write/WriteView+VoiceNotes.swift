import SwiftUI
import SwiftData
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
        if entry == nil { saveDraftAttachments() }
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

    /// Re-run transcription for any note that has audio but no transcript. Used
    /// for a restored draft (audio persists, transcripts don't) and after a
    /// delete that cancelled an in-flight pass. NOT called on opening a saved
    /// entry — that would set isTranscribingVoiceNotes and disable Save every
    /// time. Skips sub-second clips that almost certainly hold no speech.
    func rekickPendingTranscriptions() {
        for (i, note) in draftVoiceNotes.enumerated() {
            let emptyTranscript = (note.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard emptyTranscript, !note.data.isEmpty, note.duration >= 1.0 else { continue }
            guard !transcribingVoiceNoteIndexes.contains(i) else { continue }
            transcribeVoiceNote(data: note.data, index: i)
        }
    }

    /// Mark every note that has audio but no transcript as needing a retry, so
    /// its Retry button and "AI won't reflect on this" notice appear. Used on
    /// opening a saved entry — previously only the first note's failure was
    /// tracked, so additional failed notes showed nothing and were silently
    /// dropped from insightContext.
    func markPendingNotesForRetry() {
        for (i, note) in draftVoiceNotes.enumerated() {
            let emptyTranscript = (note.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard emptyTranscript, !note.data.isEmpty, note.duration >= 1.0 else { continue }
            failedTranscriptionIndexes.insert(i)
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
        // Not re-persisting the draft here: a transcript completion would rewrite
        // every (multi-MB) audio blob. The draft keeps the audio; a restored
        // draft re-decodes anything still missing a transcript.
    }

    // MARK: - Save anyway while transcribing (1.4)

    /// "Save anyway" while a voice note is still transcribing: the in-flight
    /// pass writes into `applyTranscription(_:toVoiceNoteAt:)`, which targets
    /// this view's own `@State` — but the view is about to dismiss (existing
    /// entry) or reset for a fresh draft (new entry), so that write would
    /// land nowhere anyone reads, or worse, land on whatever a *new* draft's
    /// note ends up at the same index (same corruption class as 1.1/1.5).
    /// Cancels the `@State`-bound tasks and restarts the transcription from
    /// scratch as self-contained tasks that capture `savedEntry` + `context`
    /// directly, independent of anything this view does next — not a
    /// hand-off of the in-flight pass itself, which is discarded.
    /// `VoiceTranscriptionService` serializes passes behind its own
    /// semaphore, so this costs at most one extra ~25s-capped pass.
    func continueTranscriptionAfterSaveAnyway(for savedEntry: Entry, in context: ModelContext) {
        for index in transcribingVoiceNoteIndexes {
            guard draftVoiceNotes.indices.contains(index) else { continue }
            let data = draftVoiceNotes[index].data
            transcriptionTasks[index]?.cancel()
            let preferred = transcriptionLanguage.isEmpty ? nil : transcriptionLanguage
            Task {
                do {
                    let result = try await VoiceTranscriptionService.transcribe(audioData: data, preferredLocaleId: preferred)
                    await MainActor.run {
                        WriteView.applyTranscription(result, to: savedEntry, atIndex: index)
                        try? context.save()
                    }
                } catch {
                    await MainActor.run {
                        if index == 0, savedEntry.voiceNoteData != nil {
                            savedEntry.voiceNoteTranscriptionFailed = true
                            try? context.save()
                        }
                        // Additional-note failure isn't a stored flag (matches the
                        // live path) — markPendingNotesForRetry() infers it from an
                        // empty transcript + present audio the next time this
                        // entry is opened.
                    }
                }
            }
        }
        // These tasks are now self-contained — stop tracking them against
        // this view's state so a fresh draft starts with a clean slate.
        transcribingVoiceNoteIndexes.removeAll()
        transcriptionTasks.removeAll()
        failedTranscriptionIndexes.removeAll()
    }

    /// `applyTranscription(_:toVoiceNoteAt:)`'s counterpart for a note whose
    /// transcription outlived this view — writes straight to the persisted
    /// `Entry` instead of `@State`. `static` (reads no `self`): keeps the
    /// detached `Task` above from implicitly capturing the view, and makes
    /// the index arithmetic unit-testable without a mic or a live `WriteView`.
    static func applyTranscription(_ transcription: VoiceTranscription, to entry: Entry, atIndex index: Int) {
        if index == 0 {
            guard entry.voiceNoteData != nil else { return }
            entry.voiceNoteTranscript = transcription.transcript
            entry.voiceNoteLanguageCode = transcription.languageCode
            entry.voiceNoteLanguageName = transcription.languageName
            entry.voiceNoteEnglishTranslation = transcription.englishTranslation
            entry.voiceNoteTranscriptionFailed = false
        } else {
            let additionalIndex = index - 1
            var transcripts = entry.additionalVoiceNoteTranscripts
            var codes = entry.additionalVoiceNoteLanguageCodes
            var names = entry.additionalVoiceNoteLanguageNames
            var translations = entry.additionalVoiceNoteEnglishTranslations
            guard transcripts.indices.contains(additionalIndex) else { return }
            transcripts[additionalIndex] = transcription.transcript
            if codes.indices.contains(additionalIndex) { codes[additionalIndex] = transcription.languageCode }
            if names.indices.contains(additionalIndex) { names[additionalIndex] = transcription.languageName }
            if translations.indices.contains(additionalIndex) { translations[additionalIndex] = transcription.englishTranslation }
            entry.additionalVoiceNoteTranscripts = transcripts
            entry.additionalVoiceNoteLanguageCodes = codes
            entry.additionalVoiceNoteLanguageNames = names
            entry.additionalVoiceNoteEnglishTranslations = translations
        }
    }

    func removeVoiceNote(at index: Int) {
        // Indexes are positional and about to shift; every in-flight pass is
        // keyed to a stale one. Cancel them all, then resume decoding only if
        // something was actually running — otherwise just restore Retry state.
        let hadTranscriptionInFlight = !transcribingVoiceNoteIndexes.isEmpty
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
        if hadTranscriptionInFlight {
            rekickPendingTranscriptions()
        } else {
            markPendingNotesForRetry()
        }
        if entry == nil { saveDraftAttachments() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Inline recording (no modal — keyboard and caret stay put, à la Notes)

    func toggleInlineRecording() {
        if isRecordingInline {
            finishInlineRecording()
        } else {
            startInlineRecording()
        }
    }

    func startInlineRecording() {
        Task { @MainActor in
            let granted = await voiceRecorder.requestPermission()
            guard granted else {
                withAnimation { recordingPermissionDenied = true }
                return
            }
            recordingPermissionDenied = false
            voiceRecorder.startRecording()
            guard voiceRecorder.isRecording else { return }
            withAnimation(.easeOut(duration: 0.2)) { isRecordingInline = true }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    func finishInlineRecording() {
        guard isRecordingInline else { return }
        withAnimation(.easeOut(duration: 0.2)) { isRecordingInline = false }
        if voiceRecorder.isRecording { voiceRecorder.stopRecording() }
        if let data = voiceRecorder.recordingData, voiceRecorder.duration >= 0.5 {
            appendVoiceNote(data: data, duration: voiceRecorder.duration)
        } else {
            voiceRecorder.discardRecording()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func cancelInlineRecording() {
        withAnimation(.easeOut(duration: 0.2)) { isRecordingInline = false }
        voiceRecorder.discardRecording()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
