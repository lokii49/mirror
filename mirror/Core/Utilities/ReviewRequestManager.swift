import Foundation
import StoreKit
import SwiftData
import UIKit

/// Asks for an App Store rating at the moment the user is most invested:
/// right after saving their 5th journal entry. Fires once per install;
/// the system additionally caps prompts at 3 per year.
enum ReviewRequestManager {
    private static let entryMilestoneShownKey = "mirror.reviewRequest.entryMilestoneShown"
    private static let entryMilestone = 5

    @MainActor
    static func requestIfEntryMilestoneReached(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: entryMilestoneShownKey) else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard count >= entryMilestone else { return }
        // Let the save/dismiss animation settle before the system alert appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Only consume the one-shot once we're actually about to prompt — if the
            // app backgrounded during the delay, retry on the next qualifying save
            // instead of burning the flag on a prompt that never appeared.
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            defaults.set(true, forKey: entryMilestoneShownKey)
            AppStore.requestReview(in: scene)
        }
    }
}
