import SwiftUI
import SwiftData

/// Year in Review and Month in Review (Deep): the period's numbers from the journal itself
/// (`ReviewStatsService`). Private: nothing to share, nothing model-written.
struct ReviewView: View {
    enum Span: String, CaseIterable, Hashable { case year, month }

    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query(sort: \Entry.createdAt, order: .reverse) private var journalEntries: [Entry]
    @Query private var scopeCollections: [JournalCollection]
    @Query(sort: \MoodCheckIn.createdAt) private var moodCheckIns: [MoodCheckIn]
    @State private var insightEntries = InsightEntriesMemo()
    /// What reflections may read: moods and tags come from here; writing counts use every entry.
    private var entries: [Entry] { insightEntries.entries(journalEntries, collections: scopeCollections) }

    @State private var subscription = SubscriptionService.shared
    @State private var showPaywall = false
    @State var span: Span
    /// Any date inside the period shown.
    @State var anchor: Date
    @State private var stats: ReviewStatsService.Stats?

    init(span: Span = .year, anchor: Date? = nil) {
        // In the first week of January the year view opens on the year that just ended.
        let start = anchor ?? (span == .year && ReviewStatsService.isReviewWeek()
                               ? Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                               : Date())
        _span = State(initialValue: span)
        _anchor = State(initialValue: start)
    }

    private var isSentinel: Bool { displayMode == .sentinel }
    private var calendar: Calendar { .current }

    private var period: DateInterval {
        calendar.dateInterval(of: span == .year ? .year : .month, for: anchor) ?? DateInterval(start: anchor, duration: 1)
    }

    private var periodTitle: String {
        span == .year ? anchor.formatted(.dateTime.year()) : anchor.formatted(.dateTime.month(.wide).year())
    }

    private var canGoBack: Bool {
        guard let oldest = journalEntries.last?.createdAt else { return false }
        return period.start > oldest
    }

    private var canGoForward: Bool { period.end <= Date() }

    private struct LoadKey: Hashable {
        var journal: JournalCacheKey
        var start: Date
        var span: Span
    }

    var body: some View {
        Group {
            if subscription.isDeep {
                content
            } else {
                DeepLockCard(icon: "calendar.badge.checkmark", title: "Year in Review", sentinelTitle: "ANNUAL DEBRIEF",
                             message: "Your year in numbers: entries, words, streaks, the moods and tags that came up most. Year in Review is part of Deep.") {
                    showPaywall = true
                }
            }
        }
        .background(MirrorTheme.bgBase)
        #if os(macOS)
        .macPage("Year in Review")
        #endif
        .navigationTitle(isSentinel ? "ANNUAL DEBRIEF" : "Year in Review")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Span", selection: $span) {
                    Text("Year").tag(Span.year)
                    Text("Month").tag(Span.month)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("review.span")

                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(!canGoBack)
                        .accessibilityLabel("Previous")
                    Spacer()
                    Text(periodTitle)
                        .scaledFont(isSentinel ? 18 : 22, weight: .bold, design: isSentinel ? .monospaced : .default)
                        .textCase(isSentinel ? .uppercase : nil)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(!canGoForward)
                        .accessibilityLabel("Next")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violet)

                if let stats {
                    if stats.isEmpty {
                        Text(span == .year ? "No entries this year." : "No entries this month.")
                            .scaledFont(15)
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else {
                        tiles(stats)
                        moods(stats)
                        tags(stats)
                        details(stats)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .frame(maxWidth: hSizeClass == .regular ? 700 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(16)
            .padding(.bottom, 24)
        }
        .task(id: LoadKey(journal: JournalCacheKey(entries: journalEntries.count, checkIns: moodCheckIns.count, revision: JournalRevision.shared.value),
                          start: period.start, span: span)) {
            load()
        }
    }

    private func step(_ by: Int) {
        anchor = calendar.date(byAdding: span == .year ? .year : .month, value: by, to: anchor) ?? anchor
    }

    // MARK: Sections

    private func tiles(_ stats: ReviewStatsService.Stats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(value: stats.entries, label: stats.entries == 1 ? "entry" : "entries")
            tile(value: stats.words, label: stats.words == 1 ? "word" : "words")
            tile(value: stats.activeDays, label: stats.activeDays == 1 ? "day written" : "days written")
            tile(value: stats.longestStreak, label: stats.longestStreak == 1 ? "day, longest streak" : "days, longest streak")
        }
    }

    private func tile(value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value, format: .number)
                .scaledFont(isSentinel ? 24 : 28, weight: .bold, design: isSentinel ? .monospaced : .rounded)
                .foregroundStyle(MirrorTheme.textPrimary)
                .monospacedDigit()
            Text(label)
                .scaledFont(13)
                .foregroundStyle(MirrorTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func moods(_ stats: ReviewStatsService.Stats) -> some View {
        if !stats.topMoods.isEmpty {
            card("Moods that came up most") {
                ForEach(stats.topMoods, id: \.mood) { item in
                    HStack(spacing: 8) {
                        Circle().fill(MirrorTheme.moodColor(for: item.mood)).frame(width: 9, height: 9)
                        Text(MirrorTheme.localizedMoodName(for: item.mood))
                            .scaledFont(15, weight: .medium)
                        Spacer()
                        Text(item.days == 1 ? "1 day" : "\(item.days) days")
                            .scaledFont(13)
                            .monospacedDigit()
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func tags(_ stats: ReviewStatsService.Stats) -> some View {
        if !stats.topTags.isEmpty {
            card("Tags you used most") {
                ForEach(stats.topTags, id: \.tag) { item in
                    HStack {
                        Text("#" + MirrorTheme.localizedTagName(for: item.tag))
                            .scaledFont(15, weight: .medium)
                        Spacer()
                        Text(item.entries == 1 ? "1 entry" : "\(item.entries) entries")
                            .scaledFont(13)
                            .monospacedDigit()
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func details(_ stats: ReviewStatsService.Stats) -> some View {
        card("Also") {
            if let weekday = stats.busiestWeekday {
                detail("Wrote most on", calendar.standaloneWeekdaySymbols[weekday - 1])
            }
            if let month = stats.busiestMonth {
                detail("Busiest month", calendar.standaloneMonthSymbols[month - 1])
            }
            if let first = stats.firstEntry {
                detail("First entry", first.formatted(date: .abbreviated, time: .omitted))
            }
            if let last = stats.lastEntry {
                detail("Latest entry", last.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).scaledFont(14).foregroundStyle(MirrorTheme.textSecondary)
            Spacer()
            Text(value).scaledFont(14, weight: .medium)
        }
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .textCase(isSentinel ? .uppercase : nil)
                .scaledFont(isSentinel ? 12 : 15, weight: .semibold, design: isSentinel ? .monospaced : .default)
            content()
        }
        .foregroundStyle(MirrorTheme.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1))
    }

    // MARK: Load

    /// Decrypts moods and tags once per journal change or period switch (never in body).
    private func load() {
        let interval = period
        let inPeriod = journalEntries.filter { interval.contains($0.createdAt) && $0.createdAt < interval.end }
        let readable = entries.filter { interval.contains($0.createdAt) && $0.createdAt < interval.end }
        let dayMoods = MoodLog.dailyMoods(in: interval, entries: readable, checkIns: moodCheckIns)
            .filter { $0.key < interval.end }
            .map(\.value.mood)
        stats = ReviewStatsService.compute(
            writing: inPeriod.map { .init(date: $0.createdAt, words: $0.wordCount) },
            dayMoods: Array(dayMoods),
            tags: readable.map(\.tags),
            isYear: span == .year,
            calendar: calendar
        )
    }
}
