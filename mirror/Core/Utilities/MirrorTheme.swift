import SwiftUI
import UIKit

enum MirrorTheme {

    // MARK: - Adaptive color helper

    private static func hex(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { trait in
            let h = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red:   CGFloat((h >> 16) & 0xFF) / 255,
                green: CGFloat((h >> 8)  & 0xFF) / 255,
                blue:  CGFloat(h         & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    // MARK: - Surface tokens

    static let inkBase    = hex(0x08060F, 0xF2EEF8)  // page background
    static let inkMid     = hex(0x110E1C, 0xFFFFFF)  // base card
    static let inkRaised  = hex(0x1C1830, 0xF8F5FF)  // elevated card / sheet
    static let inkBorder  = hex(0x2A2545, 0xE0D9F5)  // dividers, stroke

    // MARK: - Accent tokens

    static let violet      = hex(0x7C5CE4, 0x6341CC)  // primary accent
    static let violetLight = hex(0xA78BFA, 0x7C5CE4)  // secondary labels, tints
    static let violetDim   = hex(0x3D2D8A, 0xEDE8FC)  // tint backgrounds (chips, etc.)
    // ember — warm second accent. 3 uses only: paywall CTA, mood alert, first insight.
    static let ember       = hex(0xF97B8B, 0xE05470)

    // MARK: - Text tokens

    static let textPrimary   = hex(0xEDE9F8, 0x16112A)
    static let textSecondary = hex(0x7A7098, 0x6B6080)
    static let textTertiary  = hex(0x3F3860, 0xA89FC0)

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

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [violet, violetLight], startPoint: .topLeading, endPoint: .bottomTrailing)
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

    static func moodColor(for mood: String) -> Color {
        switch mood {
        case "Joyful":      return Color(red: 1.000, green: 0.835, blue: 0.310)
        case "Grateful":    return Color(red: 0.400, green: 0.733, blue: 0.416)
        case "Peaceful":    return Color(red: 0.506, green: 0.831, blue: 0.980)
        case "Content":     return Color(red: 0.302, green: 0.714, blue: 0.675)
        case "Energized":   return Color(red: 1.000, green: 0.596, blue: 0.000)
        case "Hopeful":     return Color(red: 0.584, green: 0.459, blue: 0.804)
        case "Anxious":     return Color(red: 1.000, green: 0.757, blue: 0.027)
        case "Overwhelmed": return Color(red: 0.937, green: 0.325, blue: 0.314)
        case "Frustrated":  return Color(red: 0.961, green: 0.486, blue: 0.000)
        case "Drained":     return Color(red: 0.620, green: 0.620, blue: 0.620)
        case "Sad":         return Color(red: 0.259, green: 0.647, blue: 0.961)
        case "Numb":        return Color(red: 0.812, green: 0.847, blue: 0.863)
        default:            return violet
        }
    }

    /// Continuous color for an average mood score (1…5), anchored to the
    /// discrete mood colors so aggregate visuals stay on-palette.
    static func moodScoreColor(_ score: Double) -> Color {
        // Anchors: 1 Overwhelmed (red), 2 Frustrated (orange), 3 Numb (gray),
        // 4 Content (teal), 5 Joyful (yellow).
        let anchors: [(Double, Double, Double)] = [
            (0.937, 0.325, 0.314),
            (0.961, 0.486, 0.000),
            (0.812, 0.847, 0.863),
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
