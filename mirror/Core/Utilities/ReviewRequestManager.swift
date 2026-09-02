import Foundation
import SwiftData
import UIKit

/// Surfaces the rate-us gate (`RateUsPromptSheet`) once per install, for any
/// user with 5+ journal entries. Checked after each entry save (from the
/// editor and from `AddJournalEntryIntent`) so new users see it right after
/// their 5th, and on every foreground (from `mirrorApp`) so users who already
/// crossed 5 — including on an earlier build that only showed Apple's raw
/// prompt — get the new gate on their next launch.
///
/// The key is deliberately NOT the old `entryMilestoneShown` one: existing
/// users who saw the old raw `SKStoreReviewRequest` have that set, and we
/// want them to see the new 🙂/🙁 gate once.
///
/// Detection is decoupled from presentation via `ReviewPromptCoordinator`
/// (the Siri path has no view to present from); `ContentView` shows the sheet.
/// Apple caps its own system prompt at 3/year regardless.
enum ReviewRequestManager {
    private static let entryMilestoneShownKey = "mirror.reviewRequest.smartPromptShown"
    private static let entryMilestone = 5

    static var hasShownEntryMilestonePrompt: Bool {
        UserDefaults.standard.bool(forKey: entryMilestoneShownKey)
    }

    /// Consumed by `ContentView` at the moment `RateUsPromptSheet` is actually
    /// presented — never before. If presentation is blocked (another sheet is
    /// up), the flag stays unset and the milestone can be retried.
    static func markEntryMilestonePromptShown() {
        UserDefaults.standard.set(true, forKey: entryMilestoneShownKey)
    }

    #if DEBUG
    /// Clears the one-shot flag so the gate can be triggered again for testing.
    static func resetEntryMilestonePromptForTesting() {
        UserDefaults.standard.removeObject(forKey: entryMilestoneShownKey)
    }
    #endif

    @MainActor
    static func requestIfEntryMilestoneReached(context: ModelContext) {
        guard !hasShownEntryMilestonePrompt else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard count >= entryMilestone else { return }
        // Small beat so the prompt doesn't collide with a save animation or a
        // just-launched screen still settling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .contains(where: { $0.activationState == .foregroundActive }) else { return }
            // Re-setting to true when already true is a no-op for SwiftUI's
            // onChange, which is fine — ContentView's retry loop, once started,
            // is self-driving and doesn't need a fresh transition.
            ReviewPromptCoordinator.shared.isPending = true
        }
    }
}
