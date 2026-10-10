import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension WriteView {
    func applyTextCommand(_ command: NoteTextCommand) {
        // Delete Done removes rows, so every entry point (toolbar trash, Aa panel, Mac popover
        // menu) asks first; it can also be undone. An alert can't present over the Aa popover, so close it
        // and wait for the dismissal.
        if case .deleteCheckedItems = command {
            let panelWasOpen = showFormattingPanel
            showFormattingPanel = false
            DispatchQueue.main.asyncAfter(deadline: .now() + (panelWasOpen ? 0.35 : 0)) {
                showDeleteCheckedConfirm = true
            }
            return
        }
        sendTextCommand(command)
    }

    /// Hands a command to the editor without any confirmation step.
    func sendTextCommand(_ command: NoteTextCommand) {
        // Doesn't focus the editor: a formatting tap shouldn't pop the keyboard (this line used
        // to set `editorFocused = true`, which had no effect while it was a @FocusState).
        pendingTextCommand = command
        textCommandRevision += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Fingerprint of everything a save would write for an existing entry. Used
    /// to skip the write when the entry was only opened to read — the trimmed
    /// text is compared, so an emptied entry still differs and still saves (1.3).
    func currentContentHash() -> Int {
        var h = Hasher()
        h.combine(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines))
        h.combine(viewModel.selectedMood)
        h.combine(entryTags)
        h.combine(entryDate)
        h.combine(entryFontChoiceRaw)
        h.combine(viewModel.textStyleData)
        h.combine(inlineStyleData)
        h.combine(photoDataArray)
        h.combine(voiceNoteData)
        h.combine(voiceNoteTranscript)
        h.combine(additionalVoiceNoteData)
        h.combine(additionalVoiceNoteTranscripts)
        return h.finalize()
    }

    /// Saves and dismisses even while a voice note is still transcribing
    /// (1.4) — the in-flight pass is handed off to
    /// `continueTranscriptionAfterSaveAnyway` so it keeps running against the
    /// saved entry after this view is gone, instead of being silently
    /// abandoned or corrupting whatever comes next.
    func saveAndDismiss() {
        commitPendingTag()
        if let entry {
            // Snapshot before the handoff below clears failedTranscriptionIndexes —
            // line ~80 still needs to know what was failed *at save time* to set
            // entry.voiceNoteTranscriptionFailed correctly.
            let failedAtSave = failedTranscriptionIndexes
            // Checked before both early-return guards below: a Retry-triggered
            // transcription (voiceNoteTranscriptionFailed entry, mic re-tapped)
            // changes neither textDecryptionFailed nor currentContentHash() — the
            // transcript hasn't landed yet — so either guard would dismiss without
            // ever handing the in-flight pass off, leaving it writing into a
            // dismissed view's @State (1.4).
            if isTranscribingVoiceNotes {
                continueTranscriptionAfterSaveAnyway(for: entry, in: modelContext)
            }
            guard !entry.textDecryptionFailed, !entryContentUnreadable else {
                dismiss()
                return
            }
            // Persist only when something actually changed — including an emptied
            // entry, whose trimmed text differs from what loaded (1.3). Opening an
            // entry just to read it no longer rewrites it or dirties its CloudKit
            // record. The explicit delete path is the trash button.
            guard currentContentHash() != loadedContentHash else {
                dismiss()
                DispatchQueue.main.async { onSaveComplete?() }
                return
            }
            // Keep the edits recoverable until the save below has actually landed.
            flushDraftSave()
            editCommitted = true
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
            entry.voiceNoteTranscriptionFailed = voiceNoteData != nil && (voiceNoteTranscript?.isEmpty ?? true) && failedAtSave.contains(0)
            let moodDetection = autoDetectMoodIfNeeded(for: entry)
            // continueTranscriptionAfterSaveAnyway(for:in:) already ran above,
            // before the early-return guards — transcribingVoiceNoteIndexes is
            // empty here.
            // Defer write past dismiss so SQLite/CloudKit flush doesn't block navigation animation
            let ctx = modelContext
            let editSlot = WriteDraftStore.Slot.entry(entry.id)
            Task { @MainActor in
                do {
                    try ctx.save()
                    WriteDraftStore.clear(slot: editSlot)
                } catch {
                    // The edit draft stays; reopening the entry offers it back.
                }
                // The reflection and the alert check both read this entry's mood.
                _ = await moodDetection?.value
                await mirrorApp.runDailyNudgeIfNeeded(context: ctx)
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
                guard insertAndSave(entry) else { return }
                let moodDetection = autoDetectMoodIfNeeded(for: entry)
                if isTranscribingVoiceNotes {
                    continueTranscriptionAfterSaveAnyway(for: entry, in: modelContext)
                }
                ReviewRequestManager.requestIfEntryMilestoneReached(context: modelContext)
                let ctx = modelContext
                Task { @MainActor in
                    _ = await moodDetection?.value   // the reflection and alert check read the mood
                    // Foreground writes past the nudge hour used to sit dead until the
                    // app backgrounded/reopened — nothing else in-session re-triggers
                    // generation. Firing it here (same non-bypass gate as
                    // preGenerateInsightsIfNeeded, so the nudge-hour preference still
                    // applies) closes that gap without a second time-gate rule to keep
                    // in sync.
                    await mirrorApp.runDailyNudgeIfNeeded(context: ctx)
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

    /// Saves even while a voice note is still transcribing (1.4) — see
    /// `saveAndDismiss()`'s doc comment.
    func saveDraft() {
        commitPendingTag()
        guard entry == nil, hasDraftContent else { return }
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
        savedEntry.voiceNoteTranscriptionFailed = voiceNoteData != nil && (voiceNoteTranscript?.isEmpty ?? true) && failedTranscriptionIndexes.contains(0)
        guard insertAndSave(savedEntry) else { return }
        let moodDetection = autoDetectMoodIfNeeded(for: savedEntry)
        if isTranscribingVoiceNotes {
            continueTranscriptionAfterSaveAnyway(for: savedEntry, in: modelContext)
        }
        ReviewRequestManager.requestIfEntryMilestoneReached(context: modelContext)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ctx = modelContext
        Task { @MainActor in
            _ = await moodDetection?.value   // the reflection reads the entry's mood
            await mirrorApp.runDailyNudgeIfNeeded(context: ctx)
        }
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
        // Tags and a picked date are part of the draft too: deleting or saving it used to leave
        // the chips behind for the next entry (2026-10-09).
        entryTags = []
        tagText = ""
        showTagInput = false
        if entry == nil {
            entryDate = Date()
            entryDateChosen = false
        }
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
            entryDate: entryDate,
            entryDateChosen: entryDateChosen,
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
        entryDate = undoSnapshot.entryDate
        entryDateChosen = undoSnapshot.entryDateChosen
        voiceNoteData = undoSnapshot.voiceNoteData
        voiceNoteDuration = undoSnapshot.voiceNoteDuration
        voiceNoteTranscript = undoSnapshot.voiceNoteTranscript
        additionalVoiceNoteData = undoSnapshot.additionalVoiceNoteData
        additionalVoiceNoteDurations = undoSnapshot.additionalVoiceNoteDurations
        additionalVoiceNoteTranscripts = undoSnapshot.additionalVoiceNoteTranscripts
    }

    func deleteAndDismiss() {
        editCommitted = true
        if let entry {
            WriteDraftStore.clearIncludingPreserved(slot: .entry(entry.id))
            modelContext.delete(entry)
        }
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

    // MARK: - Draft persistence (new entries only; sealed in WriteDraftStore)

    /// Scratch journals use a different encryption key and must never read,
    /// replace or clear the user's normal draft (preferences are shared on Mac).
    static func usesPersistentDraftStorage(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        // Opt-in scratch storage (separate suite and file, see WriteDraftStore.storage).
        if arguments.contains("--scratchDraftStorage") { return true }
        return !arguments.contains("--macSnapshot") && !arguments.contains { $0.hasPrefix("--perfSeed=") }
        #else
        return true
        #endif
    }

    /// Debounced draft write. `onChange(of: viewModel.text)` fires on every
    /// keystroke and `saveDraftToStorage` encrypts the whole document + tag
    /// array each call, so writing synchronously per character is real input
    /// latency. Coalesce to one write ~1s after typing stops; background and
    /// mood changes still flush immediately.
    /// Draft content other than the text (which has its own trigger), the mood (flushed at
    /// once) and photos/voice notes (saved on their own): a change here must schedule a draft
    /// save just like typing does.
    struct DraftChangeKey: Equatable {
        var textStyleData: Data?
        var inlineStyleData: Data?
        var tags: [String]
        var entryDate: Date
        var fontChoice: String = WritingFontChoice.system.rawValue
    }

    var draftChangeKey: DraftChangeKey {
        DraftChangeKey(textStyleData: viewModel.textStyleData, inlineStyleData: inlineStyleData,
                       tags: entryTags, entryDate: entryDate, fontChoice: entryFontChoiceRaw)
    }

    /// The entry date as the date pickers set it: a pick marks the date as chosen, so a
    /// new-entry draft keeps it.
    var chosenEntryDate: Binding<Date> {
        Binding(get: { entryDate }, set: { entryDate = $0; entryDateChosen = true })
    }

    func scheduleDraftSave() {
        guard Self.usesPersistentDraftStorage(), !pendingDelete, !editCommitted else { return }
        // No content comparison here: it hashes attachments, too slow per keystroke.
        // saveEditDraft compares once the debounce settles.
        if draftSaveState != .saving { draftSaveState = .saving }
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            saveDraftToStorage()
            draftSaveTask = nil
        }
    }

    /// "Keep writing" follow-up (writing-roadmap.md 1.2). Debounced like the draft save but
    /// on a longer idle window since this triggers an on-device generation, not a cheap local
    /// write. Entirely ephemeral: nothing here touches SwiftData, the draft store, or the
    /// eventual saved Entry — only `@State` on WriteView, gone the moment the view disappears.
    func scheduleFollowUpCheck() {
        followUpTask?.cancel()
        guard followUpQuestion == nil else { return }
        let sub = SubscriptionService.shared
        guard sub.tier == .core || sub.tier == .deep else { return }
        guard LocalLLMService.isModelAvailable else { return }
        let currentWordCount = viewModel.wordCount
        guard currentWordCount >= 20 else { return }
        guard currentWordCount - followUpWordCountAtLastCheckpoint >= 20 else { return }
        let snapshot = viewModel.text
        followUpTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, snapshot == viewModel.text else { return }
            // Skip this attempt entirely rather than queue behind whatever's already running —
            // this is an ambient, opportunistic suggestion nobody explicitly asked for right
            // now, and it shouldn't add latency to a save-time mood detect, an explicit Ask, or
            // a background digest that's mid-flight. No retry: the next idle pause after more
            // typing gets another chance, same as any other missed checkpoint.
            guard await !LLMGenerationQueue.shared.isBusy else {
                followUpTask = nil
                return
            }
            guard let result = try? await InsightService.generateFollowUp(currentText: snapshot) else {
                followUpTask = nil
                return
            }
            guard !Task.isCancelled, snapshot == viewModel.text else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                followUpQuestion = result.text
                followUpEngine = result.engine
            }
            followUpWordCountAtLastCheckpoint = viewModel.wordCount
            followUpTask = nil
        }
    }

    func useFollowUpQuestion() {
        guard let followUpQuestion else { return }
        let separator = viewModel.text.isEmpty || viewModel.text.hasSuffix("\n") ? "" : "\n\n"
        viewModel.text += separator + followUpQuestion + "\n"
        // Same clamped-stale-selection bug as templates/Talk it out/scanned text (see
        // WritingTemplate.cursorOffset) — without this the caret stays wherever it was before
        // the question was appended, not at the end where the user would continue writing.
        applyTextCommand(.moveCursor(location: .max))
        dismissFollowUp()
    }

    func dismissFollowUp() {
        withAnimation(.easeOut(duration: 0.2)) {
            followUpQuestion = nil
            followUpEngine = nil
        }
        followUpWordCountAtLastCheckpoint = viewModel.wordCount
    }

    func flushDraftSave() {
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
        guard Self.usesPersistentDraftStorage() else { return }
        if let entry {
            saveEditDraft(for: entry)
            return
        }
        // A debounced write can land just after clearDraft() emptied everything
        // (the empty-text onChange schedules one more pass). Don't leave a blank
        // ciphertext blob behind that restoreDraftFromStorage would rehydrate.
        guard hasDraftContent || !entryTags.isEmpty || viewModel.selectedMood != nil else {
            clearDraftStorage()
            draftSaveState = .idle
            return
        }
        // On failure (key unavailable) the previous stored draft stays as it was.
        let saved = WriteDraftStore.save(WriteDraftStore.Payload(
            text: viewModel.text,
            textStyleData: viewModel.textStyleData,
            inlineStyleData: inlineStyleData,
            mood: viewModel.selectedMood,
            tags: entryTags,
            entryDate: entryDateChosen ? entryDate : nil,
            fontChoice: entryFontChoiceRaw
        ))
        draftSaveState = saved && attachmentsSaved ? .saved : .failed
    }

    // MARK: - Edit drafts (existing entries)

    func entryFingerprint(_ entry: Entry) -> String {
        WriteDraftStore.fingerprint(text: entry.text, mood: entry.mood, tags: entry.tags,
                                    textStyleData: entry.textStyleData, inlineStyleData: entry.inlineStyleData,
                                    createdAt: entry.createdAt)
    }

    /// Unsaved edits to an existing entry go to their own encrypted slot. They are
    /// never written into the entry by themselves; the user restores or discards
    /// them the next time the entry is opened. Text, formatting, mood, tags and
    /// date only: photo and voice-note edits are not kept.
    func saveEditDraft(for entry: Entry) {
        guard !pendingDelete, !editCommitted, !entry.textDecryptionFailed, !entryContentUnreadable,
              let base = editBaseFingerprint else { return }
        let slot = WriteDraftStore.Slot.entry(entry.id)
        guard currentContentHash() != loadedContentHash else {
            WriteDraftStore.clear(slot: slot)
            draftSaveState = .idle
            return
        }
        let saved = WriteDraftStore.save(WriteDraftStore.Payload(
            text: viewModel.text,
            textStyleData: viewModel.textStyleData,
            inlineStyleData: inlineStyleData,
            mood: viewModel.selectedMood,
            tags: entryTags,
            entryDate: entryDate,
            baseFingerprint: base,
            savedAt: Date(),
            fontChoice: entryFontChoiceRaw
        ), slot: slot)
        draftSaveState = saved ? .saved : .failed
    }

    func checkForEditDraft() {
        guard let entry, Self.usesPersistentDraftStorage(), !entry.textDecryptionFailed, !entryContentUnreadable else { return }
        editBaseFingerprint = entryFingerprint(entry)
        let slot = WriteDraftStore.Slot.entry(entry.id)
        guard case .payload(let draft) = WriteDraftStore.load(slot: slot) else { return }
        let unchanged = draft.text == viewModel.text
            && draft.mood == viewModel.selectedMood
            && draft.tags == entryTags
            && draft.textStyleData == viewModel.textStyleData
            && draft.inlineStyleData == inlineStyleData
            && (draft.entryDate ?? entryDate) == entryDate
        if unchanged {
            WriteDraftStore.clear(slot: slot)
        } else {
            pendingEditDraft = draft
        }
    }

    /// Puts the unsaved edits back in the editor. Nothing is written to the entry
    /// until the user saves.
    func restoreEditDraft(_ draft: WriteDraftStore.Payload) {
        pendingEditDraft = nil
        viewModel.text = draft.text
        viewModel.textStyleData = draft.textStyleData
        inlineStyleData = draft.inlineStyleData
        viewModel.selectedMood = draft.mood
        entryTags = draft.tags
        if let date = draft.entryDate { entryDate = date }
        if let font = draft.fontChoice { entryFontChoiceRaw = font }
        draftSaveState = .saved
    }

    func discardEditDraft() {
        pendingEditDraft = nil
        if let entry { WriteDraftStore.clear(slot: .entry(entry.id)) }
    }

    /// Inserts and saves a new entry. On failure the insert is rolled back and the
    /// draft stays in the editor and in storage.
    func insertAndSave(_ newEntry: Entry) -> Bool {
        modelContext.insert(newEntry)
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            flushDraftSave()
            entrySaveFailed = true
            return false
        }
    }

    /// Voice-note / photo blobs for a new-entry draft. Kept out of
    /// saveDraftToStorage (which runs on the debounced text path) — attachments
    /// change rarely and a voice note can be megabytes.
    func saveDraftAttachments() {
        guard entry == nil, Self.usesPersistentDraftStorage() else { return }
        let notes = draftVoiceNotes.map {
            DraftAttachmentStore.VoiceNote(
                data: $0.data,
                duration: $0.duration,
                transcript: $0.transcript,
                languageCode: $0.languageCode,
                languageName: $0.languageName,
                englishTranslation: $0.englishTranslation
            )
        }
        // Off the main thread (up to ~130 ms with five camera photos); a newer save or a
        // clear makes this result stale, so it's dropped.
        attachmentSaveGeneration &+= 1
        let generation = attachmentSaveGeneration
        DraftAttachmentStore.saveInBackground(photos: photoDataArray, voiceNotes: notes) { saved in
            guard generation == attachmentSaveGeneration else { return }
            attachmentsSaved = saved
            if !saved { draftSaveState = .failed }
        }
    }

    func restoreDraftAttachments() {
        guard entry == nil, Self.usesPersistentDraftStorage(), let restored = DraftAttachmentStore.load() else { return }
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
        guard Self.usesPersistentDraftStorage() else { return }
        restoreDraftAttachments()
        // A draft that can't be read yet (key not available, e.g. before first
        // unlock) stays in storage for a later launch; never show the fallback
        // sentinel as text or re-encrypt it over the original.
        guard case .payload(let draft) = WriteDraftStore.load() else { return }
        viewModel.text = draft.text
        viewModel.textStyleData = draft.textStyleData
        inlineStyleData = draft.inlineStyleData
        viewModel.selectedMood = draft.mood
        entryTags = draft.tags
        if let date = draft.entryDate {
            entryDate = date
            entryDateChosen = true
        }
        if let font = draft.fontChoice { entryFontChoiceRaw = font }
    }

    func clearDraftStorage() {
        cancelDraftSave()
        attachmentSaveGeneration &+= 1   // a photo save still in flight must not report afterwards
        Self.clearAllDraftStorage()      // waits for that save, then clears
        draftSaveState = .idle
        attachmentsSaved = true
    }

    func retryDraftSave() {
        if entry == nil { saveDraftAttachments() }
        flushDraftSave()
    }

    /// Static counterpart of `clearDraftStorage()` for call sites with no live
    /// `WriteView` instance (app-launch test-state reset) — same keys, no
    /// in-flight debounced-save task to cancel.
    static func clearAllDraftStorage() {
        guard usesPersistentDraftStorage() else { return }
        DraftAttachmentStore.clear()
        WriteDraftStore.clear()
    }

    /// Delete Everything while this editor is open: drop what it holds, or the
    /// next flush would write the erased draft back.
    func handleDraftsErased() {
        guard entry == nil else { return }
        cancelDraftSave()
        clearDraft()
    }

    /// Delete Everything: like `clearAllDraftStorage`, plus any draft held back
    /// because it couldn't be decrypted when found.
    static func eraseAllDraftStorage() {
        guard usesPersistentDraftStorage() else { return }
        DraftAttachmentStore.clearIncludingPreserved()
        WriteDraftStore.clearIncludingPreserved()
        WriteDraftStore.clearAllEntryDrafts()
        NotificationCenter.default.post(name: .mirrorDraftsErased, object: nil)
    }
}

struct OnDraftsErased: ViewModifier {
    let perform: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .mirrorDraftsErased)) { _ in perform() }
    }
}

enum DraftSaveState: Equatable {
    case idle, saving, saved, failed
}

/// Restore/Discard for unsaved edits from an earlier session, and the alert for a
/// new entry that could not be saved. Kept out of WriteView's body so it type-checks.
struct DraftRecoveryAlerts: ViewModifier {
    @Binding var pendingEditDraft: WriteDraftStore.Payload?
    let entryChangedSinceDraft: Bool
    @Binding var entrySaveFailed: Bool
    let restore: (WriteDraftStore.Payload) -> Void
    let discard: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Restore unsaved changes?", isPresented: Binding(
                get: { pendingEditDraft != nil },
                // Cancel (Mac) or dismissal: decide later; the draft stays stored and
                // is offered again the next time this entry is opened.
                set: { if !$0 { pendingEditDraft = nil } }
            ), presenting: pendingEditDraft) { draft in
                Button("Restore") { restore(draft) }
                Button("Discard", role: .destructive) { discard() }
            } message: { draft in
                if entryChangedSinceDraft {
                    Text("You edited this entry earlier and didn't save. It has changed since then, for example on another device. Restoring puts your earlier edits in the editor; saving would replace the newer version.")
                } else if let savedAt = draft.savedAt {
                    Text("You edited this entry on \(savedAt.formatted(date: .abbreviated, time: .shortened)) and didn't save. Restore those edits?")
                } else {
                    Text("You edited this entry earlier and didn't save. Restore those edits?")
                }
            }
            .alert("Couldn't save this entry", isPresented: $entrySaveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your writing is still here and kept as a draft on this device. Try saving again.")
            }
    }
}

/// "Saving…", "Saved on this device" or "Not saved" with Retry. About local draft
/// storage only; it never claims iCloud sync.
struct DraftSaveStatusLabel: View {
    let state: DraftSaveState
    let retry: () -> Void
    /// The iPhone header's narrow slot: "Draft saved" with a checkmark and a short "Retry";
    /// VoiceOver still hears the full wording.
    var compact = false
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            label("Saving…")
        case .saved:
            // A draft, not the entry: Save is still needed (and nothing here is iCloud).
            if compact {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                    label("Draft saved")
                }
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Draft kept on this device"))
                .accessibilityIdentifier("draft.saveStatus")
            } else {
                label("Draft kept on this device")
            }
        case .failed:
            Button(action: retry) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Not saved · Retry")
                        .lineLimit(1)
                }
                .font(displayMode == .sentinel ? MirrorTheme.mono(10, weight: .semibold) : .system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("draft.saveRetry")
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(displayMode == .sentinel ? MirrorTheme.mono(10, weight: .medium) : .system(size: 12))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .accessibilityIdentifier("draft.saveStatus")
    }
}
