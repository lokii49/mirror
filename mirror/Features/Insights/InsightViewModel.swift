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

enum DigestState {
    case idle
    case loading
    case loaded(Insight)
    case notEnoughEntries
    case subscriptionRequired
    case error(String)
}

@Observable
final class InsightViewModel {
    var nudgeState: NudgeState = .idle
    var digestState: DigestState = .idle

    // MARK: - Daily Nudge

    func loadNudge(entries: [Entry], insights: [Insight], context: ModelContext) async {
        if case .loading = nudgeState {
            return
        }

        guard entries.count >= 3 else {
            nudgeState = .needsMoreEntries(3 - entries.count)
            return
        }

        let hasSeenFirstNudge = insights.contains { $0.type == .dailyNudge }

        // First nudge is always free — subsequent nudges require subscription
        if hasSeenFirstNudge && !SubscriptionService.shared.isSubscribed {
            nudgeState = .subscriptionRequired
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
            let sortedEntries = entries.sorted { $0.createdAt > $1.createdAt }
            let text = try await Task.detached(priority: .background) {
                try await InsightService.generateNudge(entries: sortedEntries, token: "")
            }.value
            let insight = Insight(type: .dailyNudge, content: text, periodIdentifier: today)
            context.insert(insight)
            nudgeState = .loaded(insight)
        } catch InsightError.subscriptionRequired {
            nudgeState = .subscriptionRequired
        } catch {
            nudgeState = .error(error.localizedDescription)
        }
    }

    // MARK: - Weekly Digest

    func loadWeeklyDigest(entries: [Entry], insights: [Insight], context: ModelContext) async {
        if case .loading = digestState {
            return
        }

        guard entries.count >= 5 else {
            digestState = .notEnoughEntries
            return
        }

        guard SubscriptionService.shared.isSubscribed else {
            digestState = .subscriptionRequired
            return
        }

        // Cache check — one digest per week
        let thisWeek = DateHelpers.weekIdentifier(for: Date())
        if let cached = insights.first(where: {
            $0.type == .weeklyDigest && $0.periodIdentifier == thisWeek
        }) {
            digestState = .loaded(cached)
            return
        }

        digestState = .loading
        do {
            let sortedEntries = entries.sorted { $0.createdAt > $1.createdAt }
            let text = try await Task.detached(priority: .background) {
                try await InsightService.generateWeeklyDigest(entries: sortedEntries, token: "")
            }.value
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek)
            context.insert(insight)
            digestState = .loaded(insight)
        } catch InsightError.subscriptionRequired {
            digestState = .subscriptionRequired
        } catch {
            digestState = .error(error.localizedDescription)
        }
    }
}
