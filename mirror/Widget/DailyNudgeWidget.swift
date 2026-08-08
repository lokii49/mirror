import WidgetKit
import SwiftUI

private let appGroupID = "group.com.lokesh.mirror"

private let nudgeDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Colors (shared dark ink palette)

private let wBgTop     = Color(red: 0.110, green: 0.094, blue: 0.188)  // #1C1830
private let wBgBottom  = Color(red: 0.067, green: 0.055, blue: 0.110)  // #110E1C
private let wViolet    = Color(red: 0.486, green: 0.361, blue: 0.894)  // #7C5CE4
private let wViLight   = Color(red: 0.655, green: 0.545, blue: 0.980)  // #A78BFA

// Sentinel accent — matches MirrorTheme.ember's dark-mode hex (0xF97B8B).
// Widgets run in a separate extension target with no access to the app's
// MirrorTheme, so the handful of values used here are copied, same as the
// violet ink palette above.
private let wEmber      = Color(red: 0.976, green: 0.482, blue: 0.545)
private let wSentinelBg = Color(red: 0.043, green: 0.043, blue: 0.055)

private func widgetIsSentinel() -> Bool {
    UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.displayMode") == "sentinel"
}

// MARK: - Timeline

struct NudgeWidgetEntry: TimelineEntry {
    let date: Date
    let nudgeText: String?
    let isToday: Bool
}

struct NudgeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeWidgetEntry {
        NudgeWidgetEntry(date: .now, nudgeText: "You've been carrying a lot quietly. What would it feel like to set one thing down today?", isToday: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (NudgeWidgetEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeWidgetEntry>) -> Void) {
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [makeEntry()], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> NudgeWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        let text = defaults?.string(forKey: "widget.nudge.text")
        let storedDate = defaults?.string(forKey: "widget.nudge.date") ?? ""
        let todayStr = nudgeDayFormatter.string(from: Date())
        return NudgeWidgetEntry(date: .now, nudgeText: text, isToday: storedDate == todayStr)
    }
}

// MARK: - Small

private struct NudgeSmallView: View {
    let entry: NudgeWidgetEntry
    private let sentinel = widgetIsSentinel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !sentinel {
                Text("\u{201C}")
                    .font(.system(size: 96, weight: .black, design: .serif))
                    .foregroundStyle(wViLight.opacity(0.15))
                    .offset(x: -6, y: -18)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if let text = entry.nudgeText, entry.isToday {
                    Text(text)
                        .font(sentinel ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(6)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: false)
                } else {
                    Text(sentinel ? "SIGNAL PENDING…" : "Your nudge\narrives soon…")
                        .font(sentinel ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.50))
                        .italic(!sentinel)
                }

                Spacer(minLength: 10)

                HStack(spacing: 4) {
                    Image(systemName: sentinel ? "target" : "sparkles")
                        .font(.system(size: 8, weight: .semibold))
                    Text(sentinel ? "BRIEFING" : "DAILY NUDGE")
                        .font(.system(size: 8, weight: .bold, design: sentinel ? .monospaced : .default))
                        .tracking(1.8)
                }
                .foregroundStyle(sentinel ? wEmber.opacity(0.75) : wViLight.opacity(0.60))
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

// MARK: - Medium

private struct NudgeMediumView: View {
    let entry: NudgeWidgetEntry
    private let sentinel = widgetIsSentinel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !sentinel {
                Text("\u{201C}")
                    .font(.system(size: 120, weight: .black, design: .serif))
                    .foregroundStyle(wViLight.opacity(0.13))
                    .offset(x: -8, y: -22)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if let text = entry.nudgeText, entry.isToday {
                    Text(text)
                        .font(sentinel ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(5)
                        .lineSpacing(3)
                } else {
                    Text(sentinel ? "SIGNAL PENDING…" : "Your nudge arrives soon…")
                        .font(sentinel ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.50))
                        .italic(!sentinel)
                }

                Spacer(minLength: 12)

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: sentinel ? "target" : "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text(sentinel ? "BRIEFING" : "DAILY NUDGE")
                            .font(.system(size: 9, weight: .bold, design: sentinel ? .monospaced : .default))
                            .tracking(1.8)
                    }
                    .foregroundStyle(sentinel ? wEmber.opacity(0.75) : wViLight.opacity(0.60))

                    Spacer()

                    Text(sentinel ? "OPEN BRIEFING →" : "Tap to reflect →")
                        .font(.system(size: 11, weight: sentinel ? .bold : .semibold, design: sentinel ? .monospaced : .rounded))
                        .foregroundStyle(sentinel ? wEmber.opacity(0.7) : wViLight.opacity(0.55))
                }
            }
            .padding(16)
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

private struct NudgeLockedView: View {
    private let sentinel = widgetIsSentinel()

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: sentinel ? "target" : "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(sentinel ? wEmber.opacity(0.8) : .white.opacity(0.7))
            Text(sentinel ? "BRIEFING" : "Daily Nudge")
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

struct NudgeWidgetView: View {
    let entry: NudgeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var isUnlocked: Bool {
        let tier = UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.tier") ?? "free"
        return tier == "core" || tier == "deep"
    }

    var body: some View {
        if isUnlocked {
            if family == .systemMedium {
                NudgeMediumView(entry: entry)
            } else {
                NudgeSmallView(entry: entry)
            }
        } else {
            NudgeLockedView()
        }
    }
}

// MARK: - Widget

struct MirrorNudgeWidget: Widget {
    let kind = "MirrorNudgeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NudgeWidgetProvider()) { entry in
            NudgeWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Nudge")
        .description("Today's AI reflection from mirror, on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
