import AppIntents
import SwiftUI
import WidgetKit

// Still Open (3.1.9): unticked checklist items from every entry, with buttons that open a Scratch
// Note ready as a checklist, a numbered list or with Remind me up. The list is Core (widgets are
// Core); the buttons work on every plan, because they're writing (owner, 2026-11-13).
// Data: `StillOpenWidgetData` (written by the app; ticks queued here and applied by the app).

struct StillOpenEntry: TimelineEntry {
    let date: Date
    let items: [StillOpenWidgetData.Item]
    let total: Int
    /// Ids ticked on the widget that the app hasn't applied yet.
    let ticked: Set<String>
    let unlocked: Bool
}

struct StillOpenProvider: TimelineProvider {
    func placeholder(in context: Context) -> StillOpenEntry {
        let day = Date()
        let items = ["Buy oat milk", "Call the dentist", "Return the library books"].enumerated().map {
            StillOpenWidgetData.Item(entryID: UUID(), index: $0.offset, text: $0.element, hash: "", day: day)
        }
        return StillOpenEntry(date: .now, items: items, total: items.count, ticked: [], unlocked: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StillOpenEntry) -> Void) {
        completion(context.isPreview && StillOpenWidgetData.snapshot() == nil ? placeholder(in: context) : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StillOpenEntry>) -> Void) {
        // The app reloads this widget whenever its items change; nothing here goes stale by time.
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> StillOpenEntry {
        let snapshot = StillOpenWidgetData.snapshot()
        return StillOpenEntry(date: .now, items: snapshot?.items ?? [], total: snapshot?.total ?? 0,
                              ticked: Set(StillOpenWidgetData.ticks().map(\.id)),
                              unlocked: WidgetShared.isSubscribed())
    }
}

// MARK: - Tick

/// The circle beside an item: ticks it (or unticks one ticked here before the app applied it).
/// Runs in the widget extension and only writes the queue; the app does the rest.
struct ToggleStillOpenItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick Still Open Item"
    static let isDiscoverable = false

    @Parameter(title: "Entry") var entryID: String
    @Parameter(title: "Line") var index: Int
    @Parameter(title: "Words") var hash: String

    init() {}

    init(item: StillOpenWidgetData.Item) {
        entryID = item.entryID.uuidString
        index = item.index
        hash = item.hash
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: entryID) {
            StillOpenWidgetData.toggle(.init(entryID: id, index: index, hash: hash))
        }
        return .result()
    }
}

// MARK: - Links

private enum StillOpenLink {
    static let list = URL(string: "mirror://still-open")!
    static let checklist = URL(string: "mirror://scratch-note?start=checklist")!
    static let numbered = URL(string: "mirror://scratch-note?start=numbered")!
    static let reminder = URL(string: "mirror://scratch-note?start=reminder")!
    static let upgrade = URL(string: "mirror://upgrade")!
}

// MARK: - Pieces

private struct StillOpenRow: View {
    let item: StillOpenWidgetData.Item
    let ticked: Bool
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleStillOpenItemIntent(item: item)) {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: size + 3, weight: .regular))
                    .foregroundStyle(ticked ? WidgetTheme.violetLight : .white.opacity(0.55))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ticked ? Text("Untick") : Text("Tick"))
            .accessibilityValue(Text(item.text))
            Text(item.text)
                .font(.system(size: size))
                .foregroundStyle(ticked ? .white.opacity(0.45) : .white)
                .strikethrough(ticked)
                .lineLimit(1)
                .privacySensitive()
        }
    }
}

private struct StillOpenTitle: View {
    let count: Int?
    var size: CGFloat = 15

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Still Open")
                .font(.system(size: size, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            if let count {
                Text("\(count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Checklist / Numbered / Reminder: open a Scratch Note set up that way. Every plan.
private struct StillOpenAddButtons: View {
    var height: CGFloat = 30

    var body: some View {
        HStack(spacing: 6) {
            button("Checklist", systemImage: "checklist", url: StillOpenLink.checklist)
            button("Numbered", systemImage: "list.number", url: StillOpenLink.numbered)
            button("Reminder", systemImage: "bell", url: StillOpenLink.reminder)
        }
    }

    private func button(_ title: LocalizedStringKey, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(WidgetTheme.violetLight)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(WidgetTheme.violet.opacity(0.18), in: Capsule())
        }
    }
}

private struct StillOpenEmpty: View {
    var body: some View {
        Text("Nothing left open")
            .font(.system(size: 13, design: .serif))
            .italic()
            .foregroundStyle(.white.opacity(0.55))
    }
}

private struct StillOpenLocked: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Your open checklist items show here.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                WidgetShared.lockedTierLabel(sentinel: false)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(WidgetTheme.violetLight)
        }
    }
}

private extension View {
    func stillOpenBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(colors: [WidgetTheme.bgTop, WidgetTheme.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Families

private struct StillOpenSmallView: View {
    let entry: StillOpenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Still Open")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Spacer(minLength: 2)
                if entry.unlocked, entry.total > 0 {
                    Text("\(entry.total)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WidgetTheme.violetLight)
                }
            }
            if !entry.unlocked {
                StillOpenLocked()
            } else if entry.items.isEmpty {
                StillOpenEmpty()
            } else {
                ForEach(entry.items.prefix(3)) { item in
                    StillOpenRow(item: item, ticked: entry.ticked.contains(item.id), size: 12)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stillOpenBackground()
        // A small widget is one tap target (links inside it don't work): the list, or a new
        // checklist when there's nothing to show or the list is locked.
        .widgetURL(entry.unlocked && !entry.items.isEmpty ? StillOpenLink.list : StillOpenLink.checklist)
    }
}

private struct StillOpenListView: View {
    let entry: StillOpenEntry
    let rows: Int
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 8 : 6) {
            StillOpenTitle(count: entry.unlocked && entry.total > 0 ? entry.total : nil, size: large ? 17 : 15)
            if !entry.unlocked {
                StillOpenLocked()
            } else if entry.items.isEmpty {
                StillOpenEmpty()
            } else {
                ForEach(Array(entry.items.prefix(rows))) { item in
                    StillOpenRow(item: item, ticked: entry.ticked.contains(item.id), size: large ? 14 : 13)
                }
                if entry.total > rows {
                    Text("+\(entry.total - rows) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetTheme.violetLight)
                }
            }
            Spacer(minLength: 0)
            StillOpenAddButtons(height: large ? 32 : 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stillOpenBackground()
        .widgetURL(entry.unlocked ? StillOpenLink.list : StillOpenLink.upgrade)
    }
}

#if os(iOS)
private struct StillOpenRectangularView: View {
    let entry: StillOpenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.unlocked {
                Label("\(entry.total) still open", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                ForEach(entry.items.filter { !entry.ticked.contains($0.id) }.prefix(2)) { item in
                    Text(item.text)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .privacySensitive()
                }
            } else {
                Label("Still Open", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Core")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.unlocked ? StillOpenLink.list : StillOpenLink.upgrade)
    }
}
#endif

struct StillOpenWidgetView: View {
    let entry: StillOpenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: StillOpenListView(entry: entry, rows: 3, large: false)
        case .systemLarge: StillOpenListView(entry: entry, rows: 7, large: true)
        #if os(iOS)
        case .accessoryRectangular: StillOpenRectangularView(entry: entry)
        #endif
        default: StillOpenSmallView(entry: entry)
        }
    }
}

struct MirrorStillOpenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StillOpenWidgetData.widgetKind, provider: StillOpenProvider()) { entry in
            StillOpenWidgetView(entry: entry)
        }
        .configurationDisplayName("Still Open")
        .description("Checklist items you haven't ticked, and quick lists and reminders.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #endif
    }
}
