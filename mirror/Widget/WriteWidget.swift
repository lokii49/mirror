import WidgetKit
import SwiftUI

struct WriteTimelineEntry: TimelineEntry {
    let date: Date
}

struct WriteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WriteTimelineEntry { WriteTimelineEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WriteTimelineEntry) -> Void) { completion(WriteTimelineEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WriteTimelineEntry>) -> Void) {
        completion(Timeline(entries: [WriteTimelineEntry(date: .now)], policy: .never))
    }
}

struct WriteWidgetView: View {
    let entry: WriteTimelineEntry

    private var isUnlocked: Bool {
        let tier = UserDefaults(suiteName: "group.com.lokesh.mirror")?.string(forKey: "widget.tier") ?? "free"
        return tier == "core" || tier == "deep"
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if isUnlocked {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
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

struct MirrorWriteWidget: Widget {
    let kind = "MirrorWriteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WriteWidgetProvider()) { entry in
            WriteWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Write")
        .description("Tap to open MirrorNotes and start writing.")
        .supportedFamilies([.accessoryCircular])
    }
}
