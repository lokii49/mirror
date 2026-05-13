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

@MainActor
@Observable
final class InsightViewModel {
    var nudgeState: NudgeState = .idle
    var digestState: DigestState = .idle

    // MARK: - Daily Nudge

    func loadNudge(entries: [Entry], insights: [Insight], context: ModelContext) async {
        let today = DateHelpers.dayIdentifier(for: Date())
        let coordinatorKey = "nudge_\(today)"

        if case .loading = nudgeState {
            // If WE own the generation, keep waiting.
            // If someone else (pre-gen) is generating, fall through so a fresh
            // insights array passed from onChange can hit the cache check below.
            guard !InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) else { return }
        }

        guard entries.count >= 3 else {
            nudgeState = .needsMoreEntries(3 - entries.count)
            return
        }

        let hasSeenFirstNudge = insights.contains { $0.type == .dailyNudge }
        if hasSeenFirstNudge && !SubscriptionService.shared.isSubscribed {
            nudgeState = .subscriptionRequired
            return
        }

        if let cached = insights.first(where: {
            $0.type == .dailyNudge && $0.periodIdentifier == today
        }) {
            nudgeState = .loaded(cached)
            return
        }

        // If another caller (pre-gen) is generating, show spinner and wait for it
        // to insert the insight — InsightView's onChange(of: insights.count) will
        // re-call this function with fresh insights once it lands.
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            nudgeState = .loading
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

        InsightGenerationCoordinator.shared.release(key: coordinatorKey)
    }

    // MARK: - Weekly Digest

    func loadWeeklyDigest(entries: [Entry], insights: [Insight], context: ModelContext) async {
        let thisWeek = DateHelpers.weekIdentifier(for: Date())
        let coordinatorKey = "digest_\(thisWeek)"

        if case .loading = digestState {
            guard !InsightGenerationCoordinator.shared.isInFlight(coordinatorKey) else { return }
        }

        guard entries.count >= 5 else {
            digestState = .notEnoughEntries
            return
        }

        guard SubscriptionService.shared.isSubscribed else {
            digestState = .subscriptionRequired
            return
        }

        if let cached = insights.first(where: {
            $0.type == .weeklyDigest && $0.periodIdentifier == thisWeek
        }) {
            digestState = .loaded(cached)
            return
        }

        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            digestState = .loading
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

        InsightGenerationCoordinator.shared.release(key: coordinatorKey)
    }
}
