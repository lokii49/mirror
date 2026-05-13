import WidgetKit
import SwiftUI
import Charts

private let moodHeatmapKey = "widget.mood.heatmap"

private let widgetMoodScore: [String: Double] = [
    "Joyful": 5, "Grateful": 5, "Peaceful": 4, "Content": 4, "Energized": 4, "Hopeful": 4,
    "Anxious": 2, "Overwhelmed": 1, "Frustrated": 2, "Drained": 1, "Sad": 1, "Numb": 2
]

private let moodDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Timeline

struct MoodMapEntry: TimelineEntry {
    let date: Date
    let moodByDay: [String: String]
}

struct MoodMapProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodMapEntry {
        MoodMapEntry(date: .now, moodByDay: [:])
    }
    func getSnapshot(in context: Context, completion: @escaping (MoodMapEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodMapEntry>) -> Void) {
        let entry = makeEntry()
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> MoodMapEntry {
        let data = UserDefaults(suiteName: "group.com.lokesh.mirror")?.data(forKey: moodHeatmapKey)
        let moods = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return MoodMapEntry(date: .now, moodByDay: moods)
    }
}

// MARK: - Chart model

private struct MoodPoint: Identifiable {
    let id = UUID()
    let date: Date
    let mood: String
    let score: Double
}

// MARK: - View

struct MoodMapWidgetView: View {
    let entry: MoodMapEntry

    private var points: [MoodPoint] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset -> MoodPoint? in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = moodDayFormatter.string(from: day)
            guard let mood = entry.moodByDay[key], let score = widgetMoodScore[mood] else { return nil }
            return MoodPoint(date: day, mood: mood, score: score)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Moods")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if points.isEmpty {
                Text("Log a mood to see your chart.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Chart(points) { point in
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Mood", point.score)
                    )
                    .foregroundStyle(moodColor(point.mood))
                    .symbolSize(100)

                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Mood", point.score)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.25))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...6)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "mirror://entries"))
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
        default:            return Color.accentColor
        }
    }
}

// MARK: - Widget

struct MirrorMoodMapWidget: Widget {
    let kind = "MirrorMoodMapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodMapProvider()) { entry in
            MoodMapWidgetView(entry: entry)
        }
        .configurationDisplayName("Mood Map")
        .description("Your mood trend over the last 1 weeks.")
        .supportedFamilies([.systemSmall])
    }
}
