import Foundation
import SwiftData

enum DisplayMode: String, Codable {
    case classic, sentinel
}

@Model final class UserProfile {
    var onboardingComplete: Bool = false
    var streakCount: Int = 0
    var lastWritten: Date? = nil

    /// Stored as raw String, not a native enum attribute — a native
    /// RawRepresentable attribute added to an *already-persisted* @Model
    /// crashes on lightweight migration (SIGABRT: "Could not cast value of
    /// type Optional<Any> to DisplayMode") because old on-disk records have
    /// no value for the new column and SwiftData force-casts instead of
    /// falling back to the default. Existing InsightType/EntrySource enums
    /// never hit this because they've been in their models' schema since
    /// v1 — this is the first attribute added later to an existing model.
    private var displayModeRaw: String? = nil

    var displayMode: DisplayMode {
        get { displayModeRaw.flatMap(DisplayMode.init(rawValue:)) ?? .classic }
        set { displayModeRaw = newValue.rawValue }
    }

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
