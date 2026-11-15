import SwiftUI

/// Shared chrome for every settings screen (root Settings + the four pushed
/// sub-screens).

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @Environment(\.settingsEmbedded) private var embedded

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .scaledFont(embedded ? 11 : 12, weight: .semibold, design: .default)
                .foregroundStyle(MirrorTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(1.0)
                .padding(.bottom, embedded ? 10 : 14)
            VStack(spacing: 0) { content }
        }
        .padding(embedded ? 16 : 18)
        .themedCard(cornerRadius: embedded ? 14 : 24)
    }
}

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let iconColor: Color
    @Environment(\.settingsEmbedded) private var embedded

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: embedded ? 26 : 32, height: embedded ? 26 : 32)
                Image(systemName: systemImage)
                    .scaledFont(embedded ? 12 : 14, weight: .medium)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
            Text(title)
                .scaledFont(embedded ? 13 : 15)
                .foregroundStyle(MirrorTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Short trailing "value" text (time, day name, version, language). Use for
/// simple Text values only; Menu-based pickers keep their own label styling.
struct SettingsValueText: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(13, weight: .regular, design: .default)
            .foregroundStyle(MirrorTheme.textSecondary)
    }
}

struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(MirrorTheme.textTertiary)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(MirrorTheme.inkBorder).padding(.leading, 48)
    }
}

/// Locked-tier badge ("Core" / "Deep") shown on gated rows.
struct SettingsTierBadge: View {
    let tier: LocalizedStringKey

    var body: some View {
        Label(tier, systemImage: "lock.fill")
            .scaledFont(12, weight: .semibold, design: .default)
            .textCase(nil)
            .foregroundStyle(MirrorTheme.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                MirrorTheme.primary.opacity(0.12),
                in: Capsule()
            )
    }
}

/// Nav-link row for the root Settings screen's category list
/// (Journal / Your Data / About / Developer).
struct SettingsCategoryRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: systemImage)
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(15, weight: .semibold, design: .default)
                    .kerning(0)
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text(subtitle)
                    .scaledFont(12.5)
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer(minLength: 0)
            SettingsChevron()
        }
        .padding(16)
        .themedCard(cornerRadius: 18)
    }
}

// MARK: - Embedding in the Mac Settings window

private struct SettingsEmbeddedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when a settings screen is shown inside the Mac Settings window's own scroll view.
    var settingsEmbedded: Bool {
        get { self[SettingsEmbeddedKey.self] }
        set { self[SettingsEmbeddedKey.self] = newValue }
    }
}

/// The root scroll view of a settings screen. Embedded in a tab of the Mac Settings window, the
/// window supplies the scroll view (so two screens can share one tab) and this is just the content.
struct SettingsScroll<Content: View>: View {
    @Environment(\.settingsEmbedded) private var embedded
    @ViewBuilder var content: Content

    var body: some View {
        if embedded { content } else { ScrollView { content } }
    }
}

extension View {
    /// Embedded panes share the Settings window's title. Publishing their own titles
    /// makes SwiftUI and the AppKit window-title observer repeatedly overwrite each other.
    func settingsNavigationTitle(_ title: LocalizedStringKey) -> some View {
        modifier(SettingsNavigationTitle(title: title))
    }

    /// Esc closes a sheet on Mac (there is no swipe down); no effect on iPhone and iPad.
    func cancelActionOnMac() -> some View {
        #if os(macOS)
        keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }
}

private struct SettingsNavigationTitle: ViewModifier {
    @Environment(\.settingsEmbedded) private var embedded
    let title: LocalizedStringKey

    func body(content: Content) -> some View {
        if embedded { content } else { content.navigationTitle(title) }
    }
}
