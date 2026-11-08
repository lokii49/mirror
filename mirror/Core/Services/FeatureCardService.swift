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

    var subscriptionTier: SubscriptionTier {
        switch self {
        case .free: return .free
        case .core: return .core
        case .deep: return .deep
        }
    }

    /// "2,99 €/mo" in the user's own storefront currency, from the product the paywall sells.
    /// Nil until products have loaded. Never a typed-in dollar amount: Apple prices each country
    /// separately.
    func pricingLabel(from service: SubscriptionService = .shared) -> LocalizedStringKey? {
        guard let price = service.localizedMonthlyPrice(for: subscriptionTier) else { return nil }
        return "\(price)/mo"
    }
}

struct FeatureCard: Identifiable {
    let id: String
    let title: LocalizedStringKey
    var body: LocalizedStringKey
    let symbolName: String
    let accentColor: Color
    let tier: CardTier
    /// Version tag — card appears in the "What's New" auto-sheet only for this exact version.
    let sinceVersion: String
    /// False for changelog/update cards that shouldn't appear in the Feature Guide.
    var showInFeatureGuide: Bool = true
    /// iPhone/iPad only (the Mac has its own version of the feature, or none).
    var iOSOnly: Bool = false
    /// What this device needs for the card's promise to hold.
    var requirement: DeviceFeature? = nil
    /// Shown instead of `body` where `requirement` isn't met; nil hides the card there.
    var bodyWithoutRequirement: LocalizedStringKey? = nil

    /// The card as this device should show it, or nil when it promises something this device
    /// can't do (Health before iOS 18, a Watch on an iPad).
    func forThisDevice() -> FeatureCard? {
        guard let requirement, !requirement.isAvailable else { return self }
        guard let bodyWithoutRequirement else { return nil }
        var card = self
        card.body = bodyWithoutRequirement
        return card
    }
}

/// Device-dependent features a What's New card can promise.
enum DeviceFeature {
    case appleHealth, appleWatch, journalingSuggestions
    /// StoreKit's offer code sheet: iPhone and iPad, and the Mac app on macOS 15+ (not the
    /// iPhone app running on a Mac).
    case redeemCode
    /// This device's profile had Sentinel mode chosen before 3.1.8 retired it (ContentView records it).
    case usedSentinel

    static let usedSentinelKey = "mirror.whatsNew.usedSentinel"

    var isAvailable: Bool {
        switch self {
        case .usedSentinel:
            return UserDefaults.standard.bool(forKey: Self.usedSentinelKey)
        case .appleHealth:
            return HealthMoodWriter.isAvailable
        case .appleWatch:
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .phone
            #else
            return false
            #endif
        case .journalingSuggestions:
            return Self.journalingSuggestionsAvailable
        case .redeemCode:
            return RedeemCodeSheet.isAvailable
        }
    }

    /// Where Write offers Apple's Journaling Suggestions: iPhone on iOS 17.2+, iPad from 26.
    static var journalingSuggestionsAvailable: Bool {
        #if os(iOS) && canImport(JournalingSuggestions)
        guard #available(iOS 17.2, *) else { return false }
        return UIDevice.current.userInterfaceIdiom == .phone
            || ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        #else
        return false
        #endif
    }
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
            sinceVersion: "2.0.3",
            // History only: the free period ended with 3.1.8, so a feature guide must never show it.
            showInFeatureGuide: false
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
            // Must match what MirrorAppShortcuts' registered phrase actually resolves to at
            // runtime — \(.applicationName) fills in CFBundleDisplayName ("MirrorNotes"), not
            // PRODUCT_NAME/the Xcode target name ("mirror") — same fix as ProtocolSettingsView's
            // Quick Capture row.
            body: "Say \"Hey Siri, add a journal entry in MirrorNotes\" and dictate — it saves straight to your journal, no need to open the app. Works from Shortcuts too.",
            symbolName: "mic.fill",
            accentColor: .teal,
            tier: .free,
            sinceVersion: "2.0.5"
        ),
        // 2.0.7
        .init(
            id: "sentinel-launch-207",
            title: "Introducing Sentinel mode",
            body: "A whole new way to see MirrorNotes — HUD readouts, mono type, and ember accents on every screen, from Settings to the mood picker. Switch anytime under Settings → Appearance. Classic is still there whenever you want the calm version back.",
            symbolName: "viewfinder",
            accentColor: MirrorTheme.ember,
            tier: .free,
            sinceVersion: "2.0.7"
        ),
        // 2.1.0
        .init(
            id: "mood-checkin-210",
            title: "Daily mood check-in",
            body: "Log how you're feeling in one tap — no writing required. If you haven't checked in by your reminder time, mirror asks when you next open the app, and a Log mood button on Insights lets you update whenever you want. Every check-in feeds your Mood Timeline and the Mood Map widget.",
            symbolName: "face.smiling",
            accentColor: .pink,
            tier: .free,
            sinceVersion: "2.1.0"
        ),
        .init(
            id: "insight-widgets-210",
            title: "Weekly & monthly widgets",
            body: "The Weekly Digest and Monthly Deep Report now have home screen widgets — your latest reflection sits on the home screen, no need to open the app.",
            symbolName: "square.grid.2x2",
            accentColor: .indigo,
            tier: .core,
            sinceVersion: "2.1.0"
        ),
        .init(
            id: "show-your-work-210",
            title: "Every AI card shows its work",
            body: "In Sentinel mode, tap a card's source button to see exactly which entries — and which prompt — produced a reflection, weekly digest, monthly report, or Ask answer. Drag across to wipe between the result and where it came from.",
            symbolName: "rectangle.and.text.magnifyingglass",
            accentColor: MirrorTheme.ember,
            tier: .free,
            sinceVersion: "2.1.0"
        ),
        .init(
            id: "editor-numbered-lists-210",
            title: "Numbered lists, done right",
            body: "Type \"1. \" to start a numbered list, the way Notes does it. Tighter spacing between the number and your text, and Return continues the list cleanly.",
            symbolName: "list.number",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "2.1.0",
            showInFeatureGuide: false
        ),
        .init(
            id: "smart-ask-search-310",
            title: "Smarter search in Ask",
            body: "Ask can find entries by meaning, not only matching words. It's optional: a one-time download of a search model that runs on your device. Turn it on in Ask or in Settings.",
            symbolName: "sparkle.magnifyingglass",
            accentColor: .purple,
            tier: .core,
            sinceVersion: "3.1.0"
        ),
        .init(
            id: "reflection-styles-310",
            title: "Reflection styles",
            body: "Choose how today's reflection reads: Gentle, Quiet with only your own words, or Curious with a question about what you wrote. Choose it in Settings.",
            symbolName: "text.quote",
            accentColor: .indigo,
            tier: .core,
            sinceVersion: "3.1.0"
        ),
        .init(
            id: "format-panel-310",
            title: "A clearer format panel",
            body: "Every style, list and color is on screen at once, and each color shows what it does before you tap it.",
            symbolName: "textformat",
            accentColor: .teal,
            tier: .free,
            sinceVersion: "3.1.0",
            showInFeatureGuide: false,
            iOSOnly: true
        ),
        .init(
            id: "writing-310",
            title: "Writing that keeps up",
            body: "The cursor starts where you left off, and a draft keeps its date, font and tags. Type #work, or several tags separated by commas.",
            symbolName: "pencil.line",
            accentColor: .orange,
            tier: .free,
            sinceVersion: "3.1.0",
            showInFeatureGuide: false
        ),
        // One-time notice of the 2026-10-09 privacy policy update (the policy promises an in-app
        // notice for material changes): Cloudflare hosts the model downloads (Gemma and the optional search model).
        .init(
            id: "privacy-policy-310",
            title: "Privacy policy updated",
            body: "Our privacy policy now covers AI model downloads. The Gemma model, on devices that need it, and the optional search model for Ask each download once from models.mirrornotes.org, only when you start the download. Cloudflare hosts it for us and, as with any download, sees your IP address. Your journal never leaves your device. [Read the privacy policy](https://mirrornotes.org/privacy.html)",
            symbolName: "hand.raised.fill",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "3.1.0",
            showInFeatureGuide: false
        ),
        // 3.1.4: the paid-plans notice, two weeks before the 15 November cutover
        // (november-paid-activation.md, owner 2026-10-18). Nothing is gated in 3.1.4.
        .init(
            id: "paid-plans-314",
            title: "Paid plans start \(FeatureCardRegistry.paidPlansStartText)",
            body: "From \(FeatureCardRegistry.paidPlansStartText), the daily reflection, Ask, the weekly digest, the monthly report, the mood timeline and widgets need Core or Deep. Writing, reading, search and iCloud backup stay free, forever. New subscribers get a 7-day free trial.",
            symbolName: "calendar.badge.clock",
            accentColor: MirrorTheme.primary,
            tier: .free,
            sinceVersion: "3.1.4",
            showInFeatureGuide: false
        ),
        .init(
            id: "recently-deleted-314",
            title: "Recently Deleted",
            body: "Deleted entries wait 30 days in Recently Deleted, on all your devices, so you can bring them back. Find it in Entries, under the bookmark menu.",
            symbolName: "trash",
            accentColor: .orange,
            tier: .free,
            sinceVersion: "3.1.4"
        ),
        .init(
            id: "drafts-314",
            title: "Drafts",
            body: "Put an entry aside and start another: tap the drafts button in Write. Pick it up later from the same menu. Drafts stay on this device.",
            symbolName: "doc.text",
            accentColor: .teal,
            tier: .free,
            sinceVersion: "3.1.4"
        ),
        .init(
            id: "collection-in-write-314",
            title: "Collections while you write",
            body: "Tap the folder next to your tags to choose where an entry goes, or make a new collection there.",
            symbolName: "folder",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "3.1.4",
            showInFeatureGuide: false
        ),
        // 3.1.6: what Free keeps once paid plans start (owner, 2026-10-20).
        .init(
            id: "insights-stay-316",
            title: "What's made for you stays yours",
            body: "Every daily reflection, weekly digest and monthly report already made for you stays readable on every plan, in the app and in widgets, including after paid plans start on \(FeatureCardRegistry.paidPlansStartText). New ones need Core or Deep.",
            symbolName: "lock.open",
            accentColor: MirrorTheme.primary,
            tier: .free,
            sinceVersion: "3.1.6",
            showInFeatureGuide: false
        ),
        .init(
            id: "duplicates-314",
            title: "Find duplicates",
            body: "Entries saved twice with the same text show up together, with their dates. Merge them into one; the copies go to Recently Deleted.",
            symbolName: "square.on.square",
            accentColor: .purple,
            tier: .free,
            sinceVersion: "3.1.4"
        ),
        // 3.1.8: the free period is over (15 November 2026). No date in the text: people update
        // weeks later.
        .init(
            id: "paid-plans-318",
            title: "Core and Deep are here",
            body: "The daily reflection, Ask, the weekly digest, the monthly report, the mood timeline and widgets now need Core or Deep. Writing, reading, search and iCloud backup stay free, forever, and everything already made for you stays readable. New subscribers get a 7-day free trial.",
            symbolName: "checkmark.seal",
            accentColor: MirrorTheme.primary,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        // Paper & Ink (owner, 2026-11-07; the colours since 2026-11-06): the whole app, iPhone, iPad
        // and Mac. It also tells Sentinel users their mode was retired (3.1.8).
        .init(
            id: "theme-318",
            title: "A new look: Paper & Ink",
            body: "Warm paper pages with a plum accent, serif titles, and today's reflection on top. Entries show titles, photos and tags at a glance.",
            symbolName: "paintpalette",
            accentColor: MirrorTheme.violet,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        // Sentinel mode retired (owner, 2026-11-07). iPhone and iPad only: the Mac never had it.
        .init(
            id: "sentinel-retired-318",
            title: "Sentinel mode has been retired",
            body: "Everyone now gets Paper & Ink. To see how a reflection was made, turn on Settings › About › Show how insights are made.",
            symbolName: "rectangle.on.rectangle.angled",
            accentColor: MirrorTheme.violet,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false,
            iOSOnly: true,
            requirement: .usedSentinel
        ),
        // Offer codes are redeemed through StoreKit's sheet: iOS, and the Mac app on macOS 15+
        // (RedeemCodeSheet); hidden where the button isn't (macOS 14, the iPhone app on a Mac).
        .init(
            id: "redeem-code-318",
            title: "Have a code?",
            body: "Tap Redeem Code in Settings › Subscription, or at the bottom of the plans screen, to use an App Store offer code.",
            symbolName: "ticket",
            accentColor: .orange,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false,
            requirement: .redeemCode
        ),
        // The Mac editor has its own toolbar and no focus mode.
        .init(
            id: "focus-mode-318",
            title: "Focus mode, just your words",
            body: "Choose Focus mode in the ⋯ menu while you write and everything else steps aside: the toolbar, the starter and the cards. Tap the arrows at the top to bring it all back. Swipe down on the page to hide the keyboard.",
            symbolName: "arrow.up.left.and.arrow.down.right",
            accentColor: MirrorTheme.violet,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false,
            iOSOnly: true
        ),
        .init(
            id: "show-all-318",
            title: "Every past reflection",
            body: "Past reflections and digests now end with Show all, so you can read every one, not just the latest 14.",
            symbolName: "clock.arrow.circlepath",
            accentColor: .teal,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        // The audit of 4 November 2026: the list, search and Insights stopped re-reading every entry.
        .init(
            id: "faster-318",
            title: "Faster with a big journal",
            body: "The Entries list, search and Insights no longer re-read every entry whenever the screen changes, so years of writing stay quick.",
            symbolName: "bolt.fill",
            accentColor: .orange,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        // Kept-out collections (InsightScope): Scratch is offered in Organize on iOS and Mac.
        .init(
            id: "scratch-318",
            title: "Notes that stay out of reflections",
            body: "In Entries, open Manage collections and views and add Scratch for quick notes, checklists and lists. A Scratch note can remind you at a time you pick. Reflections, Ask, mood charts and mood alerts don't read it, and any collection can be kept out the same way.",
            symbolName: "note.text",
            accentColor: .teal,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        .init(
            id: "write-318",
            title: "A calmer Write screen",
            body: "The date is the title, Mood sits beside it, and Delete and focus mode moved into the ⋯ menu. Need a start? Pick a template, write your own, or try Suggestions from your day.",
            symbolName: "square.and.pencil",
            accentColor: MirrorTheme.violet,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false,
            iOSOnly: true,
            requirement: .journalingSuggestions,
            bodyWithoutRequirement: "The date is the title, Mood sits beside it, and Delete and focus mode moved into the ⋯ menu. Need a start? Pick a template or write your own."
        ),
        .init(
            id: "still-open-318",
            title: "Still Open",
            body: "Every checklist item you haven't ticked, from all your entries, in one list. Tick it there or open its entry. It's in the Entries menu beside your saved views.",
            symbolName: "checklist.unchecked",
            accentColor: .green,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        .init(
            id: "links-318",
            title: "Link your entries",
            body: "Select a few words, choose Add Link, then Link to an Entry. Under each entry, Linked from shows the entries that point to it.",
            symbolName: "link",
            accentColor: .blue,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        .init(
            id: "patterns-318",
            title: "Patterns and Year in Review",
            body: "See which moods come with your days, times and tags, and your year in numbers. Counted by the app from your own moods, so nothing is guessed.",
            symbolName: "square.grid.3x3.topleft.filled",
            accentColor: .pink,
            tier: .deep,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false
        ),
        .init(
            id: "watch-318",
            title: "MirrorNotes on Apple Watch",
            body: "Record a voice note, type a quick note or log a mood from your wrist. Each one is saved in MirrorNotes on your iPhone, which keeps your journal's key.",
            symbolName: "applewatch",
            accentColor: .orange,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false,
            iOSOnly: true,
            requirement: .appleWatch
        ),
        .init(
            id: "health-318",
            title: "Moods in Apple Health",
            body: "Turn on Settings › Journal › Save mood check-ins to Health, and each check-in is saved as a State of Mind. MirrorNotes never reads from Health.",
            symbolName: "heart.text.square",
            accentColor: .red,
            tier: .free,
            sinceVersion: "3.1.8",
            showInFeatureGuide: false,
            iOSOnly: true,
            requirement: .appleHealth
        ),
    ]

    /// 15 November 2026, the paid-plans cutover, in the reader's own date format.
    static var paidPlansStart: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 15)) ?? Date()
    }

    static var paidPlansStartText: String {
        paidPlansStart.formatted(.dateTime.day().month(.wide))
    }
}

// MARK: - Service

@Observable
final class FeatureCardService {
    static let shared = FeatureCardService()

    private let lastSeenVersionKey = "mirror.whatsNew.lastSeenVersion"

    var allCards: [FeatureCard] { FeatureCardRegistry.all.filter { $0.showInFeatureGuide }.compactMap { $0.forThisDevice() } }

    /// The Mac has its own version numbers (1.x) while cards carry the iOS release they shipped
    /// in, so a Mac upgrade compared 1.x against "3.1.0" and never showed a card. List only the Mac
    /// version that first shipped an iOS release's cards; later Mac versions with no cards of
    /// their own (1.1.1) need no entry.
    static let macFeatureRelease: [String: String] = [
        "1.1.0": "3.1.0",
        "1.1.4": "3.1.4",
        "1.1.6": "3.1.6",
        "1.1.8": "3.1.8",
    ]

    /// The cards a Mac version shows: those of the newest iOS release whose Mac version is newer
    /// than the last one seen, so a Mac that skipped 1.1.0 still gets 3.1.0's privacy notice and
    /// one that saw 1.1.0 isn't shown the same cards again on 1.1.1. Only Mac versions that
    /// introduced cards are listed in `macFeatureRelease`. Falls back, like iOS, to the newest
    /// release at or below the current version (an already-seen sheet keeps its list).
    static func macWhatsNewCards(lastSeen: String, current: String) -> [FeatureCard] {
        guard let currentVersion = AppVersion(current) else { return [] }
        let last = AppVersion(lastSeen) ?? AppVersion("0.0.0")!
        let shipped = macFeatureRelease
            .compactMap { mac, release in AppVersion(mac).map { ($0, release) } }
            .filter { $0.0 <= currentVersion }
            .sorted { $0.0 < $1.0 }
        guard let release = (shipped.last { $0.0 > last } ?? shipped.last)?.1 else { return [] }
        return FeatureCardRegistry.all.filter { $0.sinceVersion == release && !$0.iOSOnly }
    }

    /// Whether this Mac upgrade brings cards it hasn't shown yet.
    static func macHasUnseenCards(lastSeen: String, current: String) -> Bool {
        guard let currentVersion = AppVersion(current) else { return false }
        let last = AppVersion(lastSeen) ?? AppVersion("0.0.0")!
        return macFeatureRelease.keys.contains { mac in
            guard let version = AppVersion(mac) else { return false }
            return version > last && version <= currentVersion
        }
    }

    var whatsNewCards: [FeatureCard] {
        #if os(macOS)
        return Self.macWhatsNewCards(lastSeen: lastSeenVersion, current: currentAppVersion).compactMap { $0.forThisDevice() }
        #else
        return Self.iOSWhatsNewCards(lastSeen: lastSeenVersion, current: currentAppVersion).compactMap { $0.forThisDevice() }
        #endif
    }

    /// Only the newest release with cards since the last seen version, never the backlog. A device
    /// with no last seen version but a synced profile (a reinstall or a new phone restored from
    /// iCloud skips onboarding, which is what marks a new install seen) read as 0.0.0 and got all 28
    /// cards since 1.0.0 as pages in 3.1.0. The newest release, not the current version's cards: a
    /// version with no cards of its own (3.1.1) must still show the 3.1.0 privacy notice to someone
    /// who skipped 3.1.0.
    static func iOSWhatsNewCards(lastSeen: String, current: String) -> [FeatureCard] {
        guard let last = AppVersion(lastSeen),
              let currentVersion = AppVersion(current) else { return [] }
        let newSinceUpgrade = FeatureCardRegistry.all.filter {
            guard let cardVersion = AppVersion($0.sinceVersion) else { return false }
            return cardVersion > last && cardVersion <= currentVersion
        }
        // Fallback: if already seen this version, still show current version's cards
        guard let newest = newSinceUpgrade.compactMap({ AppVersion($0.sinceVersion) }).max() else {
            return FeatureCardRegistry.all.filter { $0.sinceVersion == current }
        }
        return newSinceUpgrade.filter { AppVersion($0.sinceVersion) == newest }
    }

    var shouldShowWhatsNew: Bool {
        guard let last = AppVersion(lastSeenVersion),
              let current = AppVersion(currentAppVersion) else { return false }
        #if os(macOS)
        return current > last && Self.macHasUnseenCards(lastSeen: lastSeenVersion, current: currentAppVersion)
        #else
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
