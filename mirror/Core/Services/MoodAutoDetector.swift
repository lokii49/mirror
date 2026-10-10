import Foundation
import SwiftData

/// Automatic mood detection for entries saved without one, shared by every path that does it:
/// save in WriteView, the Siri intent, the app-active/nightly backfill, and the daily reflection.
///
/// It exists for one race (2026-09-28): saving started detection fire-and-forget and, a moment
/// later, the daily reflection, whose plan reads the entry's mood as it's built. Detection takes
/// seconds on-device, so a save-triggered reflection usually saw no mood (the neutral line in the
/// other nine languages, "Mood: not specified" in the English prompt), and so did the mood-alert
/// check right after it. Callers that need the mood now await the detection; one in flight for
/// the same entry is joined rather than run twice.
@MainActor
final class MoodAutoDetector {
    static let shared = MoodAutoDetector()

    private var inFlight: [UUID: Task<Bool, Never>] = [:]

    private init() {}

    /// Starts (or joins) detection for an entry that has no mood. `nil` when there's nothing to
    /// do: a mood is already set, nothing readable to classify, or no tier/model for it. The
    /// task's value is whether a mood was saved. A mood the user picks while detection runs wins.
    @discardableResult
    func detectIfNeeded(_ entry: Entry, context: ModelContext) -> Task<Bool, Never>? {
        guard entry.mood == nil else { return nil }
        if let running = inFlight[entry.id] { return running }
        let sub = SubscriptionService.shared
        guard sub.tier == .core || sub.tier == .deep else { return nil }
        guard LocalLLMService.isModelAvailable else { return nil }
        guard !entry.textDecryptionFailed else { return nil }
        // A mood sealed under a key this device lacks reads as nil: don't take that for "no mood".
        guard !MirrorEncryption.encryptedStringNeedsUnavailableKey(entry.encryptedMood ?? "") else { return nil }
        let text = entry.insightContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let id = entry.id
        let task = Task { @MainActor [weak self] () -> Bool in
            defer { self?.inFlight[id] = nil }
            // The entry may have been deleted while the model ran; writing to it then can crash.
            guard let detected = try? await InsightService.detectEmotion(text: text),
                  MirrorTheme.moodOptions.contains(detected),
                  entry.modelContext != nil, !entry.isDeleted,
                  entry.mood == nil else { return false }
            entry.mood = detected
            try? context.save()
            return true
        }
        inFlight[id] = task
        return task
    }

    /// Detects moods for any of these entries that lack one and waits for all of them.
    func fillMissingMoods(for entries: [Entry], context: ModelContext) async {
        for entry in entries {
            _ = await detectIfNeeded(entry, context: context)?.value
        }
    }
}
