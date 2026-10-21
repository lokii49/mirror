import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MirrorTheme {

    // MARK: - Adaptive color helper

    static func hex(_ dark: UInt32, _ light: UInt32) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let h = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((h >> 16) & 0xFF) / 255,
                green:   CGFloat((h >> 8)  & 0xFF) / 255,
                blue:    CGFloat(h         & 0xFF) / 255,
                alpha:   1
            )
        })
        #else
        return Color(UIColor { trait in
            let h = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red:   CGFloat((h >> 16) & 0xFF) / 255,
                green: CGFloat((h >> 8)  & 0xFF) / 255,
                blue:  CGFloat(h         & 0xFF) / 255,
                alpha: 1
            )
        })
        #endif
    }

    // MARK: - Surface tokens

    // Dark steps (2026-10-21 design review): page #08060F → card #15111F → raised #1E1933.
    // The old card (#110E1C) sat 1.3:1 above the page and read as ink on ink; cards only
    // separated by their border. Light values are unchanged. Widgets mirror the dark values
    // in `WidgetTheme`, asserted by `WidgetThemeTokenTests`.
    static let inkBase    = hex(0x08060F, 0xF2EEF8)  // page background
    static let inkMid     = hex(0x15111F, 0xFFFFFF)  // base card
    static let inkRaised  = hex(0x1E1933, 0xF8F5FF)  // elevated card / sheet
    static let inkBorder  = hex(0x2A2545, 0xE0D9F5)  // dividers, stroke

    // MARK: - Accent tokens

    static let violet      = hex(0x7C5CE4, 0x6341CC)  // primary accent
    static let violetLight = hex(0xA78BFA, 0x7C5CE4)  // secondary labels, tints
    static let violetDim   = hex(0x3D2D8A, 0xEDE8FC)  // tint backgrounds (chips, etc.)
    // ember — warm second accent. 3 uses only: paywall CTA, mood alert, first insight.
    static let ember       = hex(0xF97B8B, 0xE05470)
    /// Fill for buttons that carry white text. `violet` in dark mode (#7C5CE4) puts white at
    /// 4.7:1; this deeper step reaches 5.4:1. Light mode is the same violet as the accent.
    /// Accent-coloured *text* on dark surfaces keeps `violet`; only filled controls use this.
    static let buttonFill  = hex(0x6E4FE0, 0x6341CC)

    // MARK: - Text tokens

    static let textPrimary   = hex(0xEDE9F8, 0x16112A)
    static let textSecondary = hex(0x7A7098, 0x6B6080)
    // Muted text (dates, timestamps, labels; ~50 uses) now reads at 4.5:1 or better on every
    // surface in both modes. It was #A89FC0 light / #3F3860 dark — 2.2:1 and under 2:1 — the
    // same colour the website darkened on 2026-10-21 to pass its accessibility audit; the three
    // surfaces use one value again.
    static let textTertiary  = hex(0x9087B0, 0x6E6587)

    // MARK: - Legacy aliases (kept for backward compat)

    static let primary   = Color.accentColor           // tracks AccentColor.colorset (#7C5CE4 / #A78BFA)
    static let primaryUI = UIColor.tintColor

    static let bgBase  = inkBase
    static let bgCard  = inkMid
    static let bgGroup = inkRaised

    static let red    = Color(.systemRed)
    static let yellow = Color(.systemYellow)
    static let green  = Color(.systemGreen)
    static let blue   = Color(.systemBlue)
    static let purple = violet

    static let palette: [Color] = [red, yellow, green, blue, purple]

    /// The fill behind white-text CTAs (paywall, rate-us, onboarding). It used to run
    /// `violet` → `violetLight`, whose dark-mode end (#A78BFA) left white at 2.7:1; it now runs
    /// `buttonFill` → #7C5CE4 in both modes, 5.4→4.7:1 dark and 6.7→4.7:1 light (light mode's
    /// colours are the same as before). Measured 2026-10-21.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [buttonFill, hex(0x7C5CE4, 0x7C5CE4)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Mood

    static let moodOptions: [String] = [
        "Joyful", "Grateful", "Peaceful", "Content", "Energized", "Hopeful",
        "Anxious", "Overwhelmed", "Frustrated", "Drained", "Sad", "Numb"
    ]

    static let moodScore: [String: Double] = [
        "Joyful": 5, "Grateful": 5, "Peaceful": 4, "Content": 4, "Energized": 4, "Hopeful": 4,
        "Anxious": 2, "Overwhelmed": 1, "Frustrated": 2, "Drained": 1, "Sad": 1, "Numb": 2
    ]

    static let negativeMoods: Set<String> = [
        "Anxious", "Overwhelmed", "Frustrated", "Drained", "Sad", "Numb"
    ]

    static func localizedMoodName(for mood: String) -> String {
        switch mood {
        case "Joyful": return String(localized: "Joyful", comment: "Mood label")
        case "Grateful": return String(localized: "Grateful", comment: "Mood label")
        case "Peaceful": return String(localized: "Peaceful", comment: "Mood label")
        case "Content": return String(localized: "Content", comment: "Mood label")
        case "Energized": return String(localized: "Energized", comment: "Mood label")
        case "Hopeful": return String(localized: "Hopeful", comment: "Mood label")
        case "Anxious": return String(localized: "Anxious", comment: "Mood label")
        case "Overwhelmed": return String(localized: "Overwhelmed", comment: "Mood label")
        case "Frustrated": return String(localized: "Frustrated", comment: "Mood label")
        case "Drained": return String(localized: "Drained", comment: "Mood label")
        case "Sad": return String(localized: "Sad", comment: "Mood label")
        case "Numb": return String(localized: "Numb", comment: "Mood label")
        default: return mood
        }
    }

    static func localizedTagName(for tag: String) -> String {
        switch tag {
        case "therapy": return String(localized: "therapy", comment: "Default tag suggestion")
        case "work": return String(localized: "work", comment: "Default tag suggestion")
        case "personal": return String(localized: "personal", comment: "Default tag suggestion")
        case "idea": return String(localized: "idea", comment: "Default tag suggestion")
        case "dream": return String(localized: "dream", comment: "Default tag suggestion")
        default: return tag
        }
    }

    /// Valence is encoded in saturation (2026-10-21 design review): the six good moods stay
    /// bright, the six difficult ones are dusted versions of their hue family. Before this,
    /// Joyful (#FFD54F) and Anxious (#FFC107) were both yellow and Energized/Frustrated both
    /// orange, so a good day and an anxious day looked alike in the week strip (ΔE 4.9, the
    /// worst pair of the twelve; now 7.4). Colour alone still can't separate twelve moods for
    /// colour-blind readers, so where a mood shows as colour only (day tiles, timeline dots)
    /// the view adds a thin ink ring for `negativeMoods` — see `moodRing(for:)`.
    /// The website's mood map carries the same twelve values.
    static func moodColor(for mood: String) -> Color {
        switch mood {
        case "Joyful":      return Color(red: 1.000, green: 0.835, blue: 0.310)  // #FFD54F
        case "Grateful":    return Color(red: 0.400, green: 0.733, blue: 0.416)  // #66BB6A
        case "Peaceful":    return Color(red: 0.506, green: 0.831, blue: 0.980)  // #81D4FA
        case "Content":     return Color(red: 0.302, green: 0.714, blue: 0.675)  // #4DB6AC
        case "Energized":   return Color(red: 1.000, green: 0.596, blue: 0.000)  // #FF9800
        case "Hopeful":     return Color(red: 0.584, green: 0.459, blue: 0.804)  // #9575CD
        case "Anxious":     return Color(red: 0.831, green: 0.659, blue: 0.294)  // #D4A84B dusty amber
        case "Overwhelmed": return Color(red: 0.851, green: 0.416, blue: 0.388)  // #D96A63 dusty red
        case "Frustrated":  return Color(red: 0.851, green: 0.541, blue: 0.310)  // #D98A4F dusty orange
        case "Drained":     return Color(red: 0.604, green: 0.588, blue: 0.639)  // #9A96A3 violet grey
        case "Sad":         return Color(red: 0.416, green: 0.624, blue: 0.820)  // #6A9FD1 dusty blue
        case "Numb":        return Color(red: 0.765, green: 0.796, blue: 0.820)  // #C3CBD1 pale grey
        default:            return violet
        }
    }

    /// The second cue for valence where a mood is shown as colour alone (day tiles in the
    /// calendar strips, dots on the mood charts): difficult moods get a thin ink ring, good
    /// moods none. Twelve hues cannot be told apart by colour-blind readers (validator floor
    /// ΔE ≈ 2–3 on the gray/teal pairs whatever the values), so good/hard has to survive
    /// without the hue. Returns nil for good moods and for unknown ones.
    static func moodRing(for mood: String) -> Color? {
        negativeMoods.contains(mood) ? textPrimary.opacity(0.55) : nil
    }

    /// Readable label/dot color for content drawn directly on top of
    /// `moodColor(for:)` at full opacity (a selected mood chip). Mood colours
    /// whose relative luminance is above ~0.3 — Joyful, Numb, Peaceful, Anxious,
    /// and since the 2026-10-21 dusting also Frustrated, Drained and Sad (white
    /// on those lands near 2.8:1) — get dark text; the rest keep white. Fixed
    /// black, not `textPrimary` — this is contrast against a hardcoded mood
    /// color, not the app's light/dark theme, so it shouldn't flip to near-white
    /// again in dark mode.
    static func moodOnColorText(for mood: String) -> Color {
        switch mood {
        case "Joyful", "Numb", "Peaceful", "Anxious", "Frustrated", "Drained", "Sad":
            return Color.black.opacity(0.78)
        default:
            return .white
        }
    }

    /// Continuous color for an average mood score (1…5), anchored to the
    /// discrete mood colors so aggregate visuals stay on-palette.
    static func moodScoreColor(_ score: Double) -> Color {
        // Anchors: 1 Overwhelmed (dusty red), 2 Frustrated (dusty orange), 3 Numb (pale grey),
        // 4 Content (teal), 5 Joyful (yellow) — the same values as `moodColor(for:)`.
        let anchors: [(Double, Double, Double)] = [
            (0.851, 0.416, 0.388),
            (0.851, 0.541, 0.310),
            (0.765, 0.796, 0.820),
            (0.302, 0.714, 0.675),
            (1.000, 0.835, 0.310)
        ]
        let clamped = min(max(score, 1), 5)
        let lower = min(Int(clamped) - 1, anchors.count - 2)
        let t = clamped - Double(lower + 1)
        let a = anchors[lower], b = anchors[lower + 1]
        return Color(
            red: a.0 + (b.0 - a.0) * t,
            green: a.1 + (b.1 - a.1) * t,
            blue: a.2 + (b.2 - a.2) * t
        )
    }

    // MARK: - Sentinel mode type role

    /// HUD readouts (XP, rank, log ids, timestamps) — the one new type role
    /// Sentinel mode adds. Route every HUD numeral/label through this
    /// instead of inline `.font(.system(..., design: .monospaced))` calls.
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Shared constants

    static let cornerCard: CGFloat = 20
    static let cornerPill: CGFloat = 999
    static let cornerChip: CGFloat = 10

    static func entryColor(index: Int) -> Color {
        palette[abs(index) % palette.count]
    }
}

// MARK: - View Modifiers

extension View {

    /// Base card — list rows, standard cards.
    func inkSurface(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MirrorTheme.inkMid)
                    .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MirrorTheme.inkBorder, lineWidth: 1)
            }
    }

    /// Elevated card — modals, insight cards, sheets.
    func inkCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MirrorTheme.inkRaised)
                    .shadow(color: MirrorTheme.violet.opacity(0.12), radius: 20, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MirrorTheme.inkBorder, lineWidth: 1)
            }
    }

    /// Hero card — daily nudge, paywall hero. The featured moment.
    func inkHero(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MirrorTheme.inkRaised)
                    .shadow(color: MirrorTheme.violet.opacity(0.22), radius: 32, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [MirrorTheme.violet.opacity(0.5), MirrorTheme.violetLight.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
    }

    /// Standard glass surface — kept for backward compat, now uses inkMid.
    func futureSurface(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MirrorTheme.inkMid)
                    .shadow(color: .black.opacity(0.09), radius: 14, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MirrorTheme.inkBorder, lineWidth: 1)
            }
    }

    /// Accent-bordered card — used for the active/highlighted insight.
    func accentCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MirrorTheme.violet.opacity(0.10), MirrorTheme.inkMid],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: MirrorTheme.violet.opacity(0.22), radius: 22, x: 0, y: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MirrorTheme.accentGradient, lineWidth: 2.0)
                    .opacity(0.80)
            }
    }

    /// Mode-aware replacement for `.inkSurface` — Classic keeps the rounded
    /// card; Sentinel switches to a rectangular hairline-bordered panel.
    /// Reads displayMode itself so call sites don't thread it through.
    func themedCard(cornerRadius: CGFloat = 20, classicBase: ThemedCardClassicBase = .surface) -> some View {
        modifier(ThemedCardModifier(cornerRadius: cornerRadius, isHero: false, classicBase: classicBase))
    }

    /// Same as `themedCard`, plus the viewfinder corner-bracket overlay in
    /// Sentinel mode. Reserve for the one hero card per screen — that
    /// restraint is what makes the brackets read as a signature instead of
    /// visual noise.
    func themedHeroCard(cornerRadius: CGFloat = 20, classicBase: ThemedCardClassicBase = .surface) -> some View {
        modifier(ThemedCardModifier(cornerRadius: cornerRadius, isHero: true, classicBase: classicBase))
    }

    func mirrorCard(color: Color = MirrorTheme.violet) -> some View {
        self
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: MirrorTheme.cornerCard, style: .continuous))
    }

    func mirrorChip(_ color: Color = MirrorTheme.violet) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    func glowShadow(color: Color = MirrorTheme.violet, radius: CGFloat = 28) -> some View {
        self.shadow(color: color.opacity(0.25), radius: radius, x: 0, y: 8)
    }
}

/// Which existing Classic card style a themedCard/themedHeroCard falls back
/// to when displayMode is .classic — keeps Classic mode pixel-identical to
/// before Sentinel mode existed, even for cards that used the stronger
/// `.inkCard` elevation rather than the default `.inkSurface`.
enum ThemedCardClassicBase {
    case surface, elevated, hero
}

private struct ThemedCardModifier: ViewModifier {
    @Environment(\.appDisplayMode) private var displayMode
    let cornerRadius: CGFloat
    let isHero: Bool
    var classicBase: ThemedCardClassicBase = .surface

    func body(content: Content) -> some View {
        if displayMode == .sentinel {
            content
                .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MirrorTheme.ember.opacity(isHero ? 0.45 : 0.24), lineWidth: 1)
                }
                .overlay {
                    if isHero { ViewfinderCorners() }
                }
        } else {
            switch classicBase {
            case .surface:  content.inkSurface(cornerRadius: cornerRadius)
            case .elevated: content.inkCard(cornerRadius: cornerRadius)
            case .hero:     content.inkHero(cornerRadius: cornerRadius)
            }
        }
    }
}

/// The Sentinel-mode signature motif — four L-shaped corner brackets, like a
/// camera viewfinder. Reserved for hero cards only (see themedHeroCard) so
/// it reads as one deliberate accent per screen, not decoration everywhere.
/// Faint HUD grid, drawn once per screen as an ignoresSafeArea backdrop.
/// Never load-bearing for legibility — kept at 5% opacity so it reads as
/// texture, not noise, behind actual content.
struct SentinelGridBackground: View {
    var spacing: CGFloat = 28
    var lineColor: Color = MirrorTheme.violetLight

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(lineColor.opacity(0.05)), lineWidth: 1)
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor.opacity(0.05)), lineWidth: 1)
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

struct ViewfinderCorners: View {
    var inset: CGFloat = -6
    var length: CGFloat = 12
    var color: Color = MirrorTheme.ember

    private func bracket(_ corner: UnitPoint) -> some View {
        Path { path in
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
            case .topTrailing:
                path.move(to: CGPoint(x: -length, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: length))
            case .bottomLeading:
                path.move(to: CGPoint(x: 0, y: -length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
            default: // bottomTrailing
                path.move(to: CGPoint(x: -length, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: -length))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    var body: some View {
        GeometryReader { geo in
            bracket(.topLeading).offset(x: inset, y: inset)
            bracket(.topTrailing).offset(x: geo.size.width - inset, y: inset)
            bracket(.bottomLeading).offset(x: inset, y: geo.size.height - inset)
            bracket(.bottomTrailing).offset(x: geo.size.width - inset, y: geo.size.height - inset)
        }
        .opacity(0.85)
        .allowsHitTesting(false)
    }
}

/// Serif body text for reading (reflections, Ask answers, digests, reports) that follows the
/// person's text size; it was a fixed point size, so Dynamic Type left it unchanged (backlog A19).
/// `size` is the size at the default setting; it scales relative to Body.
private struct ReadingFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .serif))
    }
}

extension View {
    func readingFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ReadingFont(size: size, weight: weight))
    }
}

