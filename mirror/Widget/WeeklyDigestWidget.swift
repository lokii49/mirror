import WidgetKit
import SwiftUI

// Palette + app-group reads live in WidgetTheme.swift (shared across all widgets).
private let wBgTop      = WidgetTheme.bgTop
private let wBgBottom   = WidgetTheme.bgBottom
private let wViLight    = WidgetTheme.violetLight

// MARK: - Timeline

struct DigestWidgetEntry: TimelineEntry {
    let date: Date
    /// The "THIS WEEK'S THEME" section body, pushed by `WidgetBridge.syncWeeklyDigest`.
    let themeText: String?
    /// True when the stored digest is for the current ISO week — a Monday rollover
    /// makes last week's theme stale before the new digest generates (Sunday task).
    let isCurrentWeek: Bool
    /// The stored theme is last week's: shown labelled until this week's arrives (A16).
    var isPreviousWeek = false
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
        let period = WidgetShared.storedPeriod(
            storedWeek, current: DateHelpers.digestWeekIdentifier(for: Date()), previous: WidgetShared.previousDigestWeek(before: Date())
        )
        return DigestWidgetEntry(date: .now, themeText: text, isCurrentWeek: period == .current, isPreviousWeek: period == .previous)
    }
}

// MARK: - Unlocked (small + large)

private struct DigestUnlockedView: View {
    let entry: DigestWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var isLarge: Bool { family == .systemLarge }
    private var quoteSize: CGFloat { isLarge ? 168 : 96 }
    private var bodySize: CGFloat { isLarge ? 17 : 13 }
    private var bodyLineLimit: Int { isLarge ? 14 : 6 }
    private var padding: CGFloat { isLarge ? 22 : 14 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Classic: the same oversized serif quote mark NudgeSmallView uses,
            // so the two insight widgets read as one family.
            Text("\u{201C}")
                .font(.system(size: quoteSize, weight: .black, design: .serif))
                .foregroundStyle(wViLight.opacity(0.15))
                .offset(x: isLarge ? -8 : -6, y: isLarge ? -28 : -18)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if let text = entry.themeText, entry.isCurrentWeek || entry.isPreviousWeek || !WidgetShared.isSubscribed() {
                    if !entry.isCurrentWeek && !entry.isPreviousWeek {
                        Text("Earlier")
                            .font(.system(size: isLarge ? 11 : 9, weight: .semibold, design: .default))
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.bottom, isLarge ? 6 : 4)
                    }
                    if entry.isPreviousWeek {
                        Text("Last week")
                            .font(.system(size: isLarge ? 11 : 9, weight: .semibold, design: .default))
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.bottom, isLarge ? 6 : 4)
                    }
                    Text(text)
                        .font(.system(size: bodySize, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(bodyLineLimit)
                        .lineSpacing(isLarge ? 5 : 3)
                        .fixedSize(horizontal: false, vertical: false)
                } else {
                    Text("This week's digest\narrives Sunday…")
                        .font(.system(size: bodySize, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.50))
                        .italic()
                }

                Spacer(minLength: isLarge ? 16 : 10)

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: isLarge ? 10 : 8, weight: .semibold))
                    Text("WEEKLY DIGEST")
                        .font(.system(size: isLarge ? 10 : 8, weight: .bold, design: .default))
                        .tracking(1.8)
                }
                .foregroundStyle(wViLight.opacity(0.60))

            }
            .padding(padding)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [wBgTop, wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://insights"))
    }
}

// MARK: - Locked

private struct DigestLockedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Weekly Digest")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            WidgetShared.lockedTierLabel(sentinel: false)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [wBgTop.opacity(0.8), wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://upgrade"))
    }
}

// MARK: - Dispatcher

struct DigestWidgetView: View {
    let entry: DigestWidgetEntry

    var body: some View {
        // Free keeps seeing its latest digest, however old (owner, 2026-10-20), labelled
        // "Earlier" past last week; the lock shows only when none was ever made, since the empty
        // states promise a digest Free won't get.
        if WidgetShared.isSubscribed() || entry.themeText != nil {
            DigestUnlockedView(entry: entry)
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
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - Previews
// `#Preview` + `WidgetPreviewContext` is the only path that renders
// `.containerBackground(for: .widget)` faithfully outside a real widget host
// (an in-app gallery screen can't — the modifier is inert there). Not
// CLI-scriptable; verify these in Xcode's canvas.
//
// `WidgetShared.tier()` reads the app group, which a
// preview process has no data in, so each preview seeds the keys it needs.
// This only touches the dev machine's container.

private func seedWidgetPreview(tier: String) {
    let d = UserDefaults(suiteName: WidgetShared.appGroupID)
    d?.set("classic", forKey: "widget.displayMode")
    d?.set(tier, forKey: "widget.tier")
}

#Preview("Classic", as: .systemSmall) {
    seedWidgetPreview(tier: "core")
    return MirrorWeeklyDigestWidget()
} timeline: {
    DigestWidgetEntry(date: .now, themeText: "A week of holding steady while the ground kept shifting under you.", isCurrentWeek: true)
    DigestWidgetEntry(date: .now, themeText: nil, isCurrentWeek: false)
}

#Preview("Classic Large", as: .systemLarge) {
    seedWidgetPreview(tier: "core")
    return MirrorWeeklyDigestWidget()
} timeline: {
    DigestWidgetEntry(date: .now, themeText: "A week of holding steady while the ground kept shifting under you.", isCurrentWeek: true)
    DigestWidgetEntry(date: .now, themeText: nil, isCurrentWeek: false)
}

#Preview("Locked", as: .systemSmall) {
    seedWidgetPreview(tier: "free")
    return MirrorWeeklyDigestWidget()
} timeline: {
    DigestWidgetEntry(date: .now, themeText: nil, isCurrentWeek: false)
}
