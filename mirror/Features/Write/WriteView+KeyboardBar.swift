#if os(iOS)
import SwiftUI
import UIKit

/// The iPhone/iPad row above the keyboard, shaped like Apple Notes': one floating capsule that
/// scrolls sideways, with the Aa panel, checklist and attach menu first and the direct
/// formatting toggles after them. Voice and hide-keyboard sit in a second capsule outside the
/// scroll so they never scroll away. Bar buttons carry `keyboardBar.*` identifiers so UI tests that look up the Aa
/// panel's "B", "I", "S" or "checklist" buttons still find exactly one.
extension WriteView {
    var keyboardBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    FormatToggleButton(panelState: panelState, isShowingPanel: showFormattingPanel) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showFormattingPanel.toggle()
                    }
                    .popover(isPresented: Binding(
                        get: { showFormattingPanel && usesPopoverPanel },
                        set: { if !$0 { showFormattingPanel = false } }
                    ), attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                        FormattingPanelView(state: panelState, presentation: .popover)
                            .frame(minWidth: 320, idealWidth: 360, maxWidth: 380, minHeight: 320)
                            .presentationCompactAdaptation(.popover)
                            .environment(\.appDisplayMode, displayMode)
                    }

                    barToggle("checklist", label: "Checklist", id: "checklist", isOn: isInChecklist) {
                        applyTextCommand(.checklist)
                    }
                    attachMenu

                    if isInChecklist {
                        checklistQuickOps
                    }

                    barDivider

                    barToggle("bold", label: "Bold", id: "bold", isOn: activeInlineStyles.bold) {
                        applyTextCommand(.bold)
                    }
                    barToggle("italic", label: "Italic", id: "italic", isOn: activeInlineStyles.italic) {
                        applyTextCommand(.italic)
                    }
                    barToggle("underline", label: "Underline", id: "underline", isOn: activeInlineStyles.underline) {
                        applyTextCommand(.underline)
                    }
                    barToggle("strikethrough", label: "Strikethrough", id: "strikethrough", isOn: activeInlineStyles.strikethrough) {
                        applyTextCommand(.strikethrough)
                    }
                    // One tap highlights in the first swatch, a second tap removes it; the other
                    // swatches stay in the Aa panel.
                    barToggle("highlighter", label: "Highlight", id: "highlight", isOn: panelState.activeHighlightIndex != nil) {
                        applyTextCommand(.highlight(index: panelState.activeHighlightIndex == nil ? 0 : nil))
                    }
                    barToggle("link", label: "Link", id: "link", isOn: panelState.activeLinkURL != nil) {
                        panelState.onRequestLinkEditor?()
                    }

                    barDivider

                    barToggle("list.bullet", label: "Bulleted list", id: "bulletedList", isOn: activeParagraphStyle == .bulletedList) {
                        applyTextCommand(.bulletedList)
                    }
                    barToggle("decrease.indent", label: "Decrease indent", id: "indentLess", isOn: false) {
                        applyTextCommand(.indentLess)
                    }
                    barToggle("increase.indent", label: "Increase indent", id: "indentMore", isOn: false) {
                        applyTextCommand(.indentMore)
                    }
                    barToggle("text.quote", label: "Quote", id: "blockQuote", isOn: activeParagraphStyle == .blockQuote) {
                        applyTextCommand(.blockQuote)
                    }

                    barDivider

                    barToggle("arrow.uturn.backward", label: "Undo", id: "undo", isOn: false, isEnabled: canUndo) {
                        applyTextCommand(.undo)
                    }
                    barToggle("arrow.uturn.forward", label: "Redo", id: "redo", isOn: false, isEnabled: canRedo) {
                        applyTextCommand(.redo)
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .barSurface(isSentinel: displayMode == .sentinel, shape: barShape)
            .overlay(alignment: .bottom) { wordGoalProgress.padding(.horizontal, 18) }

            // Kept out of the scroll view: there the mic's tap gesture lost to the scroll's pan
            // and a tap never started a recording.
            HStack(spacing: 0) {
                voiceButton
                Button {
                    dismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: toolbarIconSize(18)))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide keyboard")
            }
            .padding(.horizontal, 4)
            .barSurface(isSentinel: displayMode == .sentinel, shape: barShape)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: activeParagraphStyle)
        .animation(.easeInOut(duration: 0.15), value: isRecordingInline)
    }

    private var isInChecklist: Bool {
        activeParagraphStyle == .checklistUnchecked || activeParagraphStyle == .checklistChecked
    }

    private var barShape: AnyShape {
        displayMode == .sentinel
            ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            : AnyShape(Capsule())
    }

    private var barAccent: Color {
        displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor
    }

    private var barDivider: some View {
        Rectangle()
            .fill(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.3) : Color.secondary.opacity(0.25))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    /// The daily word goal, drawn as a hairline along the bottom of the capsule.
    @ViewBuilder
    private var wordGoalProgress: some View {
        if dailyWordGoal > 0 && viewModel.wordCount > 0 {
            let progress = min(Double(viewModel.wordCount) / Double(dailyWordGoal), 1.0)
            let isComplete = viewModel.wordCount >= dailyWordGoal
            GeometryReader { geo in
                Capsule()
                    .fill(isComplete ? MirrorTheme.green : barAccent)
                    .frame(width: geo.size.width * progress)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
            }
            .frame(height: 2)
            .accessibilityHidden(true)
        }
    }

    private func barToggle(_ systemImage: String, label: LocalizedStringKey, id: String,
                           isOn: Bool, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: toolbarIconSize(17), weight: isOn ? .semibold : .regular))
                .foregroundStyle(!isEnabled ? Color.secondary.opacity(0.35) : isOn ? barAccent : Color.primary)
                .frame(width: 40, height: 44)
                .background {
                    if isOn {
                        barShape.fill(barAccent.opacity(0.14)).padding(.vertical, 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("keyboardBar.\(id)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var checklistQuickOps: some View {
        Button {
            applyTextCommand(.checkAllItems)
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: toolbarIconSize(18)))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Check all items")
        .transition(.opacity.combined(with: .scale(scale: 0.8)))

        Button {
            applyTextCommand(.deleteCheckedItems)
        } label: {
            Image(systemName: "trash.circle")
                .font(.system(size: toolbarIconSize(18)))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete checked items")
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    /// Notes' paperclip menu, limited to what an entry can hold: scanned text, a photo from the
    /// camera or the library. Voice has its own button next to it.
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
                    Label("Camera", systemImage: "camera")
                }
            }
            Button {
                presentAfterKeyboard { showPhotoPicker = true }
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: toolbarIconSize(17)))
                .foregroundStyle(!photoDataArray.isEmpty ? barAccent : .primary)
                .frame(width: 40, height: 44)
                .overlay(alignment: .topTrailing) {
                    if !photoDataArray.isEmpty {
                        countBadge(photoDataArray.count)
                    }
                }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Add photo")
        .accessibilityValue(photoDataArray.isEmpty ? Text("") : Text("\(photoDataArray.count) attached"))
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
            .offset(x: 2, y: 4)
    }

    /// Records inline; keyboard and caret stay put. A plain view with tap and long-press
    /// gestures, not a Button: a Button's tap still fires alongside a long-press, which would
    /// start a recording behind the hint popover (audit 2.3).
    private var voiceButton: some View {
        Image(systemName: iconForVoiceButton)
            .font(.system(size: toolbarIconSize(17)))
            .foregroundStyle(
                isRecordingInline ? Color.red
                    : (!draftVoiceNotes.isEmpty ? barAccent : Color.primary)
            )
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if isTranscribingVoiceNotes {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 16, height: 16)
                        .background(Color(.systemBackground).opacity(0.85), in: Circle())
                        .offset(x: 2, y: 2)
                } else if draftVoiceNotes.count > 1 {
                    countBadge(draftVoiceNotes.count)
                }
            }
            .onTapGesture {
                toggleInlineRecording()
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showVoiceButtonHint = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(voiceButtonAccessibilityLabel)
            // VoiceOver has no long-press gesture — this is the only way
            // a VoiceOver user reaches the same explanation (audit 2.3).
            .accessibilityAction(named: Text("What this does")) {
                showVoiceButtonHint = true
            }
            .popover(isPresented: $showVoiceButtonHint) {
                voiceButtonHintContent
                    .presentationCompactAdaptation(.popover)
            }
    }
}

private extension View {
    /// Liquid Glass on iOS 26, a material capsule before it. Sentinel keeps its flat ink card with
    /// an ember hairline instead of glass.
    @ViewBuilder
    func barSurface(isSentinel: Bool, shape: AnyShape) -> some View {
        if isSentinel {
            self
                .background(MirrorTheme.inkMid, in: shape)
                .overlay(shape.stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1))
        } else if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }
}
#endif
