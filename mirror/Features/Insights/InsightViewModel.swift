import SwiftUI
import SwiftData

enum NudgeState {
    case idle
    case loading
    case loaded(Insight)
    case needsMoreEntries(Int)
    case subscriptionRequired
    case error(String)
}

@Observable
final class InsightViewModel {
    var nudgeState: NudgeState = .idle

    func loadNudge(entries: [Entry], insights: [Insight], context: ModelContext) async {
        guard entries.count >= 3 else {
            nudgeState = .needsMoreEntries(3 - entries.count)
            return
        }

        guard SubscriptionService.shared.isSubscribed else {
            nudgeState = .subscriptionRequired
            return
        }

        guard let token = KeychainManager.load() else {
            nudgeState = .error("Sign in to unlock insights.")
            return
        }

        // Cache check — one nudge per day
        let today = DateHelpers.dayIdentifier(for: Date())
        if let cached = insights.first(where: {
            $0.type == .dailyNudge && $0.periodIdentifier == today
        }) {
            nudgeState = .loaded(cached)
            return
        }

        nudgeState = .loading
        do {
            let text = try await InsightService.generateNudge(
                entries: entries.sorted { $0.createdAt > $1.createdAt },
                token: token
            )
            let insight = Insight(type: .dailyNudge, content: text, periodIdentifier: today)
            context.insert(insight)
            nudgeState = .loaded(insight)
        } catch InsightError.subscriptionRequired {
            nudgeState = .subscriptionRequired
        } catch {
            nudgeState = .error(error.localizedDescription)
        }
    }
}
