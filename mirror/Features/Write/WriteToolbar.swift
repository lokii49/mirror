import SwiftUI

/// WriteView's toolbar: delete/discard, Drafts, Save and the focus toggle.
///
/// On iPhone Duo all three (trash, check, focus) go to the vertical bar on the right, under the
/// status bar, instead of a horizontal top bar (owner, 2026-10-17). Elsewhere nothing moves.
/// Focus mode is the text and one way out: everything leaves but the dimmed exit glyph
/// (owner asked for the best UX, 2026-11-03). Save is one tap after exiting, and the draft
/// autosaves meanwhile.
///
/// A concrete struct so WriteView.body carries one nominal type instead of nested opaque
/// toolbar types (see `WriteView.toolbarItems`).
struct WriteToolbar: ToolbarContent {
    let isExistingEntry: Bool
    let focusMode: Bool
    let pendingDelete: Bool
    let hasDraftContent: Bool
    let takesSavedDrafts: Bool
    let saveGlyphBounces: Int
    let isSentinel: Bool
    let delete: () -> Void
    /// saveAndDismiss for an existing entry, saveDraft for a new one.
    let save: () -> Void
    let saveToDrafts: () -> Void
    let continueSavedDraft: (UUID) -> Void
    let toggleFocus: () -> Void
    /// Add Link › Link to an Entry…: hosted by the More menu so WriteView.body gains no modifier.
    var entryLinkPicker: Binding<Bool> = .constant(false)
    var linkingEntryID: UUID? = nil
    var linkToEntry: (UUID) -> Void = { _ in }
    /// Pictures (a suggestion's map and photos, a picked photo) are still being prepared: Save
    /// waits, so they land in this entry instead of being dropped or going into the next draft.
    var isAddingAttachment: Bool = false

    var body: some ToolbarContent {
        if focusMode {
            // Focus mode is the text and one way out.
            focusItem
        } else {
            entryItems
        }
    }

    @ToolbarContentBuilder
    private var entryItems: some ToolbarContent {
        // Option A (owner 2026-11-06): Drafts and a More menu on the leading side (focus mode and
        // the destructive delete/discard live in the menu, not as the bar's most prominent
        // glyph); Save as a clear text button on the trailing side.
        if !isExistingEntry && takesSavedDrafts {
            // Save to Drafts, the newest drafts to continue, All Drafts…. Only the main editor:
            // a prefilled one (widget prompt, Talk It Out) keeps its own text.
            ToolbarItem(placement: .topBarLeading) {
                WriteDraftsMenu(canSave: hasDraftContent && !pendingDelete, save: saveToDrafts,
                                resume: continueSavedDraft)
            }
            .preferringVerticalBar()
        }

        ToolbarItem(placement: .topBarLeading) {
            WriteMoreMenu(isExistingEntry: isExistingEntry,
                          canDiscard: isExistingEntry || hasDraftContent || pendingDelete,
                          pendingDelete: pendingDelete,
                          isSentinel: isSentinel,
                          toggleFocus: toggleFocus,
                          delete: delete)
                .sheet(isPresented: entryLinkPicker) {
                    EntryLinkPicker(excluding: linkingEntryID, onPick: linkToEntry)
                }
        }
        .preferringVerticalBar()

        ToolbarItem(placement: .topBarTrailing) {
            WriteSaveButton(enabled: (isExistingEntry || hasDraftContent) && !isAddingAttachment, isSentinel: isSentinel, save: save)
        }
        .preferringVerticalBar()
    }

    @ToolbarContentBuilder
    private var focusItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                toggleFocus()
            } label: {
                Image(systemName: focusMode
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .scaledFont(17, weight: .medium)
                    // Alone in the bar during focus mode, so it recedes rather than invites.
                    .foregroundStyle(focusMode ? MirrorTheme.textTertiary : MirrorTheme.textSecondary)
                    .glyphReplaceTransition()
            }
            .buttonStyle(.plain)
            // Esc leaves focus mode on a hardware keyboard; it does nothing outside it.
            .keyboardShortcut(focusMode ? KeyboardShortcut(.escape, modifiers: []) : nil)
            .accessibilityLabel(focusMode ? "Exit focus mode" : "Focus mode")
        }
        .preferringVerticalBar()
    }
}

/// The Write toolbar's More menu: focus mode, then delete (an entry) or discard (a draft). Both
/// destructive actions start the same undo countdown as the trash button did.
struct WriteMoreMenu: View {
    let isExistingEntry: Bool
    let canDiscard: Bool
    let pendingDelete: Bool
    let isSentinel: Bool
    let toggleFocus: () -> Void
    let delete: () -> Void

    var body: some View {
        Menu {
            Button(action: toggleFocus) {
                Label("Focus mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Divider()
            Button(role: .destructive, action: delete) {
                Label(isExistingEntry ? "Delete entry" : "Discard draft", systemImage: "trash")
            }
            .disabled(!canDiscard || pendingDelete)
        } label: {
            Image(systemName: "ellipsis")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(pendingDelete
                                 ? (isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                                 : AnyShapeStyle(MirrorTheme.textSecondary))
                .frame(minWidth: 30, minHeight: 30)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
        .accessibilityIdentifier("write.more")
    }
}

/// Save as words, not a glyph: filled in the accent when there's something to save, the system's
/// disabled look otherwise (enough contrast in both themes and both appearances).
struct WriteSaveButton: View {
    let enabled: Bool
    let isSentinel: Bool
    let save: () -> Void

    var body: some View {
        // Prominent only when enabled: a disabled prominent button is white on light grey in the
        // light appearance (14 Pro, 2026-11-06); the plain bordered style reads as off instead.
        if enabled {
            // White text needs the deep plum: the dark accent tint is too light under it.
            button.buttonStyle(.borderedProminent).tint(MirrorTheme.buttonFill)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: save) {
            Text("Save")
                .textCase(isSentinel ? .uppercase : nil)
                .scaledFont(isSentinel ? 13 : 16, weight: .semibold, design: isSentinel ? .monospaced : .default)
                .padding(.horizontal, 4)
        }
        .buttonBorderShape(.capsule)
        .tint(isSentinel ? MirrorTheme.ember : MirrorTheme.violet)
        // Save anyway while a voice note is still transcribing (1.4):
        // continueTranscriptionAfterSaveAnyway hands the in-flight pass off to the saved entry.
        .disabled(!enabled)
        #if os(macOS)
        .keyboardShortcut(.return, modifiers: .command)
        #endif
        .accessibilityLabel("Save entry")
        .accessibilityIdentifier("write.save")
    }
}
