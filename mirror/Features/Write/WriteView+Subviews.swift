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
                    Text(noteDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
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

            Spacer(minLength: 0)

            moodMenu
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    var moodMenu: some View {
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
                        Text(mood)
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
                    }
                    Text(viewModel.selectedMood ?? "Mood")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(viewModel.selectedMood == nil ? .secondary : MirrorTheme.moodColor(for: viewModel.selectedMood ?? ""))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                viewModel.selectedMood == nil && !isDetectingMood
                    ? Color(.secondarySystemFill)
                    : MirrorTheme.moodColor(for: viewModel.selectedMood ?? "").opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mood")
        .accessibilityValue(viewModel.selectedMood ?? "Not selected")
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
                        .foregroundStyle(pendingDelete ? Color.accentColor : .secondary)
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
                        .foregroundStyle(Color.accentColor)
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
                        .foregroundStyle(pendingDelete ? AnyShapeStyle(Color.accentColor) : (hasDraftContent ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)))
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
                        .foregroundStyle(hasDraftContent ? Color.accentColor : Color.secondary)
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

    private var dailyWordCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let savedToday = allEntries
            .filter { cal.startOfDay(for: $0.createdAt) == today }
            .reduce(0) { $0 + $1.wordCount }
        if let existing = entry {
            guard cal.startOfDay(for: existing.createdAt) == today else { return savedToday }
            return savedToday - existing.wordCount + viewModel.wordCount
        }
        guard cal.startOfDay(for: noteDate) == today else { return savedToday }
        return savedToday + viewModel.wordCount
    }

    var toolRow: some View {
        VStack(spacing: 0) {
            if dailyWordGoal > 0 && viewModel.wordCount > 0 {
                let progress = min(Double(dailyWordCount) / Double(dailyWordGoal), 1.0)
                let isComplete = dailyWordCount >= dailyWordGoal
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemFill))
                        Rectangle()
                            .fill(isComplete ? Color.green : MirrorTheme.primary)
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 2)
            }
            Divider()
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
                        .foregroundStyle(!photoDataArray.isEmpty ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if photoDataArray.count > 1 {
                                Text("\(photoDataArray.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor, in: Capsule())
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
                        .foregroundStyle(!draftVoiceNotes.isEmpty ? Color.accentColor : Color.primary)
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
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor, in: Capsule())
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
        .background(.bar)
    }
}
