import SwiftUI

/// Shared chrome for every settings screen (root Config + the four pushed
/// sub-screens). Each reads displayMode itself so every screen that uses
/// them gets Sentinel theming automatically, with no per-row edits needed
/// when a new settings screen is added later.

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .semibold))
                .foregroundStyle(MirrorTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(displayMode == .sentinel ? 0.6 : 1.0)
                .padding(.bottom, 14)
            VStack(spacing: 0) { content }
        }
        .padding(18)
        .themedCard(cornerRadius: 24)
    }
}

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let iconColor: Color
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(iconColor.opacity(0.3), lineWidth: 1)
                }
            }
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(MirrorTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Short trailing "value" text (time, day name, version, language) — mono
/// in Sentinel since these are data readouts, not prose. Use for simple
/// Text values only; Menu-based pickers keep their own label styling.
struct SettingsValueText: View {
    let text: String
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        Text(text)
            .font(displayMode == .sentinel ? MirrorTheme.mono(12.5) : .system(size: 13))
            .foregroundStyle(MirrorTheme.textSecondary)
    }
}

struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MirrorTheme.textTertiary)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(MirrorTheme.inkBorder).padding(.leading, 48)
    }
}

/// Locked-tier badge ("Core" / "Deep") shown on gated rows — rectangular
/// mono in Sentinel, matching the lock chips used elsewhere in the app.
struct SettingsTierBadge: View {
    let tier: LocalizedStringKey
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        Label(tier, systemImage: "lock.fill")
            .font(displayMode == .sentinel ? MirrorTheme.mono(10.5, weight: .bold) : .system(size: 12, weight: .semibold))
            .textCase(displayMode == .sentinel ? .uppercase : nil)
            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary).opacity(0.12),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1)
                }
            }
    }
}

/// Rectangular nav-link row for the root Config screen's category list
/// (Protocol / Archive / Manual / Diagnostics). Classic keeps the plain
/// settingsRowLabel + chevron look via its own call site.
struct SettingsCategoryRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let iconColor: Color
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: displayMode == .sentinel ? 8 : 12, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(displayMode == .sentinel ? MirrorTheme.mono(14, weight: .bold) : .system(size: 15, weight: .semibold))
                    .kerning(displayMode == .sentinel ? 0.3 : 0)
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer(minLength: 0)
            SettingsChevron()
        }
        .padding(16)
        .themedCard(cornerRadius: 18)
    }
}
