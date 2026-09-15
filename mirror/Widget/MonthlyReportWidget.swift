import WidgetKit
import SwiftUI

// Palette + app-group reads live in WidgetTheme.swift (shared across all widgets).
private let wBgTop      = WidgetTheme.bgTop
private let wBgBottom   = WidgetTheme.bgBottom
private let wViLight    = WidgetTheme.violetLight
private let wEmber      = WidgetTheme.ember
private let wSentinelBg = WidgetTheme.sentinelBg

private func widgetIsSentinel() -> Bool { WidgetShared.isSentinel() }

private let monthLabelFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM"
    return f
}()

// MARK: - Timeline

struct MonthlyReportWidgetEntry: TimelineEntry {
    let date: Date
    /// The "YOUR MONTH IN ONE IMAGE" metaphor sentence, pushed by
    /// `WidgetBridge.syncMonthlyReport`.
    let imageText: String?
    /// True when the stored report is for the current calendar month.
    let isCurrentMonth: Bool
}

struct MonthlyReportWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthlyReportWidgetEntry {
        MonthlyReportWidgetEntry(
            date: .now,
            imageText: "A harbor at first light — still, but with every boat already pointed out to sea.",
            isCurrentMonth: true
        )
    }
    func getSnapshot(in context: Context, completion: @escaping (MonthlyReportWidgetEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthlyReportWidgetEntry>) -> Void) {
        let nextMidnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [makeEntry()], policy: .after(nextMidnight)))
    }
    private func makeEntry() -> MonthlyReportWidgetEntry {
        let defaults = UserDefaults(suiteName: WidgetShared.appGroupID)
        let text = defaults?.string(forKey: WidgetShared.monthlyImageKey)
        let storedPeriod = defaults?.string(forKey: WidgetShared.monthlyPeriodKey) ?? ""
        let thisMonth = DateHelpers.monthIdentifier(for: Date())
        return MonthlyReportWidgetEntry(date: .now, imageText: text, isCurrentMonth: storedPeriod == thisMonth)
    }
}

// MARK: - Unlocked (medium + large)

private struct MonthlyReportUnlockedView: View {
    let entry: MonthlyReportWidgetEntry
    @Environment(\.widgetFamily) private var family
    private let sentinel = widgetIsSentinel()

    private var monthName: String { monthLabelFormatter.string(from: entry.date).uppercased() }
    private var isLarge: Bool { family == .systemLarge }
    private var glyphSize: CGFloat { isLarge ? 168 : 96 }
    private var bodySize: CGFloat { isLarge ? 18 : (sentinel ? 13 : 15) }
    private var bodyLineLimit: Int { isLarge ? 10 : 4 }
    private var padding: CGFloat { isLarge ? 22 : 16 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !sentinel {
                Image(systemName: "sparkles")
                    .font(.system(size: glyphSize, weight: .black))
                    .foregroundStyle(wViLight.opacity(0.10))
                    .offset(x: isLarge ? 8 : 6, y: isLarge ? -22 : -14)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: sentinel ? "chart.bar.doc.horizontal" : "moon.stars.fill")
                        .font(.system(size: isLarge ? 11 : 9, weight: .semibold))
                    Text(sentinel ? "\(monthName) · DEEP REPORT" : "\(monthName) IN ONE IMAGE")
                        .font(.system(size: isLarge ? 11 : 9, weight: .bold, design: sentinel ? .monospaced : .default))
                        .tracking(1.6)
                }
                .foregroundStyle(sentinel ? wEmber.opacity(0.75) : wViLight.opacity(0.60))

                if sentinel {
                    Rectangle()
                        .fill(wEmber.opacity(0.35))
                        .frame(height: 1)
                        .padding(.top, 5)
                }

                Spacer(minLength: isLarge ? 14 : 8)

                if let text = entry.imageText, entry.isCurrentMonth {
                    Text(text)
                        .font(sentinel ? .system(size: bodySize, weight: .medium, design: .monospaced) : .system(size: bodySize, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(bodyLineLimit)
                        .lineSpacing(isLarge ? 5 : 3)
                        .fixedSize(horizontal: false, vertical: false)
                } else {
                    Text(sentinel ? "REPORT COMPILES AT MONTH END." : "Your monthly image forms\nas the month fills in…")
                        .font(sentinel ? .system(size: bodySize, weight: .medium, design: .monospaced) : .system(size: bodySize, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.50))
                        .italic(!sentinel)
                }

                Spacer(minLength: isLarge ? 14 : 8)

                HStack {
                    Spacer()
                    Text(sentinel ? "OPEN TRANSMISSION →" : "Read the full report →")
                        .font(.system(size: isLarge ? 13 : 11, weight: sentinel ? .bold : .semibold, design: sentinel ? .monospaced : .rounded))
                        .foregroundStyle(sentinel ? wEmber.opacity(0.7) : wViLight.opacity(0.55))
                }
            }
            .padding(padding)
        }
        .containerBackground(for: .widget) {
            if sentinel {
                wSentinelBg
            } else {
                LinearGradient(colors: [wBgTop, wBgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .widgetURL(URL(string: "mirror://monthly-report"))
    }
}

// MARK: - Locked

private struct MonthlyReportLockedView: View {
    private let sentinel = widgetIsSentinel()

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: sentinel ? "chart.bar.doc.horizontal" : "moon.stars.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(sentinel ? wEmber.opacity(0.8) : .white.opacity(0.7))
            Text(sentinel ? "MONTHLY TRANSMISSION" : "Monthly Deep Report")
                .font(sentinel ? .system(size: 12, weight: .bold, design: .monospaced) : .system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text(sentinel ? "DEEP · $4.99/MO" : "Deep · $4.99/mo")
                .font(sentinel ? .system(size: 10, weight: .medium, design: .monospaced) : .system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
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

// MARK: - Dispatcher

struct MonthlyReportWidgetView: View {
    let entry: MonthlyReportWidgetEntry

    var body: some View {
        // Deep only — NOT `WidgetShared.isSubscribed()`. This widget is priced at
        // Deep ($4.99/mo); a Core subscriber sees the locked state.
        if WidgetShared.isDeep() {
            MonthlyReportUnlockedView(entry: entry)
        } else {
            MonthlyReportLockedView()
        }
    }
}

// MARK: - Widget

struct MirrorMonthlyReportWidget: Widget {
    let kind = "MirrorMonthlyReportWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonthlyReportWidgetProvider()) { entry in
            MonthlyReportWidgetView(entry: entry)
        }
        .configurationDisplayName("Monthly Deep Report")
        .description("The single image that captures your month.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Previews
// See WeeklyDigestWidget.swift for why previews seed the app group and why
// `#Preview` (not an in-app gallery) is the verification path for widget chrome.

private func seedMonthlyPreview(sentinel: Bool, tier: String) {
    let d = UserDefaults(suiteName: WidgetShared.appGroupID)
    d?.set(sentinel ? "sentinel" : "classic", forKey: "widget.displayMode")
    d?.set(tier, forKey: "widget.tier")
}

#Preview("Classic", as: .systemMedium) {
    seedMonthlyPreview(sentinel: false, tier: "deep")
    return MirrorMonthlyReportWidget()
} timeline: {
    MonthlyReportWidgetEntry(date: .now, imageText: "A harbor at first light — still, but with every boat already pointed out to sea.", isCurrentMonth: true)
    MonthlyReportWidgetEntry(date: .now, imageText: nil, isCurrentMonth: false)
}

#Preview("Sentinel", as: .systemMedium) {
    seedMonthlyPreview(sentinel: true, tier: "deep")
    return MirrorMonthlyReportWidget()
} timeline: {
    MonthlyReportWidgetEntry(date: .now, imageText: "A control room where every light finally reads green, and no one has left their post.", isCurrentMonth: true)
}

#Preview("Classic Large", as: .systemLarge) {
    seedMonthlyPreview(sentinel: false, tier: "deep")
    return MirrorMonthlyReportWidget()
} timeline: {
    MonthlyReportWidgetEntry(date: .now, imageText: "A harbor at first light — still, but with every boat already pointed out to sea.", isCurrentMonth: true)
    MonthlyReportWidgetEntry(date: .now, imageText: nil, isCurrentMonth: false)
}

#Preview("Sentinel Large", as: .systemLarge) {
    seedMonthlyPreview(sentinel: true, tier: "deep")
    return MirrorMonthlyReportWidget()
} timeline: {
    MonthlyReportWidgetEntry(date: .now, imageText: "A control room where every light finally reads green, and no one has left their post.", isCurrentMonth: true)
}

#Preview("Locked (Core)", as: .systemMedium) {
    seedMonthlyPreview(sentinel: false, tier: "core")
    return MirrorMonthlyReportWidget()
} timeline: {
    MonthlyReportWidgetEntry(date: .now, imageText: nil, isCurrentMonth: false)
}
