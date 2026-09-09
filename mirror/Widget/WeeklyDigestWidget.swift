import WidgetKit
import SwiftUI

// Palette + app-group reads live in WidgetTheme.swift (shared across all widgets).
private let wBgTop      = WidgetTheme.bgTop
private let wBgBottom   = WidgetTheme.bgBottom
private let wViLight    = WidgetTheme.violetLight
private let wEmber      = WidgetTheme.ember
private let wSentinelBg = WidgetTheme.sentinelBg

private func widgetIsSentinel() -> Bool { WidgetShared.isSentinel() }

// MARK: - Timeline

struct DigestWidgetEntry: TimelineEntry {
    let date: Date
    /// The "THIS WEEK'S THEME" section body, pushed by `WidgetBridge.syncWeeklyDigest`.
    let themeText: String?
    /// True when the stored digest is for the current ISO week — a Monday rollover
    /// makes last week's theme stale before the new digest generates (Sunday task).
    let isCurrentWeek: Bool
}

struct DigestWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DigestWidgetEntry {
        DigestWidgetEntry(
            date: .now,
            themeText: "A week of holding steady while the ground kept shifting under you.",
            isCurrentWeek: true
        )
    }
    func getSnapshot(in context: Context, completion: @escaping (DigestWidgetEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestWidgetEntry>) -> Void) {
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [makeEntry()], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> DigestWidgetEntry {
        let defaults = UserDefaults(suiteName: WidgetShared.appGroupID)
        let text = defaults?.string(forKey: WidgetShared.digestThemeKey)
        let storedWeek = defaults?.string(forKey: WidgetShared.digestWeekKey) ?? ""
        let thisWeek = DateHelpers.weekIdentifier(for: Date())
        return DigestWidgetEntry(date: .now, themeText: text, isCurrentWeek: storedWeek == thisWeek)
    }
}

// MARK: - Unlocked (small)

private struct DigestSmallView: View {
    let entry: DigestWidgetEntry
    private let sentinel = widgetIsSentinel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Classic: the same oversized serif quote mark NudgeSmallView uses,
            // so the two insight widgets read as one family.
            if !sentinel {
                Text("\u{201C}")
                    .font(.system(size: 96, weight: .black, design: .serif))
                    .foregroundStyle(wViLight.opacity(0.15))
                    .offset(x: -6, y: -18)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if let text = entry.themeText, entry.isCurrentWeek {
                    Text(text)
                        .font(sentinel ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(6)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: false)
                } else {
                    Text(sentinel ? "DIGEST COMPILING…" : "This week's digest\narrives Sunday…")
                        .font(sentinel ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.50))
                        .italic(!sentinel)
                }

                Spacer(minLength: 10)

                HStack(spacing: 4) {
                    Image(systemName: sentinel ? "square.stack.3d.up" : "calendar")
                        .font(.system(size: 8, weight: .semibold))
                    Text(sentinel ? "WEEKLY BRIEFING" : "WEEKLY DIGEST")
                        .font(.system(size: 8, weight: .bold, design: sentinel ? .monospaced : .default))
                        .tracking(1.8)
                }
                .foregroundStyle(sentinel ? wEmber.opacity(0.75) : wViLight.opacity(0.60))

                // Sentinel: ember hairline under the label, matching the mode's
                // "transmission divider" motif elsewhere in the widget set.
                if sentinel {
                    Rectangle()
                        .fill(wEmber.opacity(0.35))
                        .frame(height: 1)
                        .padding(.top, 5)
                }
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            if sentinel {
                wSentinelBg
            } else {
                LinearGradient(colors: [wBgTop, wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .widgetURL(URL(string: "mirror://insights"))
    }
}

// MARK: - Locked

private struct DigestLockedView: View {
    private let sentinel = widgetIsSentinel()

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: sentinel ? "square.stack.3d.up" : "calendar")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(sentinel ? wEmber.opacity(0.8) : .white.opacity(0.7))
            Text(sentinel ? "WEEKLY BRIEFING" : "Weekly Digest")
                .font(sentinel ? .system(size: 12, weight: .bold, design: .monospaced) : .system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text(sentinel ? "CORE · $2.99/MO" : "Core · $2.99/mo")
                .font(sentinel ? .system(size: 10, weight: .medium, design: .monospaced) : .system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            if sentinel {
                wSentinelBg
            } else {
                LinearGradient(colors: [wBgTop.opacity(0.8), wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .widgetURL(URL(string: "mirror://upgrade"))
    }
}

// MARK: - Dispatcher

struct DigestWidgetView: View {
    let entry: DigestWidgetEntry

    var body: some View {
        if WidgetShared.isSubscribed() {
            DigestSmallView(entry: entry)
        } else {
            DigestLockedView()
        }
    }
}

// MARK: - Widget

struct MirrorWeeklyDigestWidget: Widget {
    let kind = "MirrorWeeklyDigestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DigestWidgetProvider()) { entry in
            DigestWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly Digest")
        .description("This week's theme from your journal, at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Previews
// `#Preview` + `WidgetPreviewContext` is the only path that renders
// `.containerBackground(for: .widget)` faithfully outside a real widget host
// (an in-app gallery screen can't — the modifier is inert there). Not
// CLI-scriptable; verify these in Xcode's canvas.
//
// `widgetIsSentinel()` / `WidgetShared.tier()` read the app group, which a
// preview process has no data in, so each preview seeds the two keys it needs.
// This only touches the dev machine's container.

private func seedWidgetPreview(sentinel: Bool, tier: String) {
    let d = UserDefaults(suiteName: WidgetShared.appGroupID)
    d?.set(sentinel ? "sentinel" : "classic", forKey: "widget.displayMode")
    d?.set(tier, forKey: "widget.tier")
}

#Preview("Classic", as: .systemSmall) {
    seedWidgetPreview(sentinel: false, tier: "core")
    return MirrorWeeklyDigestWidget()
} timeline: {
    DigestWidgetEntry(date: .now, themeText: "A week of holding steady while the ground kept shifting under you.", isCurrentWeek: true)
    DigestWidgetEntry(date: .now, themeText: nil, isCurrentWeek: false)
}

#Preview("Sentinel", as: .systemSmall) {
    seedWidgetPreview(sentinel: true, tier: "core")
    return MirrorWeeklyDigestWidget()
} timeline: {
    DigestWidgetEntry(date: .now, themeText: "Recovery and pressure kept trading places all week.", isCurrentWeek: true)
}

#Preview("Locked", as: .systemSmall) {
    seedWidgetPreview(sentinel: false, tier: "free")
    return MirrorWeeklyDigestWidget()
} timeline: {
    DigestWidgetEntry(date: .now, themeText: nil, isCurrentWeek: false)
}
