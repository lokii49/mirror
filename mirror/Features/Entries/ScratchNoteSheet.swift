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
/// Its own surface, apart from Write, so it never touches Write's draft. The text is kept as an
/// encrypted draft on this device until it's saved or discarded.
struct ScratchNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loaded = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Lists, numbers, reminders…")
                                .foregroundStyle(MirrorTheme.textTertiary)
                                .padding(.horizontal, 13)
                                // Where each platform's text view puts the first line.
                                #if os(macOS)
                                .padding(.vertical, 8)
                                #else
                                .padding(.vertical, 16)
                                #endif
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("scratchNote.text")
                Label("Saved to Scratch. Reflections and insights don't read it.", systemImage: "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(MirrorTheme.textSecondary)
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
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 320, idealHeight: 360)
        #endif
        // A swipe down mustn't drop typed text; Cancel asks first.
        .interactiveDismissDisabled(!trimmed.isEmpty)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if case .payload(let draft) = WriteDraftStore.load(slot: .scratchNote) { text = draft.text }
            focused = true
        }
        // Debounced like Write's draft: one encrypted write after typing pauses.
        .task(id: text) {
            guard loaded else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            var draft = WriteDraftStore.Payload()
            draft.text = text
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
    }

    private func save() {
        do {
            try ScratchNotes.save(text, in: modelContext)
            WriteDraftStore.clear(slot: .scratchNote)
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
