import SwiftUI

/// Drafts: put a new entry aside, and pick one back up (`SavedDraftStore`).
extension WriteView {
    /// The main Write editor (not an existing entry, not a Mac New Entry window, not a prefilled
    /// editor) is the only one that takes drafts from Drafts.
    var takesSavedDrafts: Bool {
        entry == nil && !isStandaloneWindow && initialText.isEmpty && Self.usesPersistentDraftStorage()
    }

    /// Moves what the editor holds into Drafts and starts a blank entry.
    func saveToDrafts() {
        commitPendingTag()
        guard entry == nil, hasDraftContent, Self.usesPersistentDraftStorage() else { return }
        // Write the attachments and text now; the move below is queued after the attachment save.
        saveDraftAttachments()
        flushDraftSave()
        // Storage would hold an older version of what's on screen: keep it in the editor.
        guard draftSaveState != .failed else {
            entrySaveFailed = true
            return
        }
        guard SavedDraftStore.stash(from: newEntryDraftSlot, attachments: newEntryAttachmentLocation) != nil else { return }
        clearDraft()
        clearDraftStorage()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        savedToastIsDraft = true
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showSaved = false }
            // After the fade, or the label reads "Saved" while it disappears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { savedToastIsDraft = false }
        }
    }

    /// Write's Drafts menu > a draft: continue it here.
    func continueSavedDraft(_ id: UUID) {
        SavedDraftStore.pendingResume = id
        resumePendingSavedDraft(flushingEditor: true)
    }

    /// Drafts > Continue writing. Whatever the editor holds goes to Drafts first, then the chosen
    /// draft becomes the editor's draft. `flushingEditor` is false on first appear, when the
    /// editor shows nothing yet and its stored draft is current.
    func resumePendingSavedDraft(flushingEditor: Bool) {
        guard takesSavedDrafts, let id = SavedDraftStore.pendingResume else { return }
        SavedDraftStore.pendingResume = nil
        if flushingEditor, hasDraftContent || !entryTags.isEmpty || viewModel.selectedMood != nil {
            commitPendingTag()
            saveDraftAttachments()
            flushDraftSave()
            guard draftSaveState != .failed else {
                entrySaveFailed = true
                return
            }
        }
        cancelDraftSave()
        SavedDraftStore.stash(from: newEntryDraftSlot, attachments: newEntryAttachmentLocation)
        // A photo save still in flight must not report on the swapped-in draft.
        attachmentSaveGeneration &+= 1
        guard SavedDraftStore.moveToEditor(id, slot: newEntryDraftSlot, attachments: newEntryAttachmentLocation) else { return }
        clearDraft()
        if flushingEditor {
            restoreDraftFromStorage()
            rekickPendingTranscriptions()
            draftSaveState = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorFocused = true }
        }
    }
}
