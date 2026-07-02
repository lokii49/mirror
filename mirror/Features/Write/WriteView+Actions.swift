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
            if hasDraftContent {
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
        transcribingVoiceNoteIndexes = []
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

    func saveDraftToStorage() {
        let ud = UserDefaults.standard
        ud.set(MirrorEncryption.encryptString(viewModel.text), forKey: Self.draftTextKey)
        ud.set(viewModel.textStyleData, forKey: Self.draftTextStyleKey)
        ud.set(inlineStyleData, forKey: Self.draftInlineStyleKey)
        ud.set(viewModel.selectedMood, forKey: Self.draftMoodKey)
        let encryptedTags = entryTags.map { MirrorEncryption.encryptString($0) }
        ud.set(try? JSONEncoder().encode(encryptedTags), forKey: Self.draftTagsKey)
    }

    func restoreDraftFromStorage() {
        let ud = UserDefaults.standard
        let saved = ud.string(forKey: Self.draftTextKey) ?? ""
        guard !saved.isEmpty else { return }
        viewModel.text = MirrorEncryption.decryptString(saved)
        viewModel.textStyleData = ud.data(forKey: Self.draftTextStyleKey)
        inlineStyleData = ud.data(forKey: Self.draftInlineStyleKey)
        viewModel.selectedMood = ud.string(forKey: Self.draftMoodKey)
        if let tagsData = ud.data(forKey: Self.draftTagsKey) {
            let encrypted = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
            entryTags = encrypted.map { MirrorEncryption.decryptString($0) }
        }
    }

    func clearDraftStorage() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.draftTextKey)
        ud.removeObject(forKey: Self.draftTextStyleKey)
        ud.removeObject(forKey: Self.draftInlineStyleKey)
        ud.removeObject(forKey: Self.draftMoodKey)
        ud.removeObject(forKey: Self.draftTagsKey)
    }
}
