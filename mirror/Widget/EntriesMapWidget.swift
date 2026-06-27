import WidgetKit
import SwiftUI

private let appGroupID        = "group.com.lokesh.mirror"
private let entriesHeatmapKey = "widget.entries.heatmap"

// Shared dark ink palette
private let wBgTop    = Color(red: 0.110, green: 0.094, blue: 0.188)  // #1C1830
private let wBgBottom = Color(red: 0.067, green: 0.055, blue: 0.110)  // #110E1C
private let wViolet   = Color(red: 0.486, green: 0.361, blue: 0.894)  // #7C5CE4
private let wViLight  = Color(red: 0.655, green: 0.545, blue: 0.980)  // #A78BFA
private let moodHeatmapKey2   = "widget.mood.heatmap"

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
        let tier = UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.tier") ?? "free"
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

    var body: some View {
        if isUnlocked {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Entries")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
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
                            .foregroundStyle(wViLight)
                    }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                    spacing: 2
                ) {
                    ForEach(days, id: \.self) { day in
                        let isToday = key(day) == todayKey
                        RoundedRectangle(cornerRadius: 3)
                            .fill(cellColor(for: day))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                isToday
                                    ? RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(wViLight, lineWidth: 1.5)
                                    : nil
                            )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [wBgTop, wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(URL(string: "mirror://entries"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Core · $2.99/mo")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [wBgTop.opacity(0.8), wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
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
