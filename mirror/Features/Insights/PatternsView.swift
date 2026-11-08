import SwiftUI
import SwiftData

/// Patterns (Deep): which mood comes up most, by day of the week, time of day, tag, collection
/// and entry length (`PatternsService`). Plain sentences with a share meter, no model text.
struct PatternsView: View {
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query(sort: \Entry.createdAt, order: .reverse) private var journalEntries: [Entry]
    @Query private var scopeCollections: [JournalCollection]
    @Query(sort: \MoodCheckIn.createdAt) private var moodCheckIns: [MoodCheckIn]
    @State private var insightEntries = InsightEntriesMemo()
    private var entries: [Entry] { insightEntries.entries(journalEntries, collections: scopeCollections) }

    @State private var subscription = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var allTime = false
    @State private var result: PatternsService.Result?
    @State private var collectionNames: [String: String] = [:]

    private var isSentinel: Bool { displayMode == .sentinel }

    private struct LoadKey: Hashable {
        var journal: JournalCacheKey
        var allTime: Bool
        var collections: Int
    }

    var body: some View {
        Group {
            if subscription.isDeep {
                content
            } else {
                DeepLockCard(icon: "square.grid.3x3.topleft.filled", title: "Patterns", sentinelTitle: "PATTERNS",
                             message: "See which moods come with which days, times, tags and collections. Patterns are part of Deep.") {
                    showPaywall = true
                }
            }
        }
        .background(MirrorTheme.bgBase)
        #if os(macOS)
        .macPage("Patterns")
        #endif
        .navigationTitle(isSentinel ? "PATTERNS" : "Patterns")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $allTime) {
                    Text("Last 90 days").tag(false)
                    Text("All time").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("patterns.range")

                if let result {
                    if result.isEmpty {
                        PatternsEmptyCard(isSentinel: isSentinel)
                    } else {
                        section("By day of the week", rows: result.weekdays, label: weekdayLabel)
                        section("By time of day", rows: result.timesOfDay, label: bandLabel)
                        section("By tag", rows: result.tags) { "#" + MirrorTheme.localizedTagName(for: $0) }
                        section("By collection", rows: result.collections) { collectionNames[$0] ?? String(localized: "Missing collection") }
                        section("By entry length", rows: result.lengths, label: lengthLabel)
                    }
                    Text("Counted from the moods you picked and your check-ins. A pattern shows what came together, not why. A group shows only with at least 3 moods and one mood that came up twice. Collections kept out of reflections aren't counted.")
                        .scaledFont(12)
                        .foregroundStyle(MirrorTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .frame(maxWidth: hSizeClass == .regular ? 700 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(16)
            .padding(.bottom, 24)
        }
        .task(id: LoadKey(journal: JournalCacheKey(entries: entries.count, checkIns: moodCheckIns.count, revision: JournalRevision.shared.value),
                          allTime: allTime, collections: scopeCollections.count)) {
            load()
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, rows: [PatternsService.Row], label: @escaping (String) -> String) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .textCase(isSentinel ? .uppercase : nil)
                    .scaledFont(isSentinel ? 12 : 15, weight: .semibold, design: isSentinel ? .monospaced : .default)
                    .foregroundStyle(MirrorTheme.textPrimary)
                ForEach(rows) { row in
                    PatternRowView(label: label(row.key), row: row, isSentinel: isSentinel)
                }
            }
            .padding(16)
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1))
        }
    }

    private func weekdayLabel(_ key: String) -> String {
        guard let day = Int(key), (1...7).contains(day) else { return key }
        return Calendar.current.standaloneWeekdaySymbols[day - 1]
    }

    private func bandLabel(_ key: String) -> String {
        switch PatternsService.Band(rawValue: key) {
        case .morning: return String(localized: "Mornings")
        case .afternoon: return String(localized: "Afternoons")
        case .evening: return String(localized: "Evenings")
        case .night: return String(localized: "Nights")
        case nil: return key
        }
    }

    private func lengthLabel(_ key: String) -> String {
        switch PatternsService.Length(rawValue: key) {
        case .short: return String(localized: "Under 100 words")
        case .medium: return String(localized: "100 to 300 words")
        case .long: return String(localized: "Over 300 words")
        case nil: return key
        }
    }

    /// Decrypts moods and tags once per journal change or range switch (never in body).
    private func load() {
        let cutoff = allTime ? nil : Calendar.current.date(byAdding: .day, value: -90, to: Date())
        let range = cutoff.map { DateInterval(start: $0, end: .distantFuture) }
        var readings: [PatternsService.Reading] = []
        for entry in entries {
            if let cutoff, entry.createdAt < cutoff { continue }
            guard let mood = entry.mood, !mood.isEmpty else { continue }
            readings.append(.init(date: entry.createdAt, mood: mood, tags: entry.tags,
                                  collectionID: entry.collectionID, words: entry.wordCount))
        }
        let days = MoodLog.dailyMoods(in: range, entries: entries, checkIns: moodCheckIns)
            .map { (date: $0.key, mood: $0.value.mood) }
        let scope = InsightScope(collections: scopeCollections)
        let kept = scopeCollections
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .filter { scope.includes(collectionID: $0.id) }
        // Not uniqueKeysWithValues: a restored copy and its synced original share an id until
        // JournalOrganizationStore.removeDuplicates runs, and that would trap.
        collectionNames = Dictionary(kept.map { ($0.id.uuidString, $0.payload?.name ?? String(localized: "Locked collection")) },
                                     uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        result = PatternsService.compute(entries: readings, days: days, keptCollections: kept.map(\.id).filter { seen.insert($0).inserted })
    }
}

/// One group: its name, the mood that came up most, how often, and a meter of that share.
private struct PatternRowView: View {
    let label: String
    let row: PatternsService.Row
    let isSentinel: Bool

    var body: some View {
        let tint = MirrorTheme.moodColor(for: row.topMood)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .scaledFont(isSentinel ? 12.5 : 15, weight: .medium, design: isSentinel ? .monospaced : .default)
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(isSentinel ? MirrorTheme.localizedMoodName(for: row.topMood).uppercased() : MirrorTheme.localizedMoodName(for: row.topMood))
                    .scaledFont(isSentinel ? 12 : 14, weight: .semibold, design: isSentinel ? .monospaced : .default)
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text("\(row.count) of \(row.total)")
                    .scaledFont(isSentinel ? 11.5 : 13, design: isSentinel ? .monospaced : .default)
                    .monospacedDigit()
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MirrorTheme.inkBorder.opacity(0.6))
                    Capsule().fill(tint).frame(width: max(4, proxy.size.width * row.share))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): mostly \(MirrorTheme.localizedMoodName(for: row.topMood)), \(row.count) of \(row.total)"))
    }
}

private struct PatternsEmptyCard: View {
    let isSentinel: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .scaledFont(28)
                .foregroundStyle(MirrorTheme.textTertiary)
            Text("Not enough moods yet")
                .scaledFont(16, weight: .semibold, design: isSentinel ? .monospaced : .default)
            Text("A pattern shows once a group has 3 moods. Pick a mood when you write, or log one from Insights.")
                .scaledFont(13)
                .foregroundStyle(MirrorTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

/// A Deep page seen on Free or Core: what it does, and the way to unlock it. No fake preview.
struct DeepLockCard: View {
    let icon: String
    let title: LocalizedStringKey
    let sentinelTitle: LocalizedStringKey
    let message: LocalizedStringKey
    let unlock: () -> Void
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(MirrorTheme.violetDim).frame(width: 72, height: 72)
                Image(systemName: icon)
                    .scaledFont(28, weight: .semibold)
                    .foregroundStyle(MirrorTheme.violetLight)
            }
            Text(displayMode == .sentinel ? sentinelTitle : title)
                .scaledFont(displayMode == .sentinel ? 20 : 22, weight: .bold, design: displayMode == .sentinel ? .monospaced : .rounded)
            Text(message)
                .scaledFont(14)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: unlock) {
                Text("Unlock with Deep")
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(MirrorTheme.buttonFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
