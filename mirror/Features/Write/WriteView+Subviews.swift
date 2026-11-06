import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let moodLabels = MirrorTheme.moodOptions

extension WriteView {
    /// A toolbar icon size of `base` points at the default text size, scaled with Dynamic Type
    /// up to 1.5x (more would overflow the 44 pt buttons).
    func toolbarIconSize(_ base: CGFloat) -> CGFloat {
        min(base * toolbarIconMetric / 20, base * 1.5)
    }

    var dateHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                showDatePicker = true
            } label: {
                // The date as the page's title (option A, owner 2026-11-06).
                WriteDateTitle(date: noteDate, isSentinel: displayMode == .sentinel)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Changes the entry's date and time")
            .buttonStyle(.plain)


            if displayMode == .sentinel {
                HStack(spacing: 5) {
                    Circle()
                        .fill(MirrorTheme.ember)
                        .frame(width: 6, height: 6)
                        .opacity(recPulse ? 1 : 0.35)
                    Text("REC")
                        .scaledFont(9.5, weight: .bold, design: .monospaced)
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

    /// "Wed, 7 Oct": short enough to never wrap beside the Mood button; the year only when it
    /// isn't this year. VoiceOver reads the full date.
    static func headerDateFormat(for date: Date) -> Date.FormatStyle {
        let base = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? base : base.year()
    }

    /// Word count and draft status, at the trailing end of the tags row.
    @ViewBuilder
    var writingStats: some View {
        HStack(spacing: 8) {
            if viewModel.wordCount > 0 {
                let goalMet = viewModel.wordCount >= dailyWordGoal
                if displayMode == .sentinel {
                    HStack(spacing: 3) {
                        Text("\(viewModel.wordCount)w")
                            .scaledFont(12, weight: .medium, design: .monospaced)
                            .foregroundStyle(goalMet ? Color.green : Color(.tertiaryLabel))
                        if goalMet {
                            Image(systemName: "checkmark")
                                .scaledFont(9, weight: .bold)
                                .foregroundStyle(.green)
                                .glyphPopIn()
                        } else if viewModel.wordCount >= 50 {
                            Text("/ \(dailyWordGoal)w")
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.25), value: goalMet)
                    .transition(.opacity)
                } else {
                    // Classic reads in the system face like the rest of the header: "30 words",
                    // with a small ring toward the daily goal once it's in sight.
                    HStack(spacing: 5) {
                        if goalMet {
                            // Pops in the moment the goal is reached.
                            Image(systemName: "checkmark.circle.fill")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(MirrorTheme.green)
                                .glyphPopIn()
                        } else if viewModel.wordCount >= 50 {
                            WordGoalRing(progress: Double(viewModel.wordCount) / Double(max(dailyWordGoal, 1)))
                        }
                        Text(viewModel.wordCount == 1 ? "1 word" : "\(viewModel.wordCount) words")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(goalMet ? AnyShapeStyle(MirrorTheme.green) : AnyShapeStyle(.tertiary))
                            .contentTransition(.numericText())
                    }
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.25), value: goalMet)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(goalMet || viewModel.wordCount < 50 ? Text("") : Text("\(viewModel.wordCount) of \(dailyWordGoal)"))
                    .transition(.opacity)
                }
            }
            DraftSaveStatusLabel(state: draftSaveState, retry: retryDraftSave, compact: true)
        }
        .fixedSize()
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
                    if !canSuggestMood { Text("Core required") }
                }
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood || !canSuggestMood)

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

    /// Option A (owner 2026-11-06), in both themes (owner: same design in both modes): an empty
    /// mood is an invitation (dashed accent pill), a picked one shows its colour and name. Its
    /// own struct: the header sits at the Debug stack limit.
    var signalLabel: some View {
        WriteMoodPill(mood: viewModel.selectedMood, isDetecting: isDetectingMood, isSentinel: displayMode == .sentinel)
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
                        .scaledFont(12, weight: .semibold)
                    Text(isDetectingMood ? "ANALYZING…" : "AUTO-DETECT")
                        .scaledFont(11.5, weight: .bold, design: .monospaced)
                        .kerning(0.4)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MirrorTheme.ember)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood || !canSuggestMood)
            .opacity(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canSuggestMood ? 0.4 : 1)

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
                                        .scaledFont(11, weight: .bold)
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
                            .scaledFont(11, weight: .semibold)
                        Text("CLEAR SIGNAL")
                            .scaledFont(11, weight: .semibold, design: .monospaced)
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

    var voiceButtonAccessibilityLabel: String {
        if isRecordingInline { return String(localized: "Stop recording") }
        if isTranscribingVoiceNotes { return String(localized: "Transcribing voice note") }
        return draftVoiceNotes.isEmpty ? String(localized: "Record voice note") : String(localized: "Voice notes")
    }

    /// The Write toolbar as one concrete type. As `some ToolbarContent` built here, its nested
    /// opaque types were resolved inside WriteView.body and, with focus mode's changes, overflowed
    /// the Debug main-thread stack on the iPhone 14 Pro (2026-11-03).
    var toolbarItems: WriteToolbar {
        WriteToolbar(
            isExistingEntry: entry != nil,
            focusMode: focusMode,
            pendingDelete: pendingDelete,
            hasDraftContent: hasDraftContent,
            takesSavedDrafts: takesSavedDrafts,
            saveGlyphBounces: saveGlyphBounces,
            isSentinel: displayMode == .sentinel,
            delete: { startDeleteWithUndo() },
            save: { if entry != nil { saveAndDismiss() } else { saveDraft() } },
            saveToDrafts: { saveToDrafts() },
            continueSavedDraft: { continueSavedDraft($0) },
            toggleFocus: {
                withAnimation(.easeInOut(duration: 0.2)) { focusMode.toggle() }
                if focusMode { editorFocused = true }
            },
            entryLinkPicker: $showEntryLinkPicker,
            linkingEntryID: entry?.id,
            linkToEntry: { applyTextCommand(.link(url: EntryLinks.urlString(for: $0))) }
        )
    }


    #if os(iOS)
    /// Something else holds the bottom slot (the follow-up chip, undo, saved, panels).
    var keyboardHintBlocked: Bool {
        focusMode || followUpQuestion != nil || pendingDelete || showSaved || isAttachingPhoto
            || isScanningText || showFormattingPanel
    }
    #endif

    /// DEBUG `--focusMode` opens the editor in focus mode, for device screenshots
    /// (devicectl can launch but not tap).
    static var startsInFocusMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--focusMode")
        #else
        false
        #endif
    }


    #if os(macOS)
    private func macParagraphLabel(_ style: NoteParagraphTextStyle) -> LocalizedStringKey {
        switch style {
        case .body: return "Body"
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .monospaced: return "Monospaced"
        case .blockQuote: return "Quote"
        case .checklistUnchecked, .checklistChecked: return "Checklist"
        case .bulletedList: return "Bulleted list"
        case .dashedList: return "Dashed list"
        case .numberedList: return "Numbered list"
        }
    }

    private func macToggle(_ systemImage: String, label: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .frame(width: 30, height: 28)
                .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// The Mac formatting row. Every control sends the same `NoteTextCommand` the iOS panel does,
    /// so both editors write the same stored documents.
    var macFormattingControls: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Body") { applyTextCommand(.body) }
                Button("Title") { applyTextCommand(.title) }
                Button("Heading") { applyTextCommand(.heading) }
                Button("Subheading") { applyTextCommand(.subheading) }
                Button("Monospaced") { applyTextCommand(.monospaced) }
                Button("Quote") { applyTextCommand(.blockQuote) }
            } label: {
                Text(macParagraphLabel(activeParagraphStyle))
                    .scaledFont(13)
                    .frame(minWidth: 84, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 18).padding(.horizontal, 4)

            macToggle("bold", label: "Bold", isOn: activeInlineStyles.bold) { applyTextCommand(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            macToggle("italic", label: "Italic", isOn: activeInlineStyles.italic) { applyTextCommand(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            macToggle("underline", label: "Underline", isOn: activeInlineStyles.underline) { applyTextCommand(.underline) }
                .keyboardShortcut("u", modifiers: .command)
            macToggle("strikethrough", label: "Strikethrough", isOn: activeInlineStyles.strikethrough) { applyTextCommand(.strikethrough) }

            Divider().frame(height: 18).padding(.horizontal, 4)

            macToggle("list.bullet", label: "Bulleted list", isOn: activeParagraphStyle == .bulletedList) { applyTextCommand(.bulletedList) }
            macToggle("list.number", label: "Numbered list", isOn: activeParagraphStyle == .numberedList) { applyTextCommand(.numberedList) }
            macToggle("checklist", label: "Checklist", isOn: activeParagraphStyle == .checklistUnchecked || activeParagraphStyle == .checklistChecked) { applyTextCommand(.checklist) }

            Divider().frame(height: 18).padding(.horizontal, 4)

            Menu {
                ForEach(WritingFontChoice.allCases) { choice in
                    Button { applyTextCommand(.fontFamily(choice)) } label: { Text(choice.label) }
                }
            } label: {
                Image(systemName: "textformat")
                    .scaledFont(14, weight: .semibold)
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Font")
        }
        .padding(.horizontal, 8)
    }
    #endif

    var toolRow: some View {
        #if os(iOS)
        keyboardBar
        #else
        VStack(spacing: 0) {
            if dailyWordGoal > 0 && viewModel.wordCount > 0 {
                let progress = min(Double(viewModel.wordCount) / Double(dailyWordGoal), 1.0)
                let isComplete = viewModel.wordCount >= dailyWordGoal
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(MirrorTheme.inkBorder)
                        Rectangle()
                            .fill(isComplete ? MirrorTheme.green : (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary))
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 2)
            }
            Divider().overlay(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.3) : MirrorTheme.inkBorder)
            HStack(spacing: 0) {
                // Undo
                Button {
                    applyTextCommand(.undo)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: toolbarIconSize(18)))
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
                        .font(.system(size: toolbarIconSize(18)))
                        .foregroundStyle(canRedo ? Color.secondary : Color.secondary.opacity(0.35))
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canRedo)
                .accessibilityLabel("Redo")

                macFormattingControls
                Spacer(minLength: 0)

                // Checklist quick-ops — appear only when cursor is on a checklist paragraph
                let isInChecklist = activeParagraphStyle == .checklistUnchecked || activeParagraphStyle == .checklistChecked
                if isInChecklist {
                    Button {
                        applyTextCommand(.checkAllItems)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: toolbarIconSize(20)))
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
                            .font(.system(size: toolbarIconSize(20)))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete checked items")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

            }
            .animation(.easeInOut(duration: 0.15), value: activeParagraphStyle)
            .padding(.horizontal, 8)
        }
        .background(MirrorTheme.inkMid)
        #endif
    }
}

/// "Keep writing" follow-up chip (writing-roadmap.md 1.2) — a single on-device-generated
/// question, dismissible, never persisted. Mirrors MicPermissionNotice's shape (simple
/// bottom banner) rather than WritingPromptCard's — this is a transient nudge, not a
/// content card.
struct FollowUpChip: View {
    let question: String
    /// Which engine produced `question` — Gemma 3 1B or Apple Foundation Models. Surfaced only
    /// in Sentinel mode as a small tag, matching `InsightSignalSource`'s existing X-ray
    /// convention (engine attribution for persisted insights) rather than inventing a new
    /// logging mechanism for an ephemeral, unpersisted feature. Closes the "no way to tell which
    /// engine produced a bad follow-up" gap flagged in writing-roadmap.md without adding
    /// persistence this feature was deliberately scoped to avoid.
    var engine: LLMEngine? = nil
    let onUse: () -> Void
    let onDismiss: () -> Void

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    private var engineTag: String? {
        guard isSentinel, let engine else { return nil }
        switch engine {
        case .gemma: return "GEMMA"
        case .foundationModels: return "FM"
        case .search: return "SEARCH"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violet)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(question)
                    .scaledFont(13.5, design: .serif)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let engineTag {
                    Text(engineTag)
                        .scaledFont(8.5, weight: .bold, design: .monospaced)
                        .tracking(0.6)
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(action: onUse) {
                    Image(systemName: "plus.circle.fill")
                        .scaledFont(20)
                        .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violet)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add this question to your entry")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .scaledFont(10, weight: .bold)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isSentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((isSentinel ? MirrorTheme.ember : MirrorTheme.violet).opacity(isSentinel ? 0.3 : 0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}

/// "Talk it out" starter chip (writing-roadmap.md Tier 2) — the sole entry point after two
/// placement pivots this session (menu item, then a persistent tab, both reverted). Shown only
/// on a genuinely blank new entry (`WriteView`'s own gate); a quiet row, not a card, since it's
/// an offer that should get out of the way the instant the user starts writing on their own.
/// Blank-new-entry starter chip (writing-roadmap.md 0.2 + Tier 2) — one entry point instead of
/// two. Was Talk-it-out-only; widened into a menu offering Talk it out plus the 3 quick-start
/// templates, since 0.2's templates were otherwise reachable only during the cold-start
/// `.needsMoreEntries` window in InsightView and invisible to most users past onboarding.
/// Reuses this chip's already-verified-on-device placement/timing rather than adding a second
/// chip alongside it.
struct WritingStarterChip: View {
    /// False on Free: the menu offers only the templates (no paywall before the first nudge).
    var showsTalkItOut = true
    let onTalkItOut: () -> Void
    /// The text a template starts the entry with, and where the caret goes in it.
    let onUseTemplate: (_ text: String, _ cursorOffset: Int) -> Void
    /// A Journaling Suggestion picked (iPhone; iPad from iPadOS 26): its title, a line per moment,
    /// pictures and mood (`SuggestionInsert`).
    var onSuggestion: ((SuggestionInsert) -> Void)? = nil

    @Environment(\.appDisplayMode) private var displayMode
    @State private var showTemplateManager = false
    /// Your templates, unsealed once and again when the manager closes (not on every render).
    @State private var customTemplates: [CustomTemplate] = []
    /// The one-time explanation under "Suggestions from your day" (owner, 2026-11-06).
    @AppStorage("mirror.suggestions.tipShown") private var suggestionsTipShown = false
    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.violet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            starterMenu
            suggestionsPicker
        }
    }

    /// Apple's Journaling Suggestions (photos, workouts, places from your day), chosen in Apple's
    /// own sheet; nothing reaches the app until the person picks one (3.1.8, item 7).
    @ViewBuilder
    private var suggestionsPicker: some View {
        #if os(iOS) && canImport(JournalingSuggestions)
        if let onSuggestion, #available(iOS 17.2, *), DeviceFeature.journalingSuggestionsAvailable {
            JournalingSuggestionsPicker {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .scaledFont(13, weight: .semibold)
                    Text(isSentinel ? "SUGGESTIONS FROM YOUR DAY" : "Suggestions from your day")
                        .scaledFont(isSentinel ? 12.5 : 14, weight: isSentinel ? .semibold : .medium, design: isSentinel ? .monospaced : .default)
                        .kerning(isSentinel ? 0.4 : 0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(accent)
                .frame(minHeight: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            } onCompletion: { suggestion in
                let insert = await SuggestionInsert.read(suggestion)
                await MainActor.run {
                    suggestionsTipShown = true
                    onSuggestion(insert)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("write.suggestions")
            if !suggestionsTipShown {
                HStack(alignment: .top, spacing: 8) {
                    Text("Photos, workouts and places from your day, picked in Apple's own sheet. Nothing reaches MirrorNotes until you choose one.")
                        .scaledFont(12.5)
                        .foregroundStyle(MirrorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { suggestionsTipShown = true } label: {
                        Image(systemName: "xmark")
                            .scaledFont(11, weight: .bold)
                            .foregroundStyle(MirrorTheme.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.leading, 22)
                .padding(.bottom, 4)
            }
        }
        #endif
    }

    private var starterMenu: some View {
        Menu {
            if showsTalkItOut {
                Button(action: onTalkItOut) {
                    Label(isSentinel ? "TALK IT OUT" : "Talk it out", systemImage: "bubble.left.and.text.bubble.right")
                }
                Divider()
            }
            ForEach(WritingTemplate.allCases) { template in
                Button { onUseTemplate(template.seedText, template.cursorOffset) } label: {
                    Label(template.title, systemImage: template.icon)
                }
            }
            // Your own templates (this device only), then managing them.
            if !customTemplates.isEmpty {
                Divider()
                ForEach(customTemplates) { template in
                    Button { onUseTemplate(template.text, .max) } label: {
                        Label(template.title, systemImage: "doc.text")
                    }
                }
            }
            Divider()
            Button("Manage Templates…", systemImage: "slider.horizontal.3") { showTemplateManager = true }
        } label: {
            // Option A (owner 2026-11-06): one quiet line, not a card above the page, in both themes.
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .scaledFont(13, weight: .semibold)
                Text(isSentinel ? "NEED A STARTING POINT?" : "Need a starting point?")
                    .scaledFont(isSentinel ? 12.5 : 14, weight: isSentinel ? .semibold : .medium, design: isSentinel ? .monospaced : .default)
                    .kerning(isSentinel ? 0.4 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(accent)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsTalkItOut ? "Need a starting point? Talk it out, or use a template" : "Need a starting point?")
        .accessibilityIdentifier("write.starter")
        // Inside this struct, not on WriteView.body (Debug stack limit).
        .sheet(isPresented: $showTemplateManager, onDismiss: { customTemplates = CustomTemplateStore.readable() }) {
            TemplateManagerView()
        }
        .task { customTemplates = CustomTemplateStore.readable() }
    }
}

/// The Write header's progress toward the daily word goal: a thin ring the size of a glyph.
struct WordGoalRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(MirrorTheme.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
        .animation(.easeOut(duration: 0.25), value: progress)
        .accessibilityHidden(true)
    }
}

/// The classic Write header's mood button (option A): a dashed accent pill with a face while no
/// mood is set, the mood's colour and name once one is.
struct WriteMoodPill: View {
    let mood: String?
    let isDetecting: Bool
    var isSentinel = false

    var body: some View {
        let accent = isSentinel ? MirrorTheme.ember : MirrorTheme.violet
        let tint = mood.map { MirrorTheme.moodColor(for: $0) } ?? accent
        HStack(spacing: 7) {
            if isDetecting {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else if let mood {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Text(isSentinel ? MirrorTheme.localizedMoodName(for: mood).uppercased() : MirrorTheme.localizedMoodName(for: mood))
                    .foregroundStyle(tint)
            } else {
                Image(systemName: isSentinel ? "waveform" : "face.smiling")
                    .scaledFont(isSentinel ? 13 : 16, weight: .medium)
                    .foregroundStyle(accent)
            }
            if mood == nil {
                Text(isSentinel ? "SIGNAL" : "Mood")
                    .foregroundStyle(accent)
            }
        }
        .scaledFont(isSentinel ? 13.5 : 15, weight: .semibold, design: isSentinel ? .monospaced : .default)
        .kerning(isSentinel ? 0.4 : 0)
        .lineLimit(1)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(mood == nil ? Color.clear : tint.opacity(0.12), in: Capsule())
        .overlay {
            if mood == nil {
                Capsule().strokeBorder(accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: mood)
        .animation(.easeInOut(duration: 0.2), value: isDetecting)
    }
}
