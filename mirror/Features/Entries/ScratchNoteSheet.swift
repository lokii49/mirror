import SwiftUI
import SwiftData

/// Asks ContentView for the quick-note sheet (the Control Center button's link, the Entries menu,
/// the Mac's File menu). ContentView presents it once no other sheet is up; until then it waits.
@MainActor
@Observable
final class ScratchNotePresenter {
    static let shared = ScratchNotePresenter()
    private init() {}

    var pending = false
}

/// A quick note saved into Scratch: lists, numbers and reminders that reflections don't read.
/// Its own surface, apart from Write, so it never touches Write's draft. The text (and its list
/// styles) is kept as an encrypted draft on this device until it's saved or discarded.
///
/// Since 2026-11-07 (owner: "we say lists, numbers, reminders but there's no way"): Write's own
/// editor, so checklists check off and numbered lists renumber, a bar for Checklist / Numbered /
/// Bulleted, and Remind me…, a private local notification that opens the note (`ScratchReminders`).
struct ScratchNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @State private var text = ""
    @State private var textStyleData: Data?
    @State private var inlineStyleData: Data?
    @State private var photoDataArray: [Data] = []
    @State private var command: NoteTextCommand?
    @State private var commandRevision = 0
    @State private var editorFocused = false
    @State private var activeParagraphStyle: NoteParagraphTextStyle = .body
    @State private var activeInlineStyles = InlineStyleSet()
    @State private var showFormattingPanel = false
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var fontChoiceRaw = WritingFontChoice.system.rawValue
    @State private var panelState = FormattingPanelState()
    @State private var loaded = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    /// The time picked under Remind me…; scheduled when the note is saved.
    @State private var reminderDate: Date?
    @State private var showReminderPicker = false
    @State private var reminderFailed = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                // Write's editor grows to fit its text, so it scrolls inside this view (and its
                // caret-follow scrolls this view to keep the line being typed above the keyboard).
                ScrollView {
                NoteEditorTextView(
                    text: $text,
                    textStyleData: $textStyleData,
                    inlineStyleData: $inlineStyleData,
                    photoDataArray: $photoDataArray,
                    command: $command,
                    commandRevision: $commandRevision,
                    isFocused: $editorFocused,
                    activeParagraphStyle: $activeParagraphStyle,
                    activeInlineStyles: $activeInlineStyles,
                    showFormattingPanel: $showFormattingPanel,
                    canUndo: $canUndo,
                    canRedo: $canRedo,
                    fontChoiceRaw: $fontChoiceRaw,
                    panelState: panelState,
                    displayMode: displayMode,
                    placeholder: String(localized: "Lists, numbers, reminders…")
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    // A tap below the last line puts the cursor in the note.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MirrorTheme.inkRaised)
                        .onTapGesture { editorFocused = true }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("scratchNote.text")

                ScratchNoteToolbar(
                    activeStyle: activeParagraphStyle,
                    reminderDate: reminderDate,
                    send: send,
                    remind: { showReminderPicker = true }
                )
                // The note gets the room at the largest sizes; the bar stops growing at AX2.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Label("Saved to Scratch. Reflections and insights don't read it.", systemImage: "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(MirrorTheme.textSecondary)
                    // Whole at large sizes (it was cut at AX3), but no bigger than xxxLarge: at AX5
                    // it pushed the note itself off the screen.
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .padding(16)
            .background(MirrorTheme.bgBase)
            .navigationTitle("Scratch Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trimmed.isEmpty { discard() } else { confirmDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("scratchNote.save")
                }
            }
            .sheet(isPresented: $showReminderPicker) {
                ScratchReminderPicker(date: $reminderDate)
            }
        }
        // The app's plum for the cursor and controls (a sheet doesn't take ContentView's tint).
        .tint(MirrorTheme.primary)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 360, idealHeight: 420)
        #endif
        // A swipe down mustn't drop typed text; Cancel asks first.
        .interactiveDismissDisabled(!trimmed.isEmpty)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if case .payload(let draft) = WriteDraftStore.load(slot: .scratchNote) {
                text = draft.text
                textStyleData = draft.textStyleData
                inlineStyleData = draft.inlineStyleData
            }
            #if DEBUG
            // `--seedScratchListDemo`: synthetic lists for device captures (devicectl can't type).
            if ProcessInfo.processInfo.arguments.contains("--seedScratchListDemo") {
                text = "Groceries\nOat milk\nLemons\nTape\nBills\nRent\nPhone\nGate code 4412"
                let styles: [NoteParagraphTextStyle] = [.heading, .checklistUnchecked, .checklistChecked, .checklistUnchecked,
                                                        .heading, .numberedList, .numberedList, .bulletedList]
                textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles, indentLevels: nil, fontChoices: nil))
                if ProcessInfo.processInfo.arguments.contains("--seedScratchReminder") {
                    reminderDate = ScratchReminders.defaultTime()
                }
            }
            #endif
            editorFocused = true
        }
        // Debounced like Write's draft: one encrypted write after typing pauses.
        .task(id: draftKey) {
            guard loaded else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            var draft = WriteDraftStore.Payload()
            draft.text = text
            draft.textStyleData = textStyleData
            draft.inlineStyleData = inlineStyleData
            WriteDraftStore.save(draft, slot: .scratchNote)
        }
        // An alert, not a confirmation dialog: on iOS 26 a dialog attached here didn't appear while
        // the keyboard was up (14 Pro, 2026-11-06).
        .alert("Discard this note?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive, action: discard)
            Button("Keep Writing", role: .cancel) {}
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Couldn't set the reminder", isPresented: $reminderFailed) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("The note is saved without its reminder.")
        }
    }

    /// The draft is written again when the text or its list styles change.
    private var draftKey: String {
        "\(text.hashValue)-\(textStyleData?.hashValue ?? 0)-\(inlineStyleData?.hashValue ?? 0)"
    }

    private func send(_ newCommand: NoteTextCommand) {
        command = newCommand
        commandRevision += 1
    }

    private func save() {
        do {
            let entry = try ScratchNotes.save(text, textStyleData: textStyleData, inlineStyleData: inlineStyleData, in: modelContext)
            WriteDraftStore.clear(slot: .scratchNote)
            let entryID = entry.id
            if let reminderDate, reminderDate > Date() {
                Task { @MainActor in
                    // Permission was checked when the time was picked; this only fails if it was
                    // turned off since, or the system refused the request.
                    if await ScratchReminders.schedule(entryID: entryID, at: reminderDate) == .scheduled {
                        dismiss()
                    } else {
                        reminderFailed = true
                    }
                }
                return
            }
            text = ""
            dismiss()
        } catch ScratchNotes.SaveError.empty {
            return
        } catch ScratchNotes.SaveError.keyUnavailable {
            errorMessage = String(localized: "This device can't encrypt right now. Try again once it's unlocked.")
        } catch {
            errorMessage = String(localized: "Couldn't save this entry")
        }
    }

    private func discard() {
        WriteDraftStore.clear(slot: .scratchNote)
        text = ""
        dismiss()
    }
}

/// Checklist, Numbered, Bulleted and Remind me…, under the quick note's text. Each list button
/// turns the current line (or selection) into that list, or back to text when it already is one.
private struct ScratchNoteToolbar: View {
    let activeStyle: NoteParagraphTextStyle
    let reminderDate: Date?
    let send: (NoteTextCommand) -> Void
    let remind: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // One row; at accessibility sizes the reminder goes under the list buttons, where it
        // was cut to "Sat, 11:00…" beside them (AX3, 2026-11-07).
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { listButtons }
                reminderButton
            }
        } else {
            HStack(spacing: 8) {
                listButtons
                Spacer(minLength: 4)
                reminderButton
            }
        }
    }

    @ViewBuilder private var listButtons: some View {
        listButton("Checklist", systemImage: "checklist", command: .checklist,
                   isOn: activeStyle == .checklistUnchecked || activeStyle == .checklistChecked)
        listButton("Numbered list", systemImage: "list.number", command: .numberedList,
                   isOn: activeStyle == .numberedList)
        listButton("Bulleted list", systemImage: "list.bullet", command: .bulletedList,
                   isOn: activeStyle == .bulletedList)
    }

    private var reminderButton: some View {
            Button(action: remind) {
                HStack(spacing: 5) {
                    Image(systemName: reminderDate == nil ? "bell" : "bell.fill")
                    if let reminderDate {
                        Text(reminderDate, format: ScratchReminders.chipFormat(for: reminderDate))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Remind me…")
                    }
                }
                .scaledFont(14, weight: .medium)
                .foregroundStyle(MirrorTheme.violet)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(reminderDate == nil ? Color.clear : MirrorTheme.violetDim, in: Capsule())
                .overlay { if reminderDate == nil { Capsule().strokeBorder(MirrorTheme.inkBorder) } }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminderDate.map { Text("Reminder, \($0.formatted(date: .abbreviated, time: .shortened))") } ?? Text("Remind me"))
            .accessibilityIdentifier("scratchNote.remind")
    }

    private func listButton(_ title: LocalizedStringKey, systemImage: String, command: NoteTextCommand, isOn: Bool) -> some View {
        Button { send(command) } label: {
            Image(systemName: systemImage)
                .scaledFont(16, weight: .medium)
                .foregroundStyle(isOn ? MirrorTheme.violet : MirrorTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(isOn ? MirrorTheme.violetDim : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// When to be reminded: a date and time, Set or Remove. The reminder itself is scheduled when the
/// note is saved, so a discarded note never leaves one behind.
private struct ScratchReminderPicker: View {
    @Binding var date: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var picked = ScratchReminders.defaultTime()
    @State private var notAllowed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("Remind me at", selection: $picked, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Text("The reminder says only \"Scratch note reminder\" and opens this note. Its words stay in MirrorNotes.")
                    .font(.footnote)
                    .foregroundStyle(MirrorTheme.textSecondary)
                if date != nil {
                    Button("Remove Reminder", role: .destructive) {
                        date = nil
                        dismiss()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Remind me")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        // Asks for notifications now, while nothing is saved, not after.
                        Task { @MainActor in
                            if await ScratchReminders.ensureAllowed() {
                                date = picked
                                dismiss()
                            } else {
                                notAllowed = true
                            }
                        }
                    }
                    .accessibilityIdentifier("scratchNote.setReminder")
                }
            }
        }
        .onAppear { if let date, date > Date() { picked = date } }
        .alert("Notifications are off", isPresented: $notAllowed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To get reminders, allow notifications for MirrorNotes in Settings.")
        }
        #if os(iOS)
        .presentationDetents([.height(300)])
        #else
        .frame(minWidth: 360, minHeight: 220)
        #endif
    }
}
