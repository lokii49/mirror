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
