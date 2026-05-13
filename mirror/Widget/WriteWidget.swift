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

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .semibold))
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "mirror://write"))
    }
}

struct MirrorWriteWidget: Widget {
    let kind = "MirrorWriteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WriteWidgetProvider()) { entry in
            WriteWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Write")
        .description("Tap to open mirror and start writing.")
        .supportedFamilies([.accessoryCircular])
    }
}
