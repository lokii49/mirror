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

        let context = MirrorModelContainer.shared.mainContext
        let entry = Entry(text: trimmed, source: .typed)
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: entry.createdAt)
        context.insert(entry)
        try context.save()

        autoDetectMood(for: entry, context: context)
        ReviewRequestManager.requestIfEntryMilestoneReached(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)

        return .result(dialog: "Saved to your journal.")
    }

    // Mirrors WriteView+MoodDetection's autoDetectMoodIfNeeded — fire-and-forget,
    // same gating (subscription tier, on-device model availability).
    private func autoDetectMood(for entry: Entry, context: ModelContext) {
        let sub = SubscriptionService.shared
        guard sub.tier == .core || sub.tier == .deep else { return }
        guard LocalLLMService.isModelAvailable else { return }
        let moodContext = entry.insightContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !moodContext.isEmpty else { return }
        Task {
            guard let detected = try? await InsightService.detectEmotion(text: moodContext),
                  MirrorTheme.moodOptions.contains(detected) else { return }
            await MainActor.run {
                entry.mood = detected
                try? context.save()
            }
        }
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
    }
}
