import WidgetKit
import SwiftUI

private let appGroupID = "group.com.lokesh.mirror"

private let nudgeDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Colors

private let nudgeTop    = Color(red: 0.42, green: 0.22, blue: 0.72)
private let nudgeBottom = Color(red: 0.20, green: 0.10, blue: 0.44)

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\u{201C}")
                .font(.system(size: 96, weight: .black, design: .serif))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: -6, y: -18)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if let text = entry.nudgeText, entry.isToday {
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(6)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: false)
                } else {
                    Text("Your nudge\narrives soon…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .italic()
                }

                Spacer(minLength: 10)

                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .semibold))
                    Text("DAILY NUDGE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [nudgeTop, nudgeBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://insights"))
    }
}

// MARK: - Medium

private struct NudgeMediumView: View {
    let entry: NudgeWidgetEntry

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\u{201C}")
                .font(.system(size: 120, weight: .black, design: .serif))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: -8, y: -22)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if let text = entry.nudgeText, entry.isToday {
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(5)
                        .lineSpacing(3)
                } else {
                    Text("Your nudge is being prepared…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .italic()
                }

                Spacer(minLength: 12)

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text("DAILY NUDGE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.8)
                    }
                    .foregroundStyle(.white.opacity(0.45))

                    Spacer()

                    Text("Read more →")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(16)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [nudgeTop, nudgeBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://insights"))
    }
}

// MARK: - Locked

private struct NudgeLockedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Daily Nudge")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text("Core · $2.99/mo")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [nudgeTop.opacity(0.7), nudgeBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
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
