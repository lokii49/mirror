import WidgetKit
import SwiftUI

private let appGroupID = "group.com.lokesh.mirror"

struct WriteTimelineEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let wroteToday: Bool
}

struct WriteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WriteTimelineEntry {
        WriteTimelineEntry(date: .now, streak: 7, wroteToday: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (WriteTimelineEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WriteTimelineEntry>) -> Void) {
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [makeEntry()], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> WriteTimelineEntry {
        let d = UserDefaults(suiteName: appGroupID)
        return WriteTimelineEntry(
            date: .now,
            streak: d?.integer(forKey: "widget.streak") ?? 0,
            wroteToday: d?.bool(forKey: "widget.wrote.today") ?? false
        )
    }
}

// MARK: - Circular (lock screen)

struct WriteCircularView: View {
    let entry: WriteTimelineEntry

    private var isUnlocked: Bool {
        let tier = UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.tier") ?? "free"
        return tier == "core" || tier == "deep"
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if isUnlocked {
                if entry.wroteToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: isUnlocked ? "mirror://write" : "mirror://upgrade"))
    }
}

// MARK: - Rectangular (lock screen)

struct WriteRectangularView: View {
    let entry: WriteTimelineEntry

    private var isUnlocked: Bool {
        let tier = UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.tier") ?? "free"
        return tier == "core" || tier == "deep"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isUnlocked ? "square.and.pencil" : "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isUnlocked ? .primary : .secondary)

            if isUnlocked {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.wroteToday ? "Written today ✓" : "Write in mirror")
                        .font(.system(size: 13, weight: .semibold))
                    if entry.streak > 0 {
                        Text("🔥 \(entry.streak)-day streak")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Start your streak today")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quick Write")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Core required")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: isUnlocked ? "mirror://write" : "mirror://upgrade"))
    }
}

// MARK: - Unified view dispatcher

struct WriteWidgetView: View {
    let entry: WriteTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            WriteRectangularView(entry: entry)
        default:
            WriteCircularView(entry: entry)
        }
    }
}

// MARK: - Widget

struct MirrorWriteWidget: Widget {
    let kind = "MirrorWriteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WriteWidgetProvider()) { entry in
            WriteWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Write")
        .description("Tap to write in mirror. Shows your current streak.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
