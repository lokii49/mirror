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
    static let moodSpectrum: [Color] = [.indigo, .blue, .gray, .green, primary, .yellow, .red]

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [primary, primary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cornerCard: CGFloat = 20
    static let cornerPill: CGFloat = 999
    static let cornerChip: CGFloat = 10

    static func entryColor(index: Int) -> Color {
        palette[abs(index) % palette.count]
    }

    static func moodColor(_ mood: String?) -> Color {
        switch mood {
        case "Heavy": return .indigo
        case "Quiet": return .blue
        case "Neutral": return .gray
        case "Calm": return .green
        case "Hopeful": return primary
        case "Joyful": return .yellow
        case "Fired Up": return .red
        default: return primary
        }
    }

    static func moodSymbol(_ mood: String?) -> String {
        switch mood {
        case "Heavy": return "cloud.rain"
        case "Quiet": return "moon"
        case "Neutral": return "circle.dashed"
        case "Calm": return "leaf"
        case "Hopeful": return "sparkle"
        case "Joyful": return "sun.max"
        case "Fired Up": return "flame"
        default: return "circle"
        }
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
