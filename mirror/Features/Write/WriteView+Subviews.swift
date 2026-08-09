import SwiftUI
import UIKit

private let moodLabels = MirrorTheme.moodOptions

extension WriteView {
    var dateHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 5) {
                    if displayMode == .sentinel {
                        Text(noteDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                            .font(MirrorTheme.mono(11.5, weight: .semibold))
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .kerning(0.4)
                    } else {
                        Text(noteDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
                )
                .overlay {
                    if displayMode == .sentinel {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(MirrorTheme.inkBorder, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)

            if viewModel.wordCount > 0 {
                let goalMet = viewModel.wordCount >= dailyWordGoal
                HStack(spacing: 4) {
                    Text("\(viewModel.wordCount)w")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(goalMet ? Color.green : Color(.tertiaryLabel))
                    if goalMet {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                    } else if viewModel.wordCount >= 50 {
                        Text("/ \(dailyWordGoal)w")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.wordCount)
            }

            if displayMode == .sentinel {
                HStack(spacing: 5) {
                    Circle()
                        .fill(MirrorTheme.ember)
                        .frame(width: 6, height: 6)
                        .opacity(recPulse ? 1 : 0.35)
                    Text("REC")
                        .font(MirrorTheme.mono(9.5, weight: .bold))
                        .foregroundStyle(MirrorTheme.ember)
                        .kerning(0.5)
                }
            }

            Spacer(minLength: 0)

            moodMenu
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    var moodMenu: some View {
        if displayMode == .sentinel {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.15)) { showSignalPanel.toggle() }
            } label: {
                signalLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mood")
            .accessibilityValue(viewModel.selectedMood.map { Text(MirrorTheme.localizedMoodName(for: $0)) } ?? Text("Not selected"))
        } else {
            Menu {
                Button {
                    detectMoodWithMirror()
                } label: {
                    Label(isDetectingMood ? "Detecting..." : "Mirror suggests", systemImage: "sparkles")
                }
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood)

                Divider()

                ForEach(moodLabels, id: \.self) { mood in
                    Button {
                        viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
                    } label: {
                        Label {
                            Text(MirrorTheme.localizedMoodName(for: mood))
                        } icon: {
                            Image(uiImage: moodMenuDotImage(for: mood, isSelected: viewModel.selectedMood == mood))
                                .renderingMode(.original)
                        }
                    }
                }

                if viewModel.selectedMood != nil {
                    Divider()
                    Button("Clear Mood", role: .destructive) {
                        viewModel.selectedMood = nil
                    }
                }
            } label: {
                signalLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mood")
            .accessibilityValue(viewModel.selectedMood.map { Text(MirrorTheme.localizedMoodName(for: $0)) } ?? Text("Not selected"))
        }
    }

    var signalLabel: some View {
        Group {
            HStack(spacing: 6) {
                if isDetectingMood {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 13, height: 13)
                } else {
                    if let selectedMood = viewModel.selectedMood {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: selectedMood))
                            .frame(width: 8, height: 8)
                    } else if displayMode == .sentinel {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MirrorTheme.ember)
                    }
                    Group {
                        if let selectedMood = viewModel.selectedMood {
                            Text(displayMode == .sentinel
                                 ? MirrorTheme.localizedMoodName(for: selectedMood).uppercased()
                                 : MirrorTheme.localizedMoodName(for: selectedMood))
                        } else {
                            Text(displayMode == .sentinel ? "SIGNAL" : "Mood")
                        }
                    }
                        .font(displayMode == .sentinel ? MirrorTheme.mono(11.5, weight: .semibold) : .system(size: 13, weight: .semibold))
                        .kerning(displayMode == .sentinel ? 0.4 : 0)
                        .lineLimit(1)
                        .foregroundStyle(
                            viewModel.selectedMood == nil
                                ? (displayMode == .sentinel ? MirrorTheme.ember : Color.secondary)
                                : MirrorTheme.moodColor(for: viewModel.selectedMood ?? "")
                        )
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                displayMode == .sentinel
                    ? AnyShapeStyle(viewModel.selectedMood == nil ? MirrorTheme.ember.opacity(0.10) : MirrorTheme.moodColor(for: viewModel.selectedMood ?? "").opacity(0.14))
                    : AnyShapeStyle(viewModel.selectedMood == nil && !isDetectingMood ? Color(.secondarySystemFill) : MirrorTheme.moodColor(for: viewModel.selectedMood ?? "").opacity(0.12)),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            viewModel.selectedMood == nil ? MirrorTheme.ember.opacity(0.35) : MirrorTheme.moodColor(for: viewModel.selectedMood ?? "").opacity(0.4),
                            lineWidth: 1
                        )
                }
            }
        }
    }

    /// Sentinel's replacement for the native Menu — SwiftUI's Menu can't be
    /// recolored or re-fonted (it's OS chrome), so matching the HUD look
    /// requires a custom dropdown instead. Same one-row-per-mood list as
    /// Classic's Menu (icon + name, top-to-bottom, same order), just drawn
    /// with mono/ember chrome instead of the grid layout this used to have.
    /// Dismissed by WriteView's full-screen tap-catcher overlay, or by
    /// picking an option here.
    var signalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                detectMoodWithMirror()
                withAnimation(.easeOut(duration: 0.15)) { showSignalPanel = false }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isDetectingMood ? "ANALYZING…" : "AUTO-DETECT")
                        .font(MirrorTheme.mono(11.5, weight: .bold))
                        .kerning(0.4)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MirrorTheme.ember)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood)
            .opacity(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

            Rectangle().fill(MirrorTheme.inkBorder).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(moodLabels, id: \.self) { mood in
                        let isSelected = viewModel.selectedMood == mood
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.selectedMood = isSelected ? nil : mood
                            withAnimation(.easeOut(duration: 0.15)) { showSignalPanel = false }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(MirrorTheme.moodColor(for: mood))
                                    .frame(width: 8, height: 8)
                                Text(MirrorTheme.localizedMoodName(for: mood).uppercased())
                                    .font(MirrorTheme.mono(12, weight: isSelected ? .bold : .medium))
                                    .kerning(0.3)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(MirrorTheme.moodColor(for: mood))
                                }
                            }
                            .foregroundStyle(isSelected ? MirrorTheme.textPrimary : MirrorTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isSelected ? MirrorTheme.moodColor(for: mood).opacity(0.10) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 320)

            if viewModel.selectedMood != nil {
                Rectangle().fill(MirrorTheme.inkBorder).frame(height: 1)
                Button {
                    viewModel.selectedMood = nil
                    withAnimation(.easeOut(duration: 0.15)) { showSignalPanel = false }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("CLEAR SIGNAL")
                            .font(MirrorTheme.mono(11, weight: .semibold))
                            .kerning(0.4)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 250)
        .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
    }

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        if entry != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    startDeleteWithUndo()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(pendingDelete ? (displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor)) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete entry")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(isTranscribingVoiceNotes)
                .accessibilityLabel("Save entry")
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    startDeleteWithUndo()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            pendingDelete
                                ? (displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                                : (hasDraftContent ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftContent && !pendingDelete)
                .accessibilityLabel("Discard draft")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveDraft()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            hasDraftContent
                                ? (displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.accentColor))
                                : AnyShapeStyle(Color.secondary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftContent || isTranscribingVoiceNotes)
                .accessibilityLabel("Save entry")
            }
        }
    }

    @ToolbarContentBuilder
    var focusModeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { focusMode.toggle() }
                if focusMode { editorFocused = true }
            } label: {
                Image(systemName: focusMode
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(focusMode ? "Exit focus mode" : "Focus mode")
        }
    }

    var toolRow: some View {
        VStack(spacing: 0) {
            if dailyWordGoal > 0 && viewModel.wordCount > 0 {
                let progress = min(Double(viewModel.wordCount) / Double(dailyWordGoal), 1.0)
                let isComplete = viewModel.wordCount >= dailyWordGoal
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemFill))
                        Rectangle()
                            .fill(isComplete ? Color.green : (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary))
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 2)
            }
            Divider().overlay(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.3) : MirrorTheme.inkBorder)
            HStack(spacing: 0) {
                // Keyboard dismiss
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Undo
                Button {
                    applyTextCommand(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18))
                        .foregroundStyle(canUndo ? Color.secondary : Color.secondary.opacity(0.35))
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .accessibilityLabel("Undo")

                // Redo
                Button {
                    applyTextCommand(.redo)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18))
                        .foregroundStyle(canRedo ? Color.secondary : Color.secondary.opacity(0.35))
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canRedo)
                .accessibilityLabel("Redo")

                // Formatting panel
                FormatToggleButton(panelState: panelState, isShowingPanel: showFormattingPanel) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showFormattingPanel.toggle()
                }

                Spacer(minLength: 0)

                // Checklist quick-ops — appear only when cursor is on a checklist paragraph
                let isInChecklist = activeParagraphStyle == .checklistUnchecked || activeParagraphStyle == .checklistChecked
                if isInChecklist {
                    Button {
                        applyTextCommand(.checkAllItems)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 20))
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
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete checked items")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                // Photo button
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            editorFocused = false
                            isKeyboardVisible = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showCameraPicker = true }
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }
                    }
                    Button {
                        editorFocused = false
                        isKeyboardVisible = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showPhotoPicker = true }
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: !photoDataArray.isEmpty ? "photo.fill" : "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(!photoDataArray.isEmpty ? (displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor) : .primary)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if photoDataArray.count > 1 {
                                Text("\(photoDataArray.count)")
                                    .font(displayMode == .sentinel ? MirrorTheme.mono(9, weight: .bold) : .system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor,
                                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous)) : AnyShape(Capsule())
                                    )
                                    .offset(x: 4, y: -2)
                            }
                        }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)

                // Voice button
                Button {
                    presentVoiceNoteSheet()
                } label: {
                    Image(systemName: !draftVoiceNotes.isEmpty ? "waveform.circle.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(!draftVoiceNotes.isEmpty ? (displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor) : Color.primary)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if isTranscribingVoiceNotes {
                                ProgressView()
                                    .scaleEffect(0.55)
                                    .frame(width: 16, height: 16)
                                    .background(Color(.systemBackground).opacity(0.85), in: Circle())
                                    .offset(x: 6, y: -6)
                            } else if draftVoiceNotes.count > 1 {
                                Text("\(draftVoiceNotes.count)")
                                    .font(displayMode == .sentinel ? MirrorTheme.mono(9, weight: .bold) : .system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor,
                                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous)) : AnyShape(Capsule())
                                    )
                                    .offset(x: 4, y: -2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTranscribingVoiceNotes ? "Transcribing voice note" : (!draftVoiceNotes.isEmpty ? "Voice notes" : "Add voice note"))
            }
            .animation(.easeInOut(duration: 0.15), value: activeParagraphStyle)
            .padding(.horizontal, 8)
        }
        .background(displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(.bar))
    }
}
