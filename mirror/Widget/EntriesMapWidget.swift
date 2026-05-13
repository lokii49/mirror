import WidgetKit
import SwiftUI

private let appGroupID        = "group.com.lokesh.mirror"
private let entriesHeatmapKey = "widget.entries.heatmap"
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

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<35).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private func key(_ day: Date) -> String { entryDayFormatter.string(from: day) }

    private func cellColor(for day: Date) -> Color {
        guard (entry.countByDay[key(day)] ?? 0) > 0 else {
            return Color.primary.opacity(0.07)
        }
        guard let mood = entry.moodByDay[key(day)] else {
            return Color.accentColor.opacity(0.5)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Entries")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                spacing: 3
            ) {
                ForEach(days, id: \.self) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(for: day))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "mirror://entries"))
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
