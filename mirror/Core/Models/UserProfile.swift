import Foundation
import SwiftData

enum DisplayMode: String, Codable {
    case classic, sentinel
}

@Model final class UserProfile {
    var onboardingComplete: Bool = false
    var streakCount: Int = 0
    var lastWritten: Date? = nil

    var displayMode: DisplayMode = DisplayMode.classic

    /// Stored as encoded Data, not a native array — matches Entry.swift's
    /// pattern of avoiding raw array attributes for CloudKit-synced models.
    /// Badges are one-time unlock events (can't always be re-derived from
    /// current entries, e.g. "wrote after midnight"), so unlike XP/level
    /// they're genuinely stateful and belong here. See GamificationEngine
    /// for why XP/level are computed live instead of stored.
    private var badgesStorage: Data? = nil

    var badges: [String] {
        get { badgesStorage.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { badgesStorage = try? JSONEncoder().encode(newValue) }
    }

    init() {}
}
