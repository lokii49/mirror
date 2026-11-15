import WidgetKit
import SwiftUI

private let appGroupID = WidgetShared.appGroupID

// Palette + app-group reads live in WidgetTheme.swift (shared across all widgets).
private let wBgTop    = WidgetTheme.bgTop
private let wBgBottom = WidgetTheme.bgBottom
private let wViLight  = WidgetTheme.violetLight

// MARK: - Timeline

struct PromptWidgetEntry: TimelineEntry {
    let date: Date
    let promptIndex: Int
    var prompt: String { WritingPrompts.all[promptIndex] }
}

struct PromptWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PromptWidgetEntry {
        PromptWidgetEntry(date: .now, promptIndex: 0)
    }
    func getSnapshot(in context: Context, completion: @escaping (PromptWidgetEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PromptWidgetEntry>) -> Void) {
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [makeEntry()], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> PromptWidgetEntry {
        PromptWidgetEntry(date: .now, promptIndex: WritingPrompts.indexForToday())
    }
}

// MARK: - Unlocked view

private struct PromptUnlockedView: View {
    let entry: PromptWidgetEntry

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text("?")
                .font(.system(size: 110, weight: .black))
                .foregroundStyle(wViLight.opacity(0.10))
                .offset(x: 14, y: 18)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 8, weight: .bold))
                    Text("TODAY'S PROMPT")
                        .font(.system(size: 8, weight: .bold, design: .default))
                        .tracking(1.8)
                }
                .foregroundStyle(wViLight.opacity(0.60))

                Spacer(minLength: 8)

                Text(entry.prompt)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: false)

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Text("Tap to write →")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(wViLight.opacity(0.55))
                }
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [wBgTop, wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://write?promptIndex=\(entry.promptIndex)"))
    }
}

// MARK: - Locked view

private struct PromptLockedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Writing Prompt")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            WidgetShared.lockedTierLabel(sentinel: false)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [wBgTop.opacity(0.8), wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://upgrade"))
    }
}

// MARK: - Dispatcher

struct PromptWidgetView: View {
    let entry: PromptWidgetEntry

    private var isUnlocked: Bool {
        let tier = WidgetShared.tier()
        return tier == "core" || tier == "deep"
    }

    var body: some View {
        if isUnlocked {
            PromptUnlockedView(entry: entry)
        } else {
            PromptLockedView()
        }
    }
}

// MARK: - Widget

struct MirrorPromptWidget: Widget {
    let kind = "MirrorPromptWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PromptWidgetProvider()) { entry in
            PromptWidgetView(entry: entry)
        }
        .configurationDisplayName("Writing Prompt")
        .description("A fresh question every day to spark your reflection.")
        .supportedFamilies([.systemSmall])
    }
}
