import WidgetKit
import SwiftUI
import Charts
import AppIntents

private let moodHeatmapKey = "widget.mood.heatmap"

// Palette + app-group reads live in WidgetTheme.swift (shared across all widgets).
private let wBgTop    = WidgetTheme.bgTop
private let wBgBottom = WidgetTheme.bgBottom
private let wViolet   = WidgetTheme.violet
private let wViLight  = WidgetTheme.violetLight
private let wEmber    = WidgetTheme.ember
private let wSentinelBg = WidgetTheme.sentinelBg

private func widgetIsSentinel() -> Bool { WidgetShared.isSentinel() }

private let widgetMoodScore: [String: Double] = [
    "Joyful": 5, "Grateful": 5, "Peaceful": 4, "Content": 4, "Energized": 4, "Hopeful": 4,
    "Anxious": 2, "Overwhelmed": 1, "Frustrated": 2, "Drained": 1, "Sad": 1, "Numb": 2
]

private let moodDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Configuration

/// How many days the chart covers, picked in Edit Widget. 14 is the default, so widgets placed
/// before this option existed keep showing two weeks.
enum MoodMapRange: Int, AppEnum {
    case week = 7
    case twoWeeks = 14

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Range"
    static var caseDisplayRepresentations: [MoodMapRange: DisplayRepresentation] = [
        .week: "7 days",
        .twoWeeks: "14 days",
    ]
}

struct MoodMapConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Mood Map"
    static var description = IntentDescription("Choose how many days the chart shows.")

    @Parameter(title: "Range", default: .twoWeeks)
    var range: MoodMapRange
}

// MARK: - Timeline

struct MoodMapEntry: TimelineEntry {
    let date: Date
    let moodByDay: [String: String]
    var days: Int = MoodMapRange.twoWeeks.rawValue
}

struct MoodMapProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MoodMapEntry {
        MoodMapEntry(date: .now, moodByDay: [:])
    }
    func snapshot(for configuration: MoodMapConfigurationIntent, in context: Context) async -> MoodMapEntry {
        makeEntry(days: configuration.range.rawValue)
    }
    func timeline(for configuration: MoodMapConfigurationIntent, in context: Context) async -> Timeline<MoodMapEntry> {
        let entry = makeEntry(days: configuration.range.rawValue)
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }
    private func makeEntry(days: Int) -> MoodMapEntry {
        let data = UserDefaults(suiteName: WidgetShared.appGroupID)?.data(forKey: moodHeatmapKey)
        let moods = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return MoodMapEntry(date: .now, moodByDay: moods, days: days)
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
        let tier = WidgetShared.tier()
        return tier == "core" || tier == "deep"
    }

    private var points: [MoodPoint] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<entry.days).reversed().compactMap { offset -> MoodPoint? in
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
            case .declining: return WidgetTheme.ember
            case .steady, .none: return WidgetTheme.violetLight.opacity(0.60)
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
                WidgetShared.lockedTierLabel(sentinel: sentinel)
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

    /// The app's own mood palette (`WidgetTheme.moodColor`), not system colours.
    private func moodColor(_ mood: String) -> Color {
        WidgetTheme.moodColor(for: mood) ?? Color.accentColor
    }
}

// MARK: - Widget

struct MirrorMoodMapWidget: Widget {
    let kind = "MirrorMoodMapWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MoodMapConfigurationIntent.self, provider: MoodMapProvider()) { entry in
            MoodMapWidgetView(entry: entry)
        }
        .configurationDisplayName("Mood Map")
        .description("Your mood trend over the last 7 or 14 days.")
        .supportedFamilies([.systemSmall])
    }
}
