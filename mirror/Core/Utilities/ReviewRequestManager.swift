import Foundation
import SwiftData
import UIKit

/// Surfaces the rate-us gate (`RateUsPromptSheet`) at the moment the user is
/// most invested: right after saving their 5th journal entry. Fires once per
/// install. Detection is decoupled from presentation via
/// `ReviewPromptCoordinator` — this is also called from `AddJournalEntryIntent`
/// (Siri), which has no view of its own to show a sheet from, so the actual
/// custom SwiftUI sheet is always presented by `ContentView` regardless of
/// which call site set the flag. The system prompt itself
/// (`SKStoreReviewRequest`, triggered from inside the sheet) additionally
/// caps at 3 prompts per year — outside mirror's control.
enum ReviewRequestManager {
    private static let entryMilestoneShownKey = "mirror.reviewRequest.entryMilestoneShown"
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

    @MainActor
    static func requestIfEntryMilestoneReached(context: ModelContext) {
        guard !hasShownEntryMilestonePrompt else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard count >= entryMilestone else { return }
        // Let the save/dismiss animation settle before the prompt appears.
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
