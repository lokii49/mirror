import WidgetKit
import SwiftUI
import Charts

private let moodHeatmapKey = "widget.mood.heatmap"

// Shared dark ink palette
private let wBgTop    = Color(red: 0.110, green: 0.094, blue: 0.188)  // #1C1830
private let wBgBottom = Color(red: 0.067, green: 0.055, blue: 0.110)  // #110E1C
private let wViolet   = Color(red: 0.486, green: 0.361, blue: 0.894)  // #7C5CE4
private let wViLight  = Color(red: 0.655, green: 0.545, blue: 0.980)  // #A78BFA

// Sentinel accent — matches MirrorTheme.ember's dark-mode hex (0xF97B8B).
private let wEmber      = Color(red: 0.976, green: 0.482, blue: 0.545)
private let wSentinelBg = Color(red: 0.043, green: 0.043, blue: 0.055)

private func widgetIsSentinel() -> Bool {
    UserDefaults(suiteName: "group.com.lokesh.mirror")?.string(forKey: "widget.displayMode") == "sentinel"
}

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

    private var isUnlocked: Bool {
        let tier = UserDefaults(suiteName: "group.com.lokesh.mirror")?.string(forKey: "widget.tier") ?? "free"
        return tier == "core" || tier == "deep"
    }

    private var points: [MoodPoint] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<14).reversed().compactMap { offset -> MoodPoint? in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = moodDayFormatter.string(from: day)
            guard let mood = entry.moodByDay[key], let score = widgetMoodScore[mood] else { return nil }
            return MoodPoint(date: day, mood: mood, score: score)
        }
    }

    private enum TrendDirection {
        case none, improving, declining, steady

        var label: LocalizedStringKey? {
            switch self {
            case .none:       return nil
            case .improving:  return "↑ Improving"
            case .declining:  return "↓ Declining"
            case .steady:     return "→ Steady"
            }
        }

        var color: Color {
            switch self {
            case .improving: return .green
            case .declining: return Color(red: 0.976, green: 0.482, blue: 0.545) // ember
            case .steady, .none: return Color(red: 0.655, green: 0.545, blue: 0.980).opacity(0.60) // wViLight
            }
        }
    }

    private var trend: TrendDirection {
        guard points.count >= 4 else { return .none }
        let recent = points.suffix(3).map(\.score)
        let earlier = points.dropLast(3).suffix(3).map(\.score)
        guard !earlier.isEmpty else { return .none }
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let earlierAvg = earlier.reduce(0, +) / Double(earlier.count)
        let delta = recentAvg - earlierAvg
        if delta > 0.3 { return .improving }
        if delta < -0.3 { return .declining }
        return .steady
    }

    private let sentinel = widgetIsSentinel()

    var body: some View {
        if isUnlocked {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sentinel ? "VITALS" : "Moods")
                        .font(sentinel ? .system(size: 10, weight: .bold, design: .monospaced) : .system(size: 11, weight: .bold, design: .rounded))
                        .tracking(sentinel ? 1.2 : 0)
                        .foregroundStyle(sentinel ? wEmber.opacity(0.7) : .white.opacity(0.50))
                    Spacer()
                    if let label = trend.label {
                        Text(label)
                            .font(sentinel ? .system(size: 9, weight: .semibold, design: .monospaced) : .system(size: 10, weight: .medium))
                            .foregroundStyle(trend.color)
                    }
                }
                if points.isEmpty {
                    Text(sentinel ? "LOG A SIGNAL TO SEE YOUR CHART." : "Log a mood to see your chart.")
                        .font(sentinel ? .system(size: 10, weight: .medium, design: .monospaced) : .system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.40))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Mood", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: sentinel ? [wEmber.opacity(0.25), wEmber.opacity(0.03)] : [wViolet.opacity(0.25), wViolet.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Mood", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: sentinel ? [wEmber, .orange] : [wViolet, wViLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Mood", point.score)
                        )
                        .foregroundStyle(moodColor(point.mood))
                        .symbolSize(60)
                    }
                    .chartYScale(domain: 0...6)
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
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
            .widgetURL(URL(string: "mirror://mood-timeline"))
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
        .description("Your mood trend over the last 2 weeks.")
        .supportedFamilies([.systemSmall])
    }
}
