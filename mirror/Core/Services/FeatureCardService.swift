import SwiftUI

// MARK: - Version comparison (component-based — safe for "1.0.10" vs "1.0.9")

struct AppVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        major = parts[0]
        minor = parts[1]
        patch = parts.count >= 3 ? parts[2] : 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - Card types

enum CardTier: CaseIterable, Equatable {
    case free, core, deep

    var label: String {
        switch self {
        case .free:  return "Free"
        case .core:  return "Core"
        case .deep:  return "Deep"
        }
    }

    var color: Color {
        switch self {
        case .free:  return .secondary
        case .core:  return MirrorTheme.primary
        case .deep:  return .purple
        }
    }

    var sectionIcon: String {
        switch self {
        case .free:  return "star"
        case .core:  return "sparkles"
        case .deep:  return "flame.fill"
        }
    }

    var pricingLabel: String? {
        switch self {
        case .free: return nil
        case .core: return "$2.99/mo"
        case .deep: return "$4.99/mo"
        }
    }
}

struct FeatureCard: Identifiable {
    let id: String
    let title: String
    let body: String
    let symbolName: String
    let accentColor: Color
    let tier: CardTier
    /// Version tag — card appears in the "What's New" auto-sheet only for this exact version.
    let sinceVersion: String
}

// MARK: - Registry — add new cards here when releasing features

enum FeatureCardRegistry {
    static let all: [FeatureCard] = [
        // Free
        .init(
            id: "write",
            title: "Private journaling",
            body: "Write anything — typed or voice. Your entries live on your device and back up to your private iCloud. No one else can read them.",
            symbolName: "pencil.and.outline",
            accentColor: MirrorTheme.primary,
            tier: .free,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "search",
            title: "Full-text search",
            body: "Find any entry instantly by keyword. Search runs entirely on-device — nothing leaves your phone.",
            symbolName: "magnifyingglass",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "icloud",
            title: "iCloud backup",
            body: "Your journal syncs automatically to your private iCloud. Encrypted, free, and only accessible by you.",
            symbolName: "icloud.fill",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "1.0.0"
        ),
        // Core
        .init(
            id: "nudge",
            title: "Daily Reflection",
            body: "Every day, mirror reads your recent entries and surfaces one honest observation. Not a generic quote — something from your actual writing.",
            symbolName: "sparkles",
            accentColor: MirrorTheme.primary,
            tier: .core,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "ask",
            title: "Ask (15×/month)",
            body: "Ask mirror anything about your writing. Get grounded answers from your own journal, not generic advice. Core includes 15 questions per month.",
            symbolName: "bubble.left.and.bubble.right",
            accentColor: .blue,
            tier: .core,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "digest",
            title: "Weekly Digest",
            body: "Every Sunday, mirror writes a short pattern summary from the week's entries — useful for spotting recurring themes you'd otherwise miss.",
            symbolName: "calendar.badge.clock",
            accentColor: .indigo,
            tier: .core,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "widget",
            title: "Home screen widget",
            body: "Quick-capture widget for your home screen and lock screen. See today's reflection or write a new entry without unlocking the app.",
            symbolName: "square.grid.2x2",
            accentColor: .orange,
            tier: .core,
            sinceVersion: "1.0.0"
        ),
        // Deep
        .init(
            id: "ask-unlimited",
            title: "Ask (unlimited)",
            body: "All the questions you want — no monthly cap. Ask mirror anything about your journal: patterns, feelings, decisions, progress.",
            symbolName: "bubble.left.and.bubble.right.fill",
            accentColor: .blue,
            tier: .deep,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "monthly",
            title: "Monthly Deep Report",
            body: "Once a month, mirror generates a full reflection on the previous month — emotional arc, recurring patterns, what shifted.",
            symbolName: "doc.text.magnifyingglass",
            accentColor: .purple,
            tier: .deep,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "mood-timeline",
            title: "Mood Timeline",
            body: "A visual chart of your mood across 30, 90, or all-time. See distribution, streaks, and patterns at a glance.",
            symbolName: "waveform.path.ecg",
            accentColor: .pink,
            tier: .deep,
            sinceVersion: "1.0.0"
        ),
        .init(
            id: "mood-alerts",
            title: "Mood Alerts",
            body: "mirror notifies you if your last 3 consecutive entries all show a negative mood. A quiet check-in, not an alarm.",
            symbolName: "bell.badge",
            accentColor: .orange,
            tier: .deep,
            sinceVersion: "1.0.0"
        ),
        // 1.0.7
        .init(
            id: "feature-guide",
            title: "Feature Guide",
            body: "Explore everything mirror can do — free, Core, and Deep — anytime from Settings → About → What's New.",
            symbolName: "square.grid.3x3",
            accentColor: MirrorTheme.primary,
            tier: .free,
            sinceVersion: "1.0.7"
        ),
    ]
}

// MARK: - Service

@Observable
final class FeatureCardService {
    static let shared = FeatureCardService()

    private let lastSeenVersionKey = "mirror.whatsNew.lastSeenVersion"

    var allCards: [FeatureCard] { FeatureCardRegistry.all }

    var whatsNewCards: [FeatureCard] {
        #if DEBUG
        return FeatureCardRegistry.all
        #else
        guard let last = AppVersion(lastSeenVersion),
              let current = AppVersion(currentAppVersion) else { return [] }
        return FeatureCardRegistry.all.filter {
            guard let cardVersion = AppVersion($0.sinceVersion) else { return false }
            return cardVersion > last && cardVersion <= current
        }
        #endif
    }

    var shouldShowWhatsNew: Bool {
        #if DEBUG
        return true
        #else
        guard let last = AppVersion(lastSeenVersion),
              let current = AppVersion(currentAppVersion) else { return false }
        return current > last && !whatsNewCards.isEmpty
        #endif
    }

    func markWhatsNewSeen() {
        UserDefaults.standard.set(currentAppVersion, forKey: lastSeenVersionKey)
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var lastSeenVersion: String {
        UserDefaults.standard.string(forKey: lastSeenVersionKey) ?? "0.0.0"
    }
}
