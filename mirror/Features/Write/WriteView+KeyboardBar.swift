#if os(iOS)
import SwiftUI
import UIKit

/// The iPhone/iPad row above the keyboard, laid out like Apple Notes': one floating capsule that
/// scrolls sideways, with the Aa panel, checklist and attach menu first and the direct formatting
/// controls after them. Voice notes are recorded from the attach menu (Notes' Record Audio). Bar
/// buttons carry `keyboardBar.*` identifiers so UI tests that look up the Aa panel's "B", "I" or
/// "S" still find exactly one. Their on/off states read the Aa panel's state, the same source the
/// panel draws from, so the two always agree.
extension WriteView {
    var keyboardBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                FormatToggleButton(panelState: panelState, isShowingPanel: showFormattingPanel) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showFormattingPanel.toggle()
                }
                .frame(width: barItemWidth, height: barHeight)
                .popover(isPresented: Binding(
                    get: { showFormattingPanel && usesPopoverPanel },
                    set: { if !$0 { showFormattingPanel = false } }
                ), attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    FormattingPanelView(state: panelState, presentation: .popover)
                        .frame(minWidth: 340, idealWidth: 370, maxWidth: 390)
                        .presentationCompactAdaptation(.popover)
                        .environment(\.appDisplayMode, displayMode)
                }

                checklistButton
                attachMenu
                fontMenu

                barButton("bold", label: "Bold", id: "bold", isOn: panelState.activeInlineStyles.bold) {
                    applyTextCommand(.bold)
                }
                barButton("italic", label: "Italic", id: "italic", isOn: panelState.activeInlineStyles.italic) {
                    applyTextCommand(.italic)
                }
                barButton("underline", label: "Underline", id: "underline", isOn: panelState.activeInlineStyles.underline) {
                    applyTextCommand(.underline)
                }
                barButton("strikethrough", label: "Strikethrough", id: "strikethrough", isOn: panelState.activeInlineStyles.strikethrough) {
                    applyTextCommand(.strikethrough)
                }
                // Highlights in the swatch last picked in the Aa panel; a second tap removes it.
                barButton("highlighter", label: "Highlight", id: "highlight", isOn: panelState.activeHighlightIndex != nil) {
                    applyTextCommand(.highlight(index: panelState.activeHighlightIndex == nil ? panelState.lastHighlightIndex : nil))
                }
                barButton("link", label: "Link", id: "link", isOn: panelState.activeLinkURL != nil) {
                    panelState.onRequestLinkEditor?()
                }
                barButton("eraser", label: "Clear formatting", id: "clearFormatting", isOn: false) {
                    applyTextCommand(.clearFormatting)
                }
                barButton("decrease.indent", label: "Decrease indent", id: "indentLess", isOn: false) {
                    applyTextCommand(.indentLess)
                }
                barButton("increase.indent", label: "Increase indent", id: "indentMore", isOn: false) {
                    applyTextCommand(.indentMore)
                }
                barButton("text.quote", label: "Quote", id: "blockQuote", isOn: panelState.activeParagraphStyle == .blockQuote) {
                    applyTextCommand(.blockQuote)
                }
                barButton("list.bullet", label: "Bulleted list", id: "bulletedList", isOn: panelState.activeParagraphStyle == .bulletedList) {
                    applyTextCommand(.bulletedList)
                }
                barButton("arrow.uturn.backward", label: "Undo", id: "undo", isOn: false, isEnabled: canUndo) {
                    applyTextCommand(.undo)
                }
                barButton("arrow.uturn.forward", label: "Redo", id: "redo", isOn: false, isEnabled: canRedo) {
                    applyTextCommand(.redo)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(height: barHeight)
        .barSurface(isSentinel: displayMode == .sentinel)
        .matchedGeometryEffect(id: "barCapsule", in: barNamespace)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: panelState.activeParagraphStyle)
    }

    /// The bar while the keyboard is down, as in a Notes note: checklist, attach and record in one
    /// capsule on the left.
    var closedKeyboardBar: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 0) {
                barButton("checklist", label: "Checklist", id: "closed.checklist", isOn: false) {
                    editorFocused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { applyTextCommand(.checklist) }
                }
                .matchedGeometryEffect(id: "checklist", in: barNamespace)
                attachMenu
                barButton("waveform", label: "Record Audio", id: "closed.record", isOn: false) {
                    showRecorderSheet = true
                }
                .disabled(isTranscribingVoiceNotes)
            }
            .padding(.horizontal, 6)
            .frame(height: barHeight)
            .barSurface(isSentinel: displayMode == .sentinel)
            .matchedGeometryEffect(id: "barCapsule", in: barNamespace)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// The keyboard-up bar shows instead of the short keyboard-down one.
    var showsOpenBar: Bool {
        (isKeyboardVisible || editorFocused || toolRowAlwaysVisible) && !focusMode
    }

    private var barHeight: CGFloat { min(toolbarIconSize(48), 64) }
    private var barItemWidth: CGFloat { 58 }

    private var isInChecklist: Bool {
        panelState.activeParagraphStyle == .checklistUnchecked || panelState.activeParagraphStyle == .checklistChecked
    }

    private var barAccent: Color {
        displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor
    }

    private func barGlyph(_ systemImage: String, isOn: Bool = false, isEnabled: Bool = true) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: toolbarIconSize(20), weight: isOn ? .semibold : .regular))
            .foregroundStyle(!isEnabled ? Color.secondary.opacity(0.35) : isOn ? barAccent : Color.primary)
            .frame(width: barItemWidth, height: barHeight)
            .contentShape(Rectangle())
    }

    private func barButton(_ systemImage: String, label: LocalizedStringKey, id: String,
                           isOn: Bool, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            barGlyph(systemImage, isOn: isOn, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("keyboardBar.\(id)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One checklist button, as in Notes: a tap starts or ends a checklist, a long press offers
    /// Check All / Uncheck All / Sort Done / Delete Done. (A second icon for those, shown on
    /// checklist lines, read as a duplicate checklist button.)
    private var checklistButton: some View {
        Menu {
            Button { applyTextCommand(.checkAllItems) } label: { Label("Check All", systemImage: "checkmark.circle") }
            Button { applyTextCommand(.uncheckAllItems) } label: { Label("Uncheck All", systemImage: "circle") }
            Button { applyTextCommand(.sortCheckedToBottom) } label: { Label("Sort Done", systemImage: "arrow.down.to.line") }
            Button(role: .destructive) { applyTextCommand(.deleteCheckedItems) } label: { Label("Delete Done", systemImage: "trash") }
        } label: {
            barGlyph("checklist", isOn: isInChecklist)
        } primaryAction: {
            applyTextCommand(.checklist)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Checklist")
        .accessibilityHint("Touch and hold for checklist actions")
        .accessibilityIdentifier("keyboardBar.checklist")
        .accessibilityAddTraits(isInChecklist ? .isSelected : [])
        .matchedGeometryEffect(id: "checklist", in: barNamespace)
    }

    /// Font family for this entry's body text (Write, entry list preview, entry detail).
    private var fontMenu: some View {
        Menu {
            ForEach(WritingFontChoice.allCases) { choice in
                Button {
                    applyTextCommand(.fontFamily(choice))
                } label: {
                    if choice == panelState.activeFontChoice {
                        Label(choice.label, systemImage: "checkmark")
                    } else {
                        Text(choice.label)
                    }
                }
            }
        } label: {
            barGlyph("f.cursive")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Font")
        .accessibilityValue(Text(panelState.activeFontChoice.label))
        .accessibilityIdentifier("fontMenu")
    }

    /// Notes' paperclip menu, limited to what an entry can hold: scanned text, a photo from the
    /// camera or the library, and a voice note.
    private var attachMenu: some View {
        Menu {
            if DocumentScannerController.isSupported {
                Button {
                    presentAfterKeyboard { showDocumentScanner = true }
                } label: {
                    Label("Scan Text", systemImage: "text.viewfinder")
                }
            }
            if CameraPickerController.isAvailable {
                Button {
                    presentAfterKeyboard { showCameraPicker = true }
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button {
                presentAfterKeyboard { showPhotoPicker = true }
            } label: {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            Divider()
            // Opens the recorder sheet, as Notes' Record Audio does. A voice note is an audio
            // memo, transcribed afterwards; the keyboard's own mic key dictates into the text.
            Button {
                showRecorderSheet = true
            } label: {
                Label("Record Audio", systemImage: "waveform")
            }
            .disabled(isTranscribingVoiceNotes)
        } label: {
            barGlyph("paperclip")
                .overlay(alignment: .topTrailing) {
                    let count = photoDataArray.count + draftVoiceNotes.count
                    if count > 0 {
                        countBadge(count).padding(.top, 6).padding(.trailing, 8)
                    }
                }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("keyboardBar.attach")
        .accessibilityValue(attachAccessibilityValue)
        .matchedGeometryEffect(id: "attach", in: barNamespace)
    }

    private var attachAccessibilityValue: Text {
        let count = photoDataArray.count + draftVoiceNotes.count
        return count == 0 ? Text("") : Text("\(count) attached")
    }

    private func presentAfterKeyboard(_ present: @escaping () -> Void) {
        editorFocused = false
        isKeyboardVisible = false
        dismissKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: present)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(displayMode == .sentinel ? MirrorTheme.mono(9, weight: .bold) : .system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                barAccent,
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous)) : AnyShape(Capsule())
            )
    }
}

private extension View {
    /// Liquid Glass on iOS 26, a material capsule before it. Sentinel keeps its flat ink card with
    /// an ember hairline instead of glass.
    @ViewBuilder
    func barSurface(isSentinel: Bool) -> some View {
        if isSentinel {
            self
                .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1))
        } else if #available(iOS 26, *) {
            self
                .clipShape(Capsule())
                .glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }
}
#endif
