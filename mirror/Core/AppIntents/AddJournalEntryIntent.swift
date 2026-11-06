import AppIntents
import SwiftData

struct AddJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Journal Entry"
    static var description = IntentDescription("Save a new entry to your MirrorNotes journal.")
    // Runs in the main app process so it can safely touch the shared SwiftData store.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Entry", description: "What you want to write in your journal")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to MirrorNotes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "That entry was empty — nothing saved.")
        }

        // Never write to the in-memory stand-in: the entry would be lost when the app closes.
        guard MirrorModelContainer.isStoreAvailable else {
            return .result(dialog: "MirrorNotes couldn't open your journal, so this wasn't saved. Open the app to fix it.")
        }
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: true) else {
            return .result(dialog: "Couldn't save this entry")
        }
        let context = MirrorModelContainer.shared.mainContext
        let entry = Entry(text: trimmed, source: .typed)
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: entry.createdAt)
        context.insert(entry)
        try context.save()

        // Fire-and-forget here: the app isn't necessarily open. The next daily reflection joins
        // or redoes it (MoodAutoDetector) before reading the mood.
        MoodAutoDetector.shared.detectIfNeeded(entry, context: context)
        ReviewRequestManager.requestIfEntryMilestoneReached(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)

        return .result(dialog: "Saved to your journal.")
    }

}

/// "Add a note to Scratch": a quick note saved into Scratch (the collection reflections don't
/// read), created the first time if needed. Same store and key checks as Add Journal Entry.
struct AddScratchNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Scratch Note"
    static var description = IntentDescription("Save a quick note to Scratch. Reflections and insights don't read it.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Note", description: "The list, number or reminder to keep")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Scratch")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "That note was empty — nothing saved.")
        }
        guard MirrorModelContainer.isStoreAvailable else {
            return .result(dialog: "MirrorNotes couldn't open your journal, so this wasn't saved. Open the app to fix it.")
        }
        do {
            try ScratchNotes.save(text, in: MirrorModelContainer.shared.mainContext)
        } catch {
            return .result(dialog: "Couldn't save this note")
        }
        return .result(dialog: "Saved to Scratch.")
    }
}

struct MirrorAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddJournalEntryIntent(),
            phrases: [
                "Add a journal entry in \(.applicationName)",
                "Write in \(.applicationName)",
                "Journal in \(.applicationName)",
            ],
            shortTitle: "Add Entry",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AddScratchNoteIntent(),
            phrases: [
                "Add a note to Scratch in \(.applicationName)",
                "Scratch note in \(.applicationName)",
            ],
            shortTitle: "Scratch Note",
            systemImageName: "note.text"
        )
    }
}
