import WidgetKit
import SwiftUI

private let appGroupID        = WidgetShared.appGroupID
private let entriesHeatmapKey = "widget.entries.heatmap"
private let moodHeatmapKey2   = "widget.mood.heatmap"

// Palette + app-group reads live in WidgetTheme.swift (shared across all widgets).
private let wBgTop    = WidgetTheme.bgTop
private let wBgBottom = WidgetTheme.bgBottom
private let wViolet   = WidgetTheme.violet
private let wViLight  = WidgetTheme.violetLight
private let wEmber    = WidgetTheme.ember
private let wSentinelBg = WidgetTheme.sentinelBg

private func widgetIsSentinel() -> Bool { WidgetShared.isSentinel() }

private let entryDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Timeline

struct EntriesMapEntry: TimelineEntry {
    let date: Date
    let countByDay: [String: Int]
    let moodByDay: [String: String]
}

struct EntriesMapProvider: TimelineProvider {
    func placeholder(in context: Context) -> EntriesMapEntry {
        EntriesMapEntry(date: .now, countByDay: [:], moodByDay: [:])
    }
    func getSnapshot(in context: Context, completion: @escaping (EntriesMapEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntriesMapEntry>) -> Void) {
        let entry = makeEntry()
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> EntriesMapEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        let counts = defaults?.data(forKey: entriesHeatmapKey)
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        let moods = defaults?.data(forKey: moodHeatmapKey2)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return EntriesMapEntry(date: .now, countByDay: counts, moodByDay: moods)
    }
}

// MARK: - View

struct EntriesMapWidgetView: View {
    let entry: EntriesMapEntry

    private var isUnlocked: Bool {
        let tier = WidgetShared.tier()
        return tier == "core" || tier == "deep"
    }

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<35).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private var todayKey: String { entryDayFormatter.string(from: Calendar.current.startOfDay(for: .now)) }

    private var streak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let fmt = entryDayFormatter
        var day = today
        if (entry.countByDay[fmt.string(from: day)] ?? 0) == 0 {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  (entry.countByDay[fmt.string(from: yesterday)] ?? 0) > 0 else { return 0 }
            day = yesterday
        }
        var count = 0
        while (entry.countByDay[fmt.string(from: day)] ?? 0) > 0 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private var wroteToday: Bool { (entry.countByDay[todayKey] ?? 0) > 0 }

    private func key(_ day: Date) -> String { entryDayFormatter.string(from: day) }

    private func cellColor(for day: Date) -> Color {
        guard (entry.countByDay[key(day)] ?? 0) > 0 else {
            return Color.white.opacity(0.08)
        }
        guard let mood = entry.moodByDay[key(day)] else {
            return wViolet.opacity(0.70)
        }
        return moodColor(mood)
    }

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "Joyful":      return .yellow
        case "Grateful":    return .green
        case "Peaceful":    return .teal
        case "Content":     return .cyan
        case "Energized":   return .orange
        case "Hopeful":     return .indigo
        case "Anxious":     return .yellow.opacity(0.7)
        case "Overwhelmed": return .red
        case "Frustrated":  return .orange.opacity(0.8)
        case "Drained":     return .gray.opacity(0.5)
        case "Sad":         return .blue
        case "Numb":        return .gray.opacity(0.3)
        default:            return Color.accentColor.opacity(0.6)
        }
    }

    private let sentinel = widgetIsSentinel()

    var body: some View {
        if isUnlocked {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sentinel ? "LOG" : "Entries")
                        .font(sentinel ? .system(size: 10, weight: .bold, design: .monospaced) : .system(size: 11, weight: .bold, design: .rounded))
                        .tracking(sentinel ? 1.2 : 0)
                        .foregroundStyle(sentinel ? wEmber.opacity(0.7) : .white.opacity(0.50))
                    Spacer()
                    if streak > 0 {
                        HStack(spacing: 3) {
                            Text("🔥")
                                .font(.system(size: 10))
                            Text("\(streak)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    } else if wroteToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(sentinel ? wEmber : wViLight)
                    }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                    spacing: 2
                ) {
                    ForEach(days, id: \.self) { day in
                        let isToday = key(day) == todayKey
                        RoundedRectangle(cornerRadius: sentinel ? 1.5 : 3)
                            .fill(cellColor(for: day))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                isToday
                                    ? RoundedRectangle(cornerRadius: sentinel ? 1.5 : 3)
                                        .strokeBorder(sentinel ? wEmber : wViLight, lineWidth: 1.5)
                                    : nil
                            )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .containerBackground(for: .widget) {
                if sentinel {
                    wSentinelBg
                } else {
                    LinearGradient(colors: [wBgTop, wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .widgetURL(URL(string: "mirror://entries"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(sentinel ? wEmber.opacity(0.5) : .white.opacity(0.35))
                Text(sentinel ? "CORE · $2.99/MO" : "Core · $2.99/mo")
                    .font(sentinel ? .system(size: 10, weight: .semibold, design: .monospaced) : .system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
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
}

// MARK: - Widget

struct MirrorEntriesMapWidget: Widget {
    let kind = "MirrorEntriesMapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EntriesMapProvider()) { entry in
            EntriesMapWidgetView(entry: entry)
        }
        .configurationDisplayName("Entry Map")
        .description("Your journaling streak at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
