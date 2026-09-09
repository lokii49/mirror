import SwiftUI
import SwiftData
import UIKit

extension WriteView {
    func applyTextCommand(_ command: NoteTextCommand) {
        editorFocused = true
        pendingTextCommand = command
        textCommandRevision += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func saveAndDismiss() {
        guard !isTranscribingVoiceNotes else { return }
        if let entry {
            guard !entry.textDecryptionFailed else {
                dismiss()
                return
            }
            // Always persist edits to an existing entry — including an emptied one.
            // Guarding on `hasDraftContent` silently reverted "select all, delete, save".
            // The explicit way to remove an entry is the trash button (startDeleteWithUndo).
            update(entry)
            entry.createdAt = entryDate
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: entryDate)
            entry.tags = entryTags
            entry.fontChoice = entryFontChoiceRaw
            entry.photoDataArray = photoDataArray
            entry.voiceNoteData = voiceNoteData
            entry.voiceNoteDuration = voiceNoteDuration
            entry.voiceNoteTranscript = voiceNoteTranscript
            entry.voiceNoteLanguageCode = voiceNoteLanguageCode
            entry.voiceNoteLanguageName = voiceNoteLanguageName
            entry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
            entry.additionalVoiceNoteData = additionalVoiceNoteData
            entry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
            entry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
            entry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
            entry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
            entry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
            entry.voiceNoteTranscriptionFailed = voiceNoteData != nil && (voiceNoteTranscript?.isEmpty ?? true) && failedTranscriptionIndexes.contains(0)
            autoDetectMoodIfNeeded(for: entry)
            // Defer write past dismiss so SQLite/CloudKit flush doesn't block navigation animation
            let ctx = modelContext
            Task { @MainActor in
                try? ctx.save()
                await mirrorApp.checkMoodAlertIfNeeded(context: ctx)
            }
        } else {
            if hasDraftContent {
                let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
                entry.createdAt = entryDate
                entry.weekIdentifier = DateHelpers.weekIdentifier(for: entryDate)
                entry.tags = entryTags
                entry.fontChoice = entryFontChoiceRaw
                entry.textStyleData = viewModel.textStyleData
                entry.photoDataArray = photoDataArray
                entry.inlineStyleData = inlineStyleData
                entry.wordCount = strippedWordCount(plain)
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
                entry.voiceNoteTranscript = voiceNoteTranscript
                entry.voiceNoteLanguageCode = voiceNoteLanguageCode
                entry.voiceNoteLanguageName = voiceNoteLanguageName
                entry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
                entry.additionalVoiceNoteData = additionalVoiceNoteData
                entry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
                entry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
                entry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
                entry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
                entry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
                entry.voiceNoteTranscriptionFailed = voiceNoteData != nil && (voiceNoteTranscript?.isEmpty ?? true) && failedTranscriptionIndexes.contains(0)
                modelContext.insert(entry)
                try? modelContext.save()
                autoDetectMoodIfNeeded(for: entry)
                ReviewRequestManager.requestIfEntryMilestoneReached(context: modelContext)
                let ctx = modelContext
                Task { @MainActor in
                    await mirrorApp.checkMoodAlertIfNeeded(context: ctx)
                }
                clearDraftStorage()
                withAnimation { showSaved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { showSaved = false }
                }
            }
        }
        dismiss()
        if entry != nil {
            DispatchQueue.main.async {
                onSaveComplete?()
            }
        }
    }

    func saveDraft() {
        guard entry == nil, hasDraftContent, !isTranscribingVoiceNotes else { return }
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEntry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
        savedEntry.createdAt = entryDate
        savedEntry.weekIdentifier = DateHelpers.weekIdentifier(for: entryDate)
        savedEntry.tags = entryTags
        savedEntry.fontChoice = entryFontChoiceRaw
        savedEntry.textStyleData = viewModel.textStyleData
        savedEntry.photoDataArray = photoDataArray
        savedEntry.inlineStyleData = inlineStyleData
        savedEntry.wordCount = strippedWordCount(plain)
        savedEntry.voiceNoteData = voiceNoteData
        savedEntry.voiceNoteDuration = voiceNoteDuration
        savedEntry.voiceNoteTranscript = voiceNoteTranscript
        savedEntry.voiceNoteLanguageCode = voiceNoteLanguageCode
        savedEntry.voiceNoteLanguageName = voiceNoteLanguageName
        savedEntry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
        savedEntry.additionalVoiceNoteData = additionalVoiceNoteData
        savedEntry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
        savedEntry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
        savedEntry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
        savedEntry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
        savedEntry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
        modelContext.insert(savedEntry)
        try? modelContext.save()
        autoDetectMoodIfNeeded(for: savedEntry)
        ReviewRequestManager.requestIfEntryMilestoneReached(context: modelContext)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        clearDraft()
        clearDraftStorage()
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showSaved = false }
        }
        onSaveComplete?()
    }

    func clearDraft() {
        viewModel.text = ""
        viewModel.textStyleData = nil
        viewModel.selectedMood = nil
        photoDataArray = []
        inlineStyleData = nil
        activeInlineStyles = InlineStyleSet()
        showFormattingPanel = false
        voiceNoteData = nil
        voiceNoteDuration = 0
        voiceNoteTranscript = nil
        voiceNoteLanguageCode = nil
        voiceNoteLanguageName = nil
        voiceNoteEnglishTranslation = nil
        additionalVoiceNoteData = []
        additionalVoiceNoteDurations = []
        additionalVoiceNoteTranscripts = []
        additionalVoiceNoteLanguageCodes = []
        additionalVoiceNoteLanguageNames = []
        additionalVoiceNoteEnglishTranslations = []
        cancelAllTranscriptions()
    }

    func update(_ entry: Entry) {
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = plain
        entry.textStyleData = viewModel.textStyleData
        entry.inlineStyleData = inlineStyleData
        entry.wordCount = strippedWordCount(plain)
        entry.mood = viewModel.selectedMood
        entry.source = !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func startDeleteWithUndo() {
        undoSnapshot = DraftUndoSnapshot(
            text: viewModel.text,
            textStyleData: viewModel.textStyleData,
            inlineStyleData: inlineStyleData,
            photos: photoDataArray,
            mood: viewModel.selectedMood,
            tags: entryTags,
            voiceNoteData: voiceNoteData,
            voiceNoteDuration: voiceNoteDuration,
            voiceNoteTranscript: voiceNoteTranscript,
            additionalVoiceNoteData: additionalVoiceNoteData,
            additionalVoiceNoteDurations: additionalVoiceNoteDurations,
            additionalVoiceNoteTranscripts: additionalVoiceNoteTranscripts
        )

        // Clear content immediately so the view looks empty
        clearDraft()

        deleteCountdown = 10
        withAnimation(.easeInOut(duration: 0.25)) { pendingDelete = true }
        let isExistingEntry = entry != nil
        deleteUndoTask = Task { @MainActor in
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                deleteCountdown = remaining
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { pendingDelete = false }
            if isExistingEntry {
                deleteAndDismiss()
            } else {
                clearDraftStorage()
            }
        }
    }

    func cancelPendingDelete() {
        deleteUndoTask?.cancel()
        deleteUndoTask = nil
        withAnimation(.easeInOut(duration: 0.25)) { pendingDelete = false }
        viewModel.text = undoSnapshot.text
        viewModel.textStyleData = undoSnapshot.textStyleData
        inlineStyleData = undoSnapshot.inlineStyleData
        photoDataArray = undoSnapshot.photos
        viewModel.selectedMood = undoSnapshot.mood
        entryTags = undoSnapshot.tags
        voiceNoteData = undoSnapshot.voiceNoteData
        voiceNoteDuration = undoSnapshot.voiceNoteDuration
        voiceNoteTranscript = undoSnapshot.voiceNoteTranscript
        additionalVoiceNoteData = undoSnapshot.additionalVoiceNoteData
        additionalVoiceNoteDurations = undoSnapshot.additionalVoiceNoteDurations
        additionalVoiceNoteTranscripts = undoSnapshot.additionalVoiceNoteTranscripts
    }

    func deleteAndDismiss() {
        if let entry { modelContext.delete(entry) }
        try? modelContext.save()
        dismiss()
        DispatchQueue.main.async {
            onSaveComplete?()
        }
    }

    func discardDraft() {
        clearDraft()
        clearDraftStorage()
    }

    // MARK: - Draft persistence (new entries only, text + style + mood)

    static let draftTextKey = "mirror.writeDraft.text"
    static let draftTextStyleKey = "mirror.writeDraft.textStyleData"
    static let draftInlineStyleKey = "mirror.writeDraft.inlineStyleData"
    static let draftMoodKey = "mirror.writeDraft.mood"
    static let draftTagsKey = "mirror.writeDraft.tags"

    /// Debounced draft write. `onChange(of: viewModel.text)` fires on every
    /// keystroke and `saveDraftToStorage` encrypts the whole document + tag
    /// array each call, so writing synchronously per character is real input
    /// latency. Coalesce to one write ~1s after typing stops; background and
    /// mood changes still flush immediately.
    func scheduleDraftSave() {
        guard entry == nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            saveDraftToStorage()
            draftSaveTask = nil
        }
    }

    func flushDraftSave() {
        guard entry == nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        saveDraftToStorage()
    }

    /// Drop any pending debounced write without saving — used by the clear /
    /// discard / delete paths so a straggler can't resurrect a cleared draft.
    func cancelDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
    }

    func saveDraftToStorage() {
        guard entry == nil else { return }
        // A debounced write can land just after clearDraft() emptied everything
        // (the empty-text onChange schedules one more pass). Don't leave a blank
        // ciphertext blob behind that restoreDraftFromStorage would rehydrate.
        guard hasDraftContent || !entryTags.isEmpty || viewModel.selectedMood != nil else {
            clearDraftStorage()
            return
        }
        let ud = UserDefaults.standard
        ud.set(MirrorEncryption.encryptString(viewModel.text), forKey: Self.draftTextKey)
        ud.set(viewModel.textStyleData, forKey: Self.draftTextStyleKey)
        ud.set(inlineStyleData, forKey: Self.draftInlineStyleKey)
        ud.set(viewModel.selectedMood, forKey: Self.draftMoodKey)
        let encryptedTags = entryTags.map { MirrorEncryption.encryptString($0) }
        ud.set(try? JSONEncoder().encode(encryptedTags), forKey: Self.draftTagsKey)
    }

    /// Voice-note / photo blobs for a new-entry draft. Kept out of
    /// saveDraftToStorage (which runs on the debounced text path) — attachments
    /// change rarely and a voice note can be megabytes.
    func saveDraftAttachments() {
        guard entry == nil else { return }
        let notes = draftVoiceNotes.map {
            DraftAttachmentStore.VoiceNote(
                data: $0.data,
                duration: $0.duration,
                transcript: $0.transcript,
                languageCode: nil,
                languageName: $0.languageName,
                englishTranslation: $0.englishTranslation
            )
        }
        DraftAttachmentStore.save(photos: photoDataArray, voiceNotes: notes)
    }

    func restoreDraftAttachments() {
        guard entry == nil, let restored = DraftAttachmentStore.load() else { return }
        if photoDataArray.isEmpty, !restored.photos.isEmpty {
            photoDataArray = restored.photos
        }
        guard voiceNoteData == nil, additionalVoiceNoteData.isEmpty,
              let first = restored.voiceNotes.first else { return }
        voiceNoteData = first.data
        voiceNoteDuration = first.duration
        voiceNoteTranscript = first.transcript
        voiceNoteLanguageCode = first.languageCode
        voiceNoteLanguageName = first.languageName
        voiceNoteEnglishTranslation = first.englishTranslation
        for note in restored.voiceNotes.dropFirst() {
            additionalVoiceNoteData.append(note.data)
            additionalVoiceNoteDurations.append(note.duration)
            additionalVoiceNoteTranscripts.append(note.transcript ?? "")
            additionalVoiceNoteLanguageCodes.append(note.languageCode ?? "")
            additionalVoiceNoteLanguageNames.append(note.languageName ?? "")
            additionalVoiceNoteEnglishTranslations.append(note.englishTranslation ?? "")
        }
    }

    func restoreDraftFromStorage() {
        restoreDraftAttachments()
        let ud = UserDefaults.standard
        let saved = ud.string(forKey: Self.draftTextKey) ?? ""
        guard !saved.isEmpty else { return }
        // Key may be transiently unreadable (e.g. before first unlock). Leave the
        // stored ciphertext untouched and retry on a later launch rather than
        // surfacing the fallback sentinel as real text and re-encrypting it over
        // the original draft.
        guard let decrypted = MirrorEncryption.decryptOptionalStringValue(saved) else { return }
        viewModel.text = decrypted
        viewModel.textStyleData = ud.data(forKey: Self.draftTextStyleKey)
        inlineStyleData = ud.data(forKey: Self.draftInlineStyleKey)
        viewModel.selectedMood = ud.string(forKey: Self.draftMoodKey)
        if let tagsData = ud.data(forKey: Self.draftTagsKey) {
            let encrypted = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
            entryTags = encrypted.map { MirrorEncryption.decryptString($0) }
        }
    }

    func clearDraftStorage() {
        cancelDraftSave()
        DraftAttachmentStore.clear()
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.draftTextKey)
        ud.removeObject(forKey: Self.draftTextStyleKey)
        ud.removeObject(forKey: Self.draftInlineStyleKey)
        ud.removeObject(forKey: Self.draftMoodKey)
        ud.removeObject(forKey: Self.draftTagsKey)
    }
}
