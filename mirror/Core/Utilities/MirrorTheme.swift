import SwiftUI

enum MirrorTheme {
    static let primary = Color.accentColor
    static let primaryUI = UIColor.tintColor

    static let bgBase = Color(.systemGroupedBackground)
    static let bgCard = Color(.secondarySystemGroupedBackground)
    static let bgGroup = Color(.tertiarySystemGroupedBackground)

    static let red = Color(.systemRed)
    static let yellow = Color(.systemYellow)
    static let green = Color(.systemGreen)
    static let blue = Color(.systemBlue)
    static let purple = primary

    static let palette: [Color] = [red, yellow, green, blue, purple]
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [primary, primary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let moodOptions: [String] = [
        "Joyful", "Grateful", "Peaceful", "Content", "Energized", "Hopeful",
        "Anxious", "Overwhelmed", "Frustrated", "Drained", "Sad", "Numb"
    ]

    static func moodColor(for mood: String) -> Color {
        switch mood {
        case "Joyful":      return Color(red: 1.000, green: 0.835, blue: 0.310) // #FFD54F
        case "Grateful":    return Color(red: 0.400, green: 0.733, blue: 0.416) // #66BB6A
        case "Peaceful":    return Color(red: 0.506, green: 0.831, blue: 0.980) // #81D4FA
        case "Content":     return Color(red: 0.302, green: 0.714, blue: 0.675) // #4DB6AC
        case "Energized":   return Color(red: 1.000, green: 0.596, blue: 0.000) // #FF9800
        case "Hopeful":     return Color(red: 0.584, green: 0.459, blue: 0.804) // #9575CD
        case "Anxious":     return Color(red: 1.000, green: 0.757, blue: 0.027) // #FFC107
        case "Overwhelmed": return Color(red: 0.937, green: 0.325, blue: 0.314) // #EF5350
        case "Frustrated":  return Color(red: 0.961, green: 0.486, blue: 0.000) // #F57C00
        case "Drained":     return Color(red: 0.620, green: 0.620, blue: 0.620) // #9E9E9E
        case "Sad":         return Color(red: 0.259, green: 0.647, blue: 0.961) // #42A5F5
        case "Numb":        return Color(red: 0.812, green: 0.847, blue: 0.863) // #CFD8DC
        default:            return .accentColor
        }
    }

    static let cornerCard: CGFloat = 20
    static let cornerPill: CGFloat = 999
    static let cornerChip: CGFloat = 10

    static func entryColor(index: Int) -> Color {
        palette[abs(index) % palette.count]
    }
}

// MARK: - View Modifiers

extension View {
    func mirrorCard(color: Color = MirrorTheme.primary) -> some View {
        self
            .background(MirrorTheme.bgCard, in: RoundedRectangle(cornerRadius: MirrorTheme.cornerCard, style: .continuous))
    }

    func mirrorChip(_ color: Color = MirrorTheme.primary) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    /// Standard glass surface — used for most cards.
    func futureSurface(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(glassBorderGradient, lineWidth: 1)
            }
    }

    /// Accent-bordered card — used for the active/highlighted insight.
    func accentCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MirrorTheme.accentGradient, lineWidth: 1.5)
                    .opacity(0.55)
            }
    }

    /// Soft ambient glow beneath a card.
    func glowShadow(color: Color = MirrorTheme.primary, radius: CGFloat = 28) -> some View {
        self.shadow(color: color.opacity(0.18), radius: radius, x: 0, y: 10)
    }

    private var glassBorderGradient: LinearGradient {
        LinearGradient(
            colors: [Color(white: 1, opacity: 0.22), Color(white: 0, opacity: 0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
