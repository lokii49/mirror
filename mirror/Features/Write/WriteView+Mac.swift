#if os(macOS)
import SwiftUI
import AppKit

// The Mac Write screen's chrome, built to the approved design: a 52 pt toolbar, a 680 pt
// editor column with the date line above and mood/tag chips below, and a status bar. The
// behavior behind every control is WriteView's existing logic.

extension WriteView {

    // MARK: - Toolbar

    var macToolbar: some View {
        HStack(spacing: 6) {
            macIconButton("sidebar", label: "Hide sidebar") {
                NotificationCenter.default.post(name: .mirrorMacToggleSidebar, object: nil)
            }

            Button { showDatePicker = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry == nil ? "New entry" : "Edit entry")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MacTokens.ink)
                    Text(noteDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacTokens.secondaryInk)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .accessibilityLabel("Change date")

            Spacer(minLength: 8)

            // B / I / U / Aa
            HStack(spacing: 0) {
                formatCell(width: 32) {
                    Text("B").font(.system(size: 13, weight: .bold))
                } isOn: { activeInlineStyles.bold } action: { applyTextCommand(.bold) }
                .keyboardShortcut("b", modifiers: .command)
                .accessibilityLabel("Bold")

                formatDivider
                formatCell(width: 32) {
                    Text("I").font(.custom("Georgia", size: 13).italic())
                } isOn: { activeInlineStyles.italic } action: { applyTextCommand(.italic) }
                .keyboardShortcut("i", modifiers: .command)
                .accessibilityLabel("Italic")

                formatDivider
                formatCell(width: 32) {
                    Text("U").font(.system(size: 13)).underline()
                } isOn: { activeInlineStyles.underline } action: { applyTextCommand(.underline) }
                .keyboardShortcut("u", modifiers: .command)
                .accessibilityLabel("Underline")

                formatDivider
                formatCell(width: 40) {
                    Text("Aa").font(.system(size: 12))
                } isOn: { showFormattingPanel } action: { showFormattingPanel.toggle() }
                .accessibilityLabel("Text formatting")
                .popover(isPresented: $showFormattingPanel, arrowEdge: .bottom) {
                    FormattingPanelView(state: panelState, presentation: .popover)
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 380, minHeight: 320)
                        .environment(\.appDisplayMode, displayMode)
                }
            }
            .background(MacTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }

            Rectangle().fill(MacTokens.controlBorder).frame(width: 1, height: 20).padding(.horizontal, 6)

            Menu {
                macMoodMenuItems
            } label: {
                MacIcon(name: "smile", size: 17)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(MacTokens.controlInk)
            .accessibilityLabel("Mood")

            macIconButton("tag", label: "Add tag") {
                showTagInput = true
            }
            macIconButton("image", label: "Add photo") {
                showPhotoPicker = true
            }
            macIconButton("mic", label: "Record voice note") {
                toggleInlineRecording()
            }

            Button { presentTalkItOut() } label: {
                Text("Talk it out")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MacTokens.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .frame(height: MacTokens.chromeHeight)
        .background(MacTokens.windowBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(MacTokens.divider).frame(height: 1) }
    }

    private func macIconButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MacIcon(name: icon, size: 17)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacTokens.controlInk)
        .accessibilityLabel(label)
    }

    private var formatDivider: some View {
        Rectangle().fill(MacTokens.segmentDivider).frame(width: 1, height: 26)
    }

    private func formatCell<Label: View>(width: CGFloat, @ViewBuilder label: () -> Label, isOn: () -> Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(isOn() ? MacTokens.accent : MacTokens.ink)
                .frame(width: width, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var macMoodMenuItems: some View {
        Button {
            detectMoodWithMirror()
        } label: {
            Label(isDetectingMood ? "Detecting..." : "Mirror suggests", systemImage: "sparkles")
        }
        .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood)
        Divider()
        ForEach(MirrorTheme.moodOptions, id: \.self) { mood in
            Button {
                moodWasSuggested = false
                viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
            } label: {
                Text(MirrorTheme.localizedMoodName(for: mood))
            }
        }
        if viewModel.selectedMood != nil {
            Divider()
            Button("Clear mood") {
                moodWasSuggested = false
                viewModel.selectedMood = nil
            }
        }
    }

    // MARK: - Editor column

    /// "WEDNESDAY · 30 SEPTEMBER · 9:42 AM"
    var macDateLine: some View {
        let weekday = noteDate.formatted(.dateTime.weekday(.wide))
        let dayMonth = noteDate.formatted(.dateTime.day().month(.wide))
        let time = noteDate.formatted(.dateTime.hour().minute())
        return Text("\(weekday) · \(dayMonth) · \(time)".uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(MacTokens.secondaryInk)
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mood chip, tag chips and the suggestion hint, under the text.
    var macChipsRow: some View {
        HStack(spacing: 10) {
            if let mood = viewModel.selectedMood {
                Text(MirrorTheme.localizedMoodName(for: mood))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(MacTokens.accent, in: Capsule())
            }
            ForEach(entryTags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(MirrorTheme.localizedTagName(for: tag))")
                        .font(.system(size: 12.5))
                    Button {
                        entryTags.removeAll { $0 == tag }
                        if entry == nil { saveDraftToStorage() }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag")
                }
                .foregroundStyle(MacTokens.controlInk)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(MacTokens.surface, in: Capsule())
                .overlay { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) }
            }
            if showTagInput {
                TextField("tag", text: $tagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 90)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(MacTokens.surface, in: Capsule())
                    .overlay { Capsule().stroke(MacTokens.accent, lineWidth: 1) }
                    .onSubmit {
                        commitTag()
                        showTagInput = false
                    }
                    .focused($tagFieldFocused)
                    .onAppear { DispatchQueue.main.async { tagFieldFocused = true } }
            }
            if viewModel.selectedMood != nil, moodWasSuggested {
                Text("Mood suggested from your entry. Change it any time.")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTokens.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status bar

    var macStatusBar: some View {
        HStack(spacing: 14) {
            Text("\(viewModel.wordCount) words")
                .font(.system(size: 12))
                .foregroundStyle(MacTokens.secondaryInk)
            if entry == nil, hasDraftContent {
                Text("Draft saved")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTokens.secondaryInk)
            }
            Spacer(minLength: 0)
            Text("⌘↩ to save")
                .font(.system(size: 12))
                .foregroundStyle(MacTokens.secondaryInk)
            Button {
                if entry == nil { saveDraft() } else { saveAndDismiss() }
            } label: {
                Text("Save entry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(MacTokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(hasDraftContent ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!hasDraftContent)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Save entry")
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(MacTokens.divider).frame(height: 1) }
        .background(MacTokens.windowBackground)
    }
}

/// The system draws a soft band under a bar that overlaps scrolling content (macOS 26). The board
/// has a flat toolbar over a flat background, so the effect is turned off.
struct MacNoScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

/// Centers the scrolling content in the board's 680 pt column (plus the 20 pt side padding
/// every child already has).
struct MacEditorColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}
#endif
