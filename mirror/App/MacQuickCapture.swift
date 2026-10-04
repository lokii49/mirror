#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

// Quick capture: a small popover from the menu bar that saves straight to an entry, the way the
// Siri intent (AddJournalEntryIntent) does. No reflection runs here; insights come from the
// main app. A decoupled surface: its own scene, its own state, no hooks into WriteView.

@Observable
@MainActor
final class MacQuickCaptureModel {
    static let shared = MacQuickCaptureModel()

    /// Held in memory only. Journal text is encrypted at rest, so a draft is never written to
    /// UserDefaults; it survives closing the popover, not quitting the app.
    var text = ""
    var mood: String?
    var showAllMoods = false
    var savedToday = false
    var errorMessage: String?
    var isTranscribing = false
    let recorder = VoiceInputManager()

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var wordCount: Int { strippedWordCount(text) }
    var canSave: Bool { !trimmed.isEmpty && !isTranscribing && !recorder.isRecording }

    /// Saves like AddJournalEntryIntent: an entry typed today, mood detected later if none was picked.
    @discardableResult
    func save(in context: ModelContext) -> Bool {
        guard canSave else { return false }
        guard MirrorModelContainer.isStoreAvailable else {
            errorMessage = String(localized: "MirrorNotes couldn't open your journal, so this wasn't saved. Open the app to fix it.")
            return false
        }
        let entry = Entry(text: trimmed, mood: mood, source: .typed)
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: entry.createdAt)
        context.insert(entry)
        do { try context.save() } catch {
            errorMessage = error.localizedDescription
            return false
        }
        if mood == nil { MoodAutoDetector.shared.detectIfNeeded(entry, context: context) }
        ReviewRequestManager.requestIfEntryMilestoneReached(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)
        text = ""
        mood = nil
        showAllMoods = false
        errorMessage = nil
        savedToday = true
        return true
    }

    /// Dictate: record, then transcribe on this Mac and add the words to the draft.
    func toggleDictation() async {
        errorMessage = nil
        if recorder.isRecording {
            recorder.stopRecording()
            guard let data = recorder.recordingData else { return }
            isTranscribing = true
            defer { isTranscribing = false; recorder.discardRecording() }
            do {
                let result = try await VoiceTranscriptionService.transcribe(audioData: data)
                let words = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !words.isEmpty else { return }
                text += (trimmed.isEmpty ? "" : " ") + words
                savedToday = false
            } catch {
                errorMessage = String(localized: "Couldn't transcribe that. Try again.")
            }
        } else {
            guard await recorder.requestPermission() else {
                errorMessage = String(localized: "Microphone access is off for MirrorNotes.")
                return
            }
            recorder.startRecording()
            if let message = recorder.error { errorMessage = message }
        }
    }
}

struct MacQuickCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Entry.createdAt, order: .reverse) private var recent: [Entry]
    @State private var model = MacQuickCaptureModel.shared
    @FocusState private var focused: Bool

    /// The three moods used most lately, else a calm default set; the rest sit behind More.
    private var shortcutMoods: [String] {
        var counts: [String: Int] = [:]
        for entry in recent.prefix(60) { if let mood = entry.mood { counts[mood, default: 0] += 1 } }
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3).map(\.key)
        var shown = top.count == 3 ? top : ["Peaceful", "Hopeful", "Drained"]
        // A mood picked from More stays visible among the shortcuts.
        if let picked = model.mood, !shown.contains(picked) { shown[shown.count - 1] = picked }
        return shown
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            field
            moodRow
            actions
            footer
        }
        .frame(width: 360)
        .background(MacTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MacTokens.popoverBorder, lineWidth: 1) }
        .onAppear { focused = true }
        .onExitCommand { NSApp.keyWindow?.close() }
        .environment(\.appDisplayMode, .classic)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text("Quick capture")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTokens.ink)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(MacTokens.controlBorder).frame(height: 1) }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { model.text }, set: { model.text = $0; model.savedToday = false }))
                .font(.system(size: 16, design: .serif))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .foregroundStyle(MacTokens.ink)
                .focused($focused)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .accessibilityLabel("Quick entry")
            if model.text.isEmpty {
                // Where the editor's first character lands (measured against typed text), so the
                // caret sits exactly on the start of the placeholder.
                Text("What's on your mind?")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(MacTokens.secondaryInk)
                    .padding(.leading, 13.5)
                    .padding(.top, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 150)
        .background(MacTokens.quickField, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var moodRow: some View {
        Group {
            if model.showAllMoods {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                    ForEach(MirrorTheme.moodOptions, id: \.self) { moodChip($0, fill: true) }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(shortcutMoods, id: \.self) { moodChip($0) }
                    Button("More") { model.showAllMoods = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(MacTokens.controlInk)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .overlay { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func moodChip(_ mood: String, fill: Bool = false) -> some View {
        let selected = model.mood == mood
        return Button {
            model.mood = selected ? nil : mood
        } label: {
            Text(MirrorTheme.localizedMoodName(for: mood))
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : MacTokens.controlInk)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: 24)
                .background(selected ? MacTokens.accent : Color.clear, in: Capsule())
                .overlay { if !selected { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.toggleDictation() }
            } label: {
                MacIcon(name: "mic", size: 16)
                    .frame(width: 32, height: 30)
                    .foregroundStyle(model.recorder.isRecording ? Color.white : MacTokens.controlInk)
                    .background(model.recorder.isRecording ? Color.red.opacity(0.85) : MacTokens.quickField, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(model.isTranscribing)
            .accessibilityLabel(model.recorder.isRecording ? "Stop dictation" : "Dictate")
            .help(model.recorder.isRecording ? "Stop and add the words to your entry" : "Dictate")

            Text(model.isTranscribing ? "Transcribing…" : (model.wordCount == 1 ? "1 word" : "\(model.wordCount) words"))
                .font(.system(size: 12))
                .foregroundStyle(MacTokens.secondaryInk)
            Spacer()
            Button {
                model.save(in: modelContext)
            } label: {
                Text("Save  ⌘↩")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(MacTokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(model.canSave ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Text(model.errorMessage ?? (model.savedToday ? String(localized: "Saved to today, on this Mac.") : String(localized: "Saves to today, on this Mac.")))
                .font(.system(size: 12))
                .foregroundStyle(model.errorMessage == nil ? MacTokens.secondaryInk : Color.red)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                openMain()
            } label: {
                Text("Open MirrorNotes")
                    .font(.system(size: 12, weight: .semibold))
                    .underline()
                    .foregroundStyle(MacTokens.controlInk)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(MacTokens.quickFooter)
        .overlay(alignment: .top) { Rectangle().fill(MacTokens.controlBorder).frame(height: 1) }
    }

    /// Brings the main window forward, or opens a new one if it was closed.
    private func openMain() {
        NSApp.keyWindow?.close()
        NSApp.activate(ignoringOtherApps: true)
        let main = NSApp.windows.first { !($0 is NSPanel) && $0.contentView != nil && $0.frame.width > 800 }
        if let main {
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
#endif
