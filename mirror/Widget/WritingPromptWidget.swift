import WidgetKit
import SwiftUI

private let appGroupID = "group.com.lokesh.mirror"

private let promptTop    = Color(red: 0.70, green: 0.38, blue: 0.08)
private let promptBottom = Color(red: 0.42, green: 0.20, blue: 0.02)

private let writingPrompts: [String] = [
    "What made you smile today?",
    "What's one thing you're grateful for right now?",
    "What did you learn today, big or small?",
    "Who made your day better?",
    "What's weighing on your mind?",
    "What are you looking forward to?",
    "Describe your energy level today.",
    "What was the best moment of your day?",
    "What are you proud of this week?",
    "What would you tell your past self today?",
    "What do you want to let go of?",
    "What feels unfinished?",
    "What made you feel most alive recently?",
    "What do you want more of in your life?",
    "What's one thing you did just for yourself today?",
    "What challenged you, and how did you respond?",
    "What's something you've been avoiding?",
    "Who are you becoming?",
    "What does rest look like for you right now?",
    "What would make tomorrow better than today?",
    "What surprised you today?",
    "What moment do you want to remember?",
    "What do you need right now that you're not getting?",
    "What's a small win worth celebrating?",
    "What story are you telling yourself today?",
    "What do you wish more people understood about you?",
    "What emotion kept coming up today?",
    "Where did you spend your energy, and was it worth it?",
]

// MARK: - Timeline

struct PromptWidgetEntry: TimelineEntry {
    let date: Date
    let prompt: String
}

struct PromptWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PromptWidgetEntry {
        PromptWidgetEntry(date: .now, prompt: writingPrompts[0])
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
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return PromptWidgetEntry(date: .now, prompt: writingPrompts[dayOfYear % writingPrompts.count])
    }
}

// MARK: - Unlocked view

private struct PromptUnlockedView: View {
    let entry: PromptWidgetEntry

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text("?")
                .font(.system(size: 110, weight: .black))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 14, y: 18)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 8, weight: .bold))
                    Text("TODAY'S PROMPT")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(.white.opacity(0.45))

                Spacer(minLength: 8)

                Text(entry.prompt)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: false)

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Text("Tap to write →")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [promptTop, promptBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://write"))
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
            Text("Core · $2.99/mo")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [promptTop.opacity(0.7), promptBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "mirror://upgrade"))
    }
}

// MARK: - Dispatcher

struct PromptWidgetView: View {
    let entry: PromptWidgetEntry

    private var isUnlocked: Bool {
        let tier = UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.tier") ?? "free"
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
