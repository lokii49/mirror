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

    var body: some ToolbarContent {
        if !focusMode {
            entryItems
        }
        focusItem
    }

    @ToolbarContentBuilder
    private var entryItems: some ToolbarContent {
        if isExistingEntry {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    delete()
                } label: {
                    Image(systemName: "trash")
                        .scaledFont(18, weight: .semibold)
                        .foregroundStyle(pendingDelete ? (isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor)) : AnyShapeStyle(.secondary))
                        // The lid lifts as the entry goes to the undo countdown.
                        .glyphBounce(whenTurnsOn: pendingDelete, byLayer: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete entry")
            }
            .preferringVerticalBar()

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(22, weight: .semibold)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                // Save anyway while a voice note is still transcribing (1.4) —
                // continueTranscriptionAfterSaveAnyway hands the in-flight pass
                // off to write straight into the saved entry once it finishes.
                #if os(macOS)
                .keyboardShortcut(.return, modifiers: .command)
                #endif
                .accessibilityLabel("Save entry")
            }
            .preferringVerticalBar()
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    delete()
                } label: {
                    Image(systemName: "trash")
                        .scaledFont(18, weight: .semibold)
                        .foregroundStyle(
                            pendingDelete
                                ? (isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                                : (hasDraftContent ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        )
                        .glyphBounce(whenTurnsOn: pendingDelete, byLayer: true)
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftContent && !pendingDelete)
                .accessibilityLabel("Discard draft")
            }
            .preferringVerticalBar()

            // Save to Drafts, the newest drafts to continue, All Drafts…. Only the main editor:
            // a prefilled one (widget prompt, Talk It Out) keeps its own text.
            if takesSavedDrafts {
                ToolbarItem(placement: .topBarLeading) {
                    WriteDraftsMenu(canSave: hasDraftContent && !pendingDelete, save: saveToDrafts,
                                    resume: continueSavedDraft)
                }
                .preferringVerticalBar()
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(22, weight: .semibold)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            hasDraftContent
                                ? (isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                                : AnyShapeStyle(Color.secondary)
                        )
                        // One bounce when the first words make the entry saveable. Driven from
                        // WriteView state a beat after the button enables: a bounce started in
                        // the same update as the enable never shows (sim recording, 2026-10-16).
                        .symbolEffect(.bounce, value: saveGlyphBounces)
                }
                .accessibilityLabel("Save entry")
                .buttonStyle(.plain)
                // Save anyway while a voice note is still transcribing (1.4) —
                // continueTranscriptionAfterSaveAnyway hands the in-flight pass
                // off to write straight into the saved entry once it finishes.
                .disabled(!hasDraftContent)
                #if os(macOS)
                .keyboardShortcut(.return, modifiers: .command)
                #endif
                .accessibilityLabel("Save entry")
            }
            .preferringVerticalBar()
        }
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
