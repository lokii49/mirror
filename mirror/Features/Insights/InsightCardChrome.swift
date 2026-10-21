import SwiftUI

// One grammar for every card on the Insights tab (2026-10-21 design review): the Today
// reflection, the week's mood chart, the weekly digest and the scheduled-generation card
// each had their own header row, chip style and button. A reader re-learned the page every
// scroll. These three pieces are the only header, timestamp and action the cards use now.
// Both themes live here: Classic is the website's card header (accent label, muted time,
// hairline); Sentinel keeps its mono/ember/uppercase voice exactly as the cards had it.

/// Header row: `Label(title, icon)` in the accent, a trailing slot (timestamp, chip, source
/// button), an optional subline, then the hairline that every Insights card draws.
struct InsightCardHeader<Trailing: View, Subline: View>: View {
    let title: Text
    let icon: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var subline: () -> Subline

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder subline: @escaping () -> Subline = { EmptyView() }
    ) {
        self.title = Text(title)
        self.icon = icon
        self.trailing = trailing
        self.subline = subline
    }

    /// A title that is already text (the mood chart names the held dot's date here).
    init(
        text title: Text,
        icon: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder subline: @escaping () -> Subline = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
        self.subline = subline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: isSentinel ? 11 : 12, weight: .bold))
                    }
                    title
                        .font(isSentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .semibold))
                        .textCase(isSentinel ? .uppercase : nil)
                        .tracking(isSentinel ? 0.8 : 0)
                }
                .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                .lineLimit(1)
                Spacer(minLength: 8)
                trailing()
            }
            subline()
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: isSentinel
                            ? [MirrorTheme.ember.opacity(0.40), MirrorTheme.ember.opacity(0.06)]
                            : [MirrorTheme.violet.opacity(0.40), MirrorTheme.violet.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }
}

/// The time or date in a card header's trailing slot. Muted, not mono, in Classic; Sentinel
/// keeps its monospaced readout.
struct InsightCardStamp: View {
    let date: Date
    var format: Date.FormatStyle = .dateTime.hour().minute()
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        Text(date, format: format)
            .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .medium) : .system(size: 12, weight: .medium))
            .foregroundStyle(MirrorTheme.textTertiary)
            .lineLimit(1)
    }
}

/// The one capsule action a card offers ("Read Full Reflection", "Read Full Digest", "Show
/// Less"). Tinted, full width, 40pt; Sentinel's rectangular ember version is unchanged.
struct InsightCardAction: View {
    let title: LocalizedStringKey
    let sentinelTitle: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void
    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(isSentinel ? sentinelTitle : title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .font(isSentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 14, weight: .semibold))
            .kerning(isSentinel ? 0.4 : 0)
            .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                isSentinel ? AnyShapeStyle(MirrorTheme.ember.opacity(0.12)) : AnyShapeStyle(MirrorTheme.violetDim),
                in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if isSentinel {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MirrorTheme.ember.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small label chip inside a card (the digest's section names in its collapsed state).
/// One style for all of them: the section is told by its icon and word, not by a colour of
/// its own, so the mood colours stay the only colour that carries meaning on the tab.
struct InsightCardChip: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(isSentinel ? MirrorTheme.mono(9.5, weight: .bold) : .system(size: 11, weight: .semibold))
        .textCase(isSentinel ? .uppercase : nil)
        .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            isSentinel ? AnyShapeStyle(MirrorTheme.ember.opacity(0.12)) : AnyShapeStyle(MirrorTheme.inkRaised),
            in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
        )
        .overlay {
            if isSentinel {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1)
            }
        }
    }
}
