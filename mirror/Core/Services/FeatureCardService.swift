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

enum CardTier: CaseIterable, Equatable, Hashable {
    case free, core, deep

    var label: LocalizedStringKey {
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
        case .deep:  return MirrorTheme.violet
        }
    }

    var sectionIcon: String {
        switch self {
        case .free:  return "star"
        case .core:  return "sparkles"
        case .deep:  return "flame.fill"
        }
    }

    var pricingLabel: LocalizedStringKey? {
        switch self {
        case .free: return nil
        case .core: return "$2.99/mo"
        case .deep: return "$4.99/mo"
        }
    }
}

struct FeatureCard: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let body: LocalizedStringKey
    let symbolName: String
    let accentColor: Color
    let tier: CardTier
    /// Version tag — card appears in the "What's New" auto-sheet only for this exact version.
    let sinceVersion: String
    /// False for changelog/update cards that shouldn't appear in the Feature Guide.
    var showInFeatureGuide: Bool = true
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
            accentColor: MirrorTheme.violet,
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
        // 1.0.8
        .init(
            id: "tags",
            title: "#Tags",
            body: "Add tags to any entry while writing. Filter your journal by tag to find related entries instantly — workouts, therapy sessions, dreams, anything.",
            symbolName: "number",
            accentColor: MirrorTheme.primary,
            tier: .free,
            sinceVersion: "1.0.8"
        ),
        .init(
            id: "writing-improvements-108",
            title: "Smarter lists & toolbar",
            body: "Bullet lists now nest visually (•, ◦, ▸). Tab indents a list item from the keyboard. Switching between checklist, numbered, and bullet works in one tap. Undo and redo show when they're available.",
            symbolName: "list.bullet.indent",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "1.0.8",
            showInFeatureGuide: false
        ),
        // 1.0.7
        .init(
            id: "auto-mood-detection",
            title: "Auto Mood Detection",
            body: "mirror now detects mood automatically when you save an entry — no manual tagging needed. Your Mood Timeline fills in on its own.",
            symbolName: "face.smiling",
            accentColor: .pink,
            tier: .core,
            sinceVersion: "1.0.7",
            showInFeatureGuide: false
        ),
        .init(
            id: "monthly-report-update",
            title: "Smarter Monthly Report",
            body: "In the last 3 days of the month, the report unlocks at 10 entries instead of 20 — so you don't miss it over a quiet month. A dedicated end-of-month card explains when there still isn't enough.",
            symbolName: "doc.text.magnifyingglass",
            accentColor: MirrorTheme.violet,
            tier: .deep,
            sinceVersion: "1.0.7",
            showInFeatureGuide: false
        ),
        // 2.0.3
        .init(
            id: "all-features-free-203",
            title: "Everything is free",
            body: "Ask, Daily Reflection, Weekly Digest, Monthly Deep Report, Mood Timeline, and widgets — every feature is free while mirror grows. No subscription required.",
            symbolName: "gift.fill",
            accentColor: .green,
            tier: .free,
            sinceVersion: "2.0.3"
        ),
        .init(
            id: "localization-203",
            title: "mirror now speaks 10 languages",
            body: "Spanish, Japanese, Chinese, German, French, Portuguese, Korean, Italian, and Russian — alongside English. Switch your device language and mirror follows.",
            symbolName: "globe",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "2.0.3"
        ),
        // 2.0.5
        .init(
            id: "siri-quick-add-205",
            title: "Add entries with Siri",
            body: "Say \"Hey Siri, add a journal entry in mirror\" and dictate — it saves straight to your journal, no need to open the app. Works from Shortcuts too.",
            symbolName: "mic.fill",
            accentColor: .teal,
            tier: .free,
            sinceVersion: "2.0.5"
        ),
        // 2.0.7
        .init(
            id: "sentinel-polish-207",
            title: "Sentinel mode, refined",
            body: "The HUD look now reaches every screen — Settings, the mood picker, calendar, tags, and the word-goal bar all match. Appearance locks to dark automatically while Sentinel is active, and switches back the moment you return to Classic.",
            symbolName: "viewfinder",
            accentColor: MirrorTheme.ember,
            tier: .free,
            sinceVersion: "2.0.7"
        ),
    ]
}

// MARK: - Service

@Observable
final class FeatureCardService {
    static let shared = FeatureCardService()

    private let lastSeenVersionKey = "mirror.whatsNew.lastSeenVersion"

    var allCards: [FeatureCard] { FeatureCardRegistry.all.filter { $0.showInFeatureGuide } }

    var whatsNewCards: [FeatureCard] {
        guard let last = AppVersion(lastSeenVersion),
              let current = AppVersion(currentAppVersion) else { return [] }
        let newSinceUpgrade = FeatureCardRegistry.all.filter {
            guard let cardVersion = AppVersion($0.sinceVersion) else { return false }
            return cardVersion > last && cardVersion <= current
        }
        // Fallback: if already seen this version, still show current version's cards
        if newSinceUpgrade.isEmpty {
            return FeatureCardRegistry.all.filter { $0.sinceVersion == currentAppVersion }
        }
        return newSinceUpgrade
    }

    var shouldShowWhatsNew: Bool {
        guard let last = AppVersion(lastSeenVersion),
              let current = AppVersion(currentAppVersion) else { return false }
        return current > last && !whatsNewCards.isEmpty
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
