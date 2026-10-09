import SwiftUI
import SwiftData
import Charts

struct InsightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var insights: [Insight]
    @AppStorage(ReflectionStyle.storageKey) private var reflectionStyleRaw = ReflectionStyle.gentle.rawValue
    let viewModel: InsightViewModel
    @State private var showPaywall = false
    @State private var showPaywallAfterFirstNudge = false
    @State private var showSettings = false
    @State private var chartVisible = false
    @State private var nudgeExpanded = false
    @State private var digestExpanded = false
    @State private var pastNudgesExpanded = false
    @State private var pastDigestsExpanded = false
    #if os(macOS)
    /// Which of the two pages this view backs on Mac (the iOS Insights tab shows both).
    var macPage: MacInsightPage = .today
    @State private var macInspectorOpen = false
    @State private var macToday: MacTodayContent? = nil
    @State private var macPastRows: [MacPastRow] = []
    #endif

    private var reflectionStyle: ReflectionStyle { ReflectionStyle(storedValue: reflectionStyleRaw) }

    // weekMoodEvents/thisMonthEntries/currentStreak scan the full-history `entries` @Query with
    // no date/range filter already applied; pastNudges filters+sorts the full `insights` @Query.
    // All four are read directly from `body`/its section subviews, so every unrelated @State
    // change in this view (nudgeExpanded, digestExpanded, pastNudgesExpanded, sheet toggles)
    // was re-running them from scratch. Cached via `.task(id:)`, matching the
    // CalendarHeatmap/MoodTimelineView/WriteView/AskView precedent.
    @State private var cachedThisMonthEntries: [Entry] = []
    @State private var cachedCurrentStreak: Int = 0
    @State private var cachedPastNudges: [Insight] = []
    /// The day each real reflection is about (InsightService.reflectedDay), for Past rows' labels.
    @State private var cachedReflectedDays: [PersistentIdentifier: Date] = [:]
    /// Today's reflection as shown in the app, with the second quote (since 3.0.8) (built off the main render
    /// path: it decrypts the reflected day's entries). Keyed by the insight and its content.
    @State private var cachedNudgeDisplay: (key: String, text: String)? = nil
    @State private var cachedPastDigests: [Insight] = []

    // Standalone daily mood check-ins — merged with entry moods via `MoodLog`
    // for the weekly mood chart.
    @Query(sort: \MoodCheckIn.createdAt) private var moodCheckIns: [MoodCheckIn]
    @State private var cachedWeekMoodEvents: [MoodEvent] = []

    // entries.count alone misses in-place edits: changing an existing entry's mood or date
    // (both editable) must also invalidate cachedThisMonthEntries/cachedCurrentStreak/
    // cachedWeekMoodEvents. Check-in moods+dates folded in too (matching
    // MoodTimelineView.moodDataCacheKey) so a CloudKit sync that swaps a
    // check-in without changing the count still triggers a recompute.
    private var entryCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        for entry in entries {
            hasher.combine(entry.encryptedMood)
            hasher.combine(entry.createdAt)
        }
        hasher.combine(moodCheckIns.count)
        for checkIn in moodCheckIns {
            hasher.combine(checkIn.encryptedMood)
            hasher.combine(checkIn.createdAt)
        }
        return hasher.finalize()
    }

    private var sentinelStatusLine: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("SENTINEL — ONLINE")
                .font(MirrorTheme.mono(9.5, weight: .bold))
                .foregroundStyle(Color.green)
                .kerning(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var iosContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if displayMode == .sentinel {
                        sentinelStatusLine
                    }

                    nudgeSection

                    if !pastNudges.isEmpty {
                        pastNudgesSection
                    }

                    if cachedWeekMoodEvents.count >= 2, chartVisible {
                        MoodWeekChartView(events: cachedWeekMoodEvents)
                    }

                    digestSection

                    if !pastDigests.isEmpty {
                        pastDigestsSection
                    }

                    explorationSection
                }
                .padding(16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MirrorTheme.bgBase)
            .navigationTitle(displayMode == .sentinel ? "Briefing" : "Insights")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Same single presentation site as the daily reminder /
                        // auto-prompt (ContentView owns the sheet) — a second
                        // concurrent .sheet here would be silently dropped.
                        MoodCheckInPresenter.shared.pending = true
                    } label: {
                        Image(systemName: displayMode == .sentinel ? "waveform.path.ecg" : "face.smiling")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
                    }
                    .accessibilityLabel(displayMode == .sentinel ? "Log signal" : "Log mood")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if shouldShowRefresh {
                        Button {
                            Task {
                                await refreshInsights()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .accessibilityLabel("Retry insights")
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
            .sheet(isPresented: $showPaywallAfterFirstNudge) { PaywallView().environment(\.appDisplayMode, displayMode) }
            .sheet(isPresented: $showSettings) { SettingsView().environment(\.appDisplayMode, displayMode) }
        }
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        switch macPage {
        case .today: macTodayScreen
        case .digest: macDigestScreen
        }
        #else
        iosContent
        #endif
    }

    var body: some View {
        platformContent
        .onChange(of: showPaywall || showPaywallAfterFirstNudge || showSettings) { _, up in
            // These sheets live on this view, so ContentView (which owns the
            // mood check-in sheet) can't see them. Report up so a queued
            // check-in waits its turn instead of racing into a dropped sheet.
            MoodCheckInPresenter.shared.blockedByOtherSheet = up
        }
        .task {
            async let showChart: Void = showChartAfterInitialRender()
            async let load: Void = refreshInsights()
            _ = await (showChart, load)
        }
        .task(id: entryCacheKey) {
            recomputeEntryCaches()
        }
        .task(id: insightCacheKey) {
            recomputeInsightCaches()
        }
        .task(id: nudgeDisplayKey) {
            recomputeNudgeDisplay()
        }
        .onChange(of: entries.count) { _, _ in
            nudgeExpanded = false
            digestExpanded = false
            Task {
                await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
            }
        }
        .onChange(of: insights.count) { _, _ in
            // Re-check when background pre-gen inserts a new insight
            nudgeExpanded = false
            digestExpanded = false
            Task {
                await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
                await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext)
            }
        }
        .onChange(of: InsightGenerationCoordinator.shared.isInFlight("nudge_\(DateHelpers.dayIdentifier(for: Date()))")) { _, inFlight in
            // A nudge generation that throws inserts no row, so insights.count never changes —
            // without this, a .loading card derived from the in-flight flag would stick forever.
            guard !inFlight else { return }
            Task {
                await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
            }
        }
        .onChange(of: SubscriptionService.shared.tier) { _, _ in
            // Re-evaluate when subscription status settles after cold launch
            Task { await refreshInsights() }
        }
        .onChange(of: viewModel.nudgeState) { _, newState in
            // Show paywall after first nudge if not subscribed
            if case .loaded = newState,
               !hasSeenMoreThanOneNudge,
               !SubscriptionService.shared.isSubscribed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showPaywallAfterFirstNudge = true
                }
            }
        }
    }

    private var currentStreak: Int { cachedCurrentStreak }

    private var thisMonthEntries: [Entry] { cachedThisMonthEntries }

    // Gates the "show paywall after first nudge" trigger below — counting raw rows (including
    // fallback boilerplate and per-retry duplicates, same rows newestRealPerPeriod now hides
    // from the list) meant a user whose only nudge attempts had failed grounding could rack up
    // several fallback rows and read as "already seen multiple," silently skipping the paywall
    // on what would actually be their first REAL nudge. Same "fallback doesn't count as a real
    // one" filter InsightViewModel.hasSeenFirstNudge already uses.
    private var hasSeenMoreThanOneNudge: Bool {
        insights
            .filter { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
            .count > 1
    }

    /// Everything but what the Today card shows: the card's own row (which can be yesterday's
    /// reflection, see InsightViewModel.resolvedNudgeState) and today's newest real row, the
    /// card's default, so it doesn't flash in the list before the card resolves.
    private var pastNudges: [Insight] {
        guard SubscriptionService.shared.isSubscribed else { return [] }
        let today = DateHelpers.dayIdentifier(for: Date())
        var onCard = Set<PersistentIdentifier>()
        if case .loaded(let insight) = viewModel.nudgeState { onCard.insert(insight.persistentModelID) }
        if let newestToday = cachedPastNudges.first(where: { $0.periodIdentifier == today }) {
            onCard.insert(newestToday.persistentModelID)
        }
        return cachedPastNudges.filter { !onCard.contains($0.persistentModelID) }
    }

    /// Past reflections are recomputed when insights change or an entry's date/mood does (the
    /// day a reflection is about depends on entry dates).
    private var insightCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(insights.count)
        hasher.combine(entryCacheKey)
        return hasher.finalize()
    }

    private struct PastNudgeGroup: Hashable {
        let period: String
        let aboutDay: Date?
    }

    /// Real daily reflections, newest first, one per (day it was made, day it's about): a day
    /// can hold a reflection about yesterday's writing and one about its own (2026-09-28), and
    /// both belong in the list. Fallback rows never show, and two devices' reflections about the
    /// same day (made before CloudKit merged them) still collapse to the newest.
    static func pastDailyReflections(from insights: [Insight], entriesNewestFirst: [Entry]) -> (rows: [Insight], reflectedDays: [PersistentIdentifier: Date]) {
        let realNudges = insights.filter { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
        var reflectedDays: [PersistentIdentifier: Date] = [:]
        for nudge in realNudges {
            reflectedDays[nudge.persistentModelID] = InsightService.reflectedDay(of: nudge, entriesNewestFirst: entriesNewestFirst)
        }
        let rows = Dictionary(grouping: realNudges) {
            PastNudgeGroup(period: $0.periodIdentifier, aboutDay: reflectedDays[$0.persistentModelID])
        }
        .compactMap { _, group in group.max { $0.generatedAt < $1.generatedAt } }
        .sorted { $0.generatedAt > $1.generatedAt }
        return (rows, reflectedDays)
    }

    /// Earlier weeks' digests, newest first. When the current digest state is the
    /// `.previousWeek` fallback, its hero already shows the newest one — drop it
    /// here so the archive list doesn't repeat it. Keyed off the hero's own
    /// `periodIdentifier`, not position 0: `loadWeeklyDigest`'s `.previousWeek` pick can be a
    /// fallback row, which `cachedPastDigests` (via `newestPerPeriod`) already excludes — so
    /// `dropFirst()` would remove the wrong (next-newest, real) row instead of a no-op.
    private var pastDigests: [Insight] {
        guard SubscriptionService.shared.isSubscribed else { return [] }
        if case .previousWeek(let hero, _) = viewModel.digestState {
            return cachedPastDigests.filter { $0.periodIdentifier != hero.periodIdentifier }
        }
        return cachedPastDigests
    }

    private func recomputeEntryCaches() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        cachedWeekMoodEvents = MoodLog.events(
            in: DateInterval(start: cutoff, end: .distantFuture),
            entries: entries,
            checkIns: moodCheckIns
        )

        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        cachedThisMonthEntries = entries.filter { $0.createdAt >= start }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            cachedCurrentStreak = 0
            return
        }

        var seen = Set<Date>()
        var writtenDays: [Date] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if seen.insert(day).inserted { writtenDays.append(day) }
        }

        guard let mostRecentDay = writtenDays.first, mostRecentDay >= yesterday else {
            cachedCurrentStreak = 0
            return
        }

        var streak = 0
        var checkDate = mostRecentDay
        for day in writtenDays {
            if day == checkDate {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if day < checkDate {
                break
            }
        }
        cachedCurrentStreak = streak
    }

    // A retried fallback inserts a new row per attempt rather than overwriting the old one
    // (see InsightViewModel.resolvedNudgeState) — today's card hides that with a `max(by:)`
    // lookup, but these past-list caches used to list every row unfiltered, so a day retried
    // 4 times showed 4 identical "couldn't find today's reflection" cards. Newest-per-period
    // wins here too, matching how today's own card already resolves the same duplication. A
    // period whose newest (and only surviving) row is still a fallback never produced a real
    // reflection at all, so it's dropped rather than shown as one boilerplate card — same
    // "fallback doesn't count as a real one" reasoning InsightViewModel.hasSeenFirstNudge uses.
    private func newestRealPerPeriod(_ items: [Insight]) -> [Insight] {
        Dictionary(grouping: items, by: \.periodIdentifier)
            .compactMap { _, rows in rows.max { $0.generatedAt < $1.generatedAt } }
            .filter { !InsightService.isUngroundedFallback($0.content) }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    private var loadedNudge: Insight? {
        if case .loaded(let insight) = viewModel.nudgeState { return insight }
        return nil
    }

    private func nudgeDisplayKey(for insight: Insight?) -> String {
        guard let insight else { return "" }
        return "\(insight.persistentModelID.hashValue)|\(insight.content.hashValue)|\(entries.count)|\(reflectionStyle.rawValue)"
    }

    private var nudgeDisplayKey: String { nudgeDisplayKey(for: loadedNudge) }

    private func recomputeNudgeDisplay() {
        guard let insight = loadedNudge else { cachedNudgeDisplay = nil; return }
        let shown = InsightService.reflectionForDisplay(insight.content, entries: entries, generatedAt: insight.generatedAt, style: reflectionStyle)
        cachedNudgeDisplay = (nudgeDisplayKey(for: insight), shown.text)
    }

    /// The stored text until the display cache has today's version (never decrypts in `body`).
    private func displayedNudgeText(_ insight: Insight) -> String {
        guard let cached = cachedNudgeDisplay, cached.key == nudgeDisplayKey(for: insight) else { return insight.content }
        return cached.text
    }

    private func recomputeInsightCaches() {
        let thisWeek = DateHelpers.digestWeekIdentifier(for: Date())
        let past = Self.pastDailyReflections(from: insights, entriesNewestFirst: entries)
        cachedPastNudges = past.rows
        cachedReflectedDays = past.reflectedDays
        cachedPastDigests = newestRealPerPeriod(
            insights.filter { $0.type == .weeklyDigest && $0.periodIdentifier != thisWeek }
        )
    }

    private var pastNudgesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    pastNudgesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.75) : MirrorTheme.textSecondary)
                    Text(pastNudgesExpanded
                         // "LOG" would collide with the Sentinel tab bar's own "Log" (entries
                         // list) — caught while screenshotting this fix, see B1 in
                         // .claude/2.1.0-design-plan.md.
                         ? (displayMode == .sentinel ? "HIDE PRIOR BRIEFINGS" : "Hide past reflections")
                         : (displayMode == .sentinel ? "PRIOR BRIEFINGS (\(pastNudges.count))" : "Past reflections (\(pastNudges.count))"))
                        .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 13, weight: .semibold))
                        .kerning(displayMode == .sentinel ? 0.5 : 0)
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.textPrimary : MirrorTheme.textSecondary)
                    Spacer()
                    Image(systemName: pastNudgesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Was raw .inkSurface — Classic-only, so Sentinel showed the rounded ink-card
                // look here while every other header on this screen (SectionHeader) switched
                // to the mono/hairline HUD treatment. Track B1 (.claude/2.1.0-design-plan.md):
                // one silent appDisplayMode divergence, now themed like the rest of the screen.
                .themedCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            if pastNudgesExpanded {
                VStack(spacing: 10) {
                    ForEach(pastNudges.prefix(14)) { insight in
                        PastNudgeCard(insight: insight, aboutDay: cachedReflectedDays[insight.persistentModelID])
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var pastDigestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    pastDigestsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.75) : MirrorTheme.textSecondary)
                    Text(pastDigestsExpanded
                         ? (displayMode == .sentinel ? "HIDE PRIOR DIGESTS" : "Hide past digests")
                         : (displayMode == .sentinel ? "PRIOR DIGESTS (\(pastDigests.count))" : "Past digests (\(pastDigests.count))"))
                        .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 13, weight: .semibold))
                        .kerning(displayMode == .sentinel ? 0.5 : 0)
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.textPrimary : MirrorTheme.textSecondary)
                    Spacer()
                    Image(systemName: pastDigestsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .themedCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            if pastDigestsExpanded {
                VStack(spacing: 10) {
                    ForEach(pastDigests.prefix(14)) { insight in
                        PastDigestCard(insight: insight)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var shouldShowRefresh: Bool {
        if case .error = viewModel.nudgeState { return true }
        if case .error = viewModel.digestState { return true }
        return false
    }

    private func refreshInsights() async {
        await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
        await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext)
    }

    /// Labelled only when the Today card is about an earlier day's writing.
    private func todayCardAboutDay(_ insight: Insight) -> Date? {
        // From the Past-list cache when it has the row (no decrypting in `body`); a reflection
        // that just landed may not be cached yet.
        guard let day = cachedReflectedDays[insight.persistentModelID]
                ?? InsightService.reflectedDay(of: insight, entriesNewestFirst: entries),
              day < Calendar.current.startOfDay(for: Date()) else { return nil }
        return day
    }

    private var nightlyPendingNudgeCard: some View {
        let hour = NotificationService.nudgeHour()
        let timeLabel: String = {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = NotificationService.nudgeMinute()
            if let date = Calendar.current.date(from: comps) {
                return date.formatted(.dateTime.hour().minute())
            }
            return "\(hour):00"
        }()
        return NightlyPendingCard(
            label: "Reflection generates at \(timeLabel)",
            sublabel: "Write today and open Mirror at your chosen time for your daily insight.",
            icon: "sparkles",
            iconColor: MirrorTheme.primary
        )
    }

    private var nightlyPendingDigestCard: some View {
        NightlyPendingCard(
            label: "Available Sunday mornings",
            sublabel: "Generates overnight while your phone charges.",
            icon: "calendar.badge.clock",
            iconColor: .indigo
        )
    }

    private func showChartAfterInitialRender() async {
        guard !chartVisible else { return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        chartVisible = true
    }

    // MARK: - Daily Nudge

    private var nudgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Today",
                subtitle: nudgeExpanded ? "Full daily reflection" : "A short read first; expand when you want depth",
                icon: "sparkles",
                color: MirrorTheme.primary
            ) {
                if currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(displayMode == .sentinel ? "\(currentStreak)D" : "\(currentStreak)d")
                            .font(displayMode == .sentinel ? MirrorTheme.mono(11.5, weight: .bold) : .system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Color.orange.opacity(0.12),
                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
                    )
                    .overlay {
                        if displayMode == .sentinel {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        }
                    }
                }
            }
            nudgeStatusContent
        }
    }

    @ViewBuilder
    private var nudgeStatusContent: some View {
        switch viewModel.nudgeState {
        case .idle:
            EmptyView()
        case .loading:
            LoadingInsightCard(label: "Preparing your reflection", sublabel: "Reading recent entries — this can take up to a minute", icon: "sparkles")
        case .loaded(let insight):
            InsightTextView(
                insight: insight,
                displayText: displayedNudgeText(insight),
                label: "Daily Reflection",
                icon: "sparkles",
                aboutDay: todayCardAboutDay(insight),
                accentColor: MirrorTheme.primary,
                isExpanded: nudgeExpanded,
                collapsedLineLimit: 5,
                showSourceButton: displayMode == .sentinel,
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        nudgeExpanded.toggle()
                    }
                }
            )
                .glowShadow(color: MirrorTheme.primary, radius: 32)
        case .needsMoreEntries(let remaining):
            NeedsMoreEntriesCard(remaining: remaining)
        case .subscriptionRequired:
            UpgradePromptCard(
                title: "MirrorNotes Core",
                subtitle: "Daily reflections are part of Core.",
                onUpgrade: { showPaywall = true }
            )
        case .pendingNightlyGeneration:
            nightlyPendingNudgeCard
        case .modelNotInstalled:
            ModelNotInstalledCard()
        case .groundingFallback(let insight):
            if InsightService.isUnsupportedLanguageNotice(insight.content) {
                // Retrying can't help: say which languages work, with no "Try Again".
                GroundingFallbackCard(title: "Reflections aren't available in this language yet", message: insight.content)
            } else {
                GroundingFallbackCard(title: "Couldn't confirm this reflection", message: insight.content) {
                    Task { await viewModel.retryNudge(entries: entries, insights: insights, context: modelContext) }
                }
            }
        case .error(let message):
            ErrorCard(message: message) {
                // loadNudge only re-derives state from existing insights — it never
                // generates. retryNudge is the actual regen entry point (and gives
                // instant .loading feedback so the tap isn't visually dead).
                Task { await viewModel.retryNudge(entries: entries, insights: insights, context: modelContext) }
            }
        }
    }

    // MARK: - Ask Mirror

    private var askSection: some View {
        NavigationLink {
            AskView(viewModel: viewModel)
        } label: {
            ExplorationTile(
                title: displayMode == .sentinel ? "Comms" : "Ask Mirror",
                subtitle: entries.isEmpty
                    ? "Start writing to ask questions"
                    : (entries.count == 1 ? "Search 1 entry" : "Search \(entries.count) entries"),
                icon: "bubble.left.and.text.bubble.right.fill",
                color: MirrorTheme.primary,
                badge: SubscriptionService.shared.isSubscribed ? nil : "Core"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mood Timeline

    private var moodTimelineSection: some View {
        NavigationLink {
            MoodTimelineView()
        } label: {
            ExplorationTile(
                title: displayMode == .sentinel ? "Vitals" : "Mood Timeline",
                subtitle: dominantMoodThisWeek.map { mood -> LocalizedStringKey in "Mostly \(MirrorTheme.localizedMoodName(for: mood)) this week" } ?? "See long arcs",
                icon: "waveform.path.ecg",
                color: .teal,
                badge: SubscriptionService.shared.isDeep ? nil : "Deep"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Brain View

    private var brainSection: some View {
        NavigationLink {
            BrainView(viewModel: viewModel)
        } label: {
            BrainEntryCard(isDeep: SubscriptionService.shared.isDeep)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly Report

    private var monthlyReportSection: some View {
        let count = thisMonthEntries.count
        let daysLeft = daysRemainingInMonth
        let contextLabel: LocalizedStringKey
        if daysLeft <= 3 {
            switch (count == 1, daysLeft == 1) {
            case (true, true):   contextLabel = "1 entry · 1 day left"
            case (true, false):  contextLabel = "1 entry · \(daysLeft) days left"
            case (false, true):  contextLabel = "\(count) entries · 1 day left"
            case (false, false): contextLabel = "\(count) entries · \(daysLeft) days left"
            }
        } else {
            contextLabel = count == 1 ? "1 entry this month" : "\(count) entries this month"
        }
        return NavigationLink {
            MonthlyReportView(viewModel: viewModel)
        } label: {
            ExplorationTile(
                title: displayMode == .sentinel ? "Debrief" : "Monthly Report",
                subtitle: contextLabel,
                icon: "doc.text.magnifyingglass",
                color: .indigo,
                badge: SubscriptionService.shared.isDeep ? nil : "Deep",
                isProminent: true
            )
        }
        .buttonStyle(.plain)
    }

    private var dominantMoodThisWeek: String? {
        guard !cachedWeekMoodEvents.isEmpty else { return nil }
        let counts = Dictionary(grouping: cachedWeekMoodEvents, by: { $0.mood }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private var daysRemainingInMonth: Int {
        let cal = Calendar.current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let day = cal.dateComponents([.day], from: now).day else { return 30 }
        return range.count - day
    }

    // MARK: - Weekly Digest

    private var digestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "This Week",
                subtitle: digestExpanded ? "Full weekly digest" : "Collapsed so deeper reports stay within reach",
                icon: "calendar.badge.clock",
                color: .indigo
            )
            digestStatusContent
        }
    }

    @ViewBuilder
    private var digestStatusContent: some View {
        switch viewModel.digestState {
        case .idle:
            EmptyView()
        case .loading:
            LoadingInsightCard(label: "Preparing weekly digest", sublabel: "Analysing your week…", icon: "calendar.badge.clock")
        case .loaded(let insight):
            WeeklyDigestView(
                insight: insight,
                isExpanded: digestExpanded,
                showSourceButton: displayMode == .sentinel,
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        digestExpanded.toggle()
                    }
                }
            )
                .glowShadow(color: .indigo, radius: 28)
        case .previousWeek(let insight, _):
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    displayMode == .sentinel
                        ? "LAST WEEK'S BRIEFING — 3 SIGNALS THIS WEEK FOR A NEW ONE"
                        : "Last week's digest — write 3 entries this week for a fresh one.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .medium))
                .kerning(displayMode == .sentinel ? 0.4 : 0)
                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.85) : .secondary)
                WeeklyDigestView(
                    insight: insight,
                    isExpanded: digestExpanded,
                    showSourceButton: displayMode == .sentinel,
                    onToggleExpanded: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            digestExpanded.toggle()
                        }
                    }
                )
                    .glowShadow(color: .indigo, radius: 28)
            }
        case .notEnoughEntries(let remaining):
            NeedsMoreEntriesCard(
                remaining: remaining,
                total: 3,
                icon: "calendar.badge.clock",
                iconColor: .indigo,
                unlockLabel: "Weekly digest covers this week — write 3 entries to unlock it."
            )
        case .subscriptionRequired:
            UpgradePromptCard(
                title: "Core required",
                subtitle: "Weekly digests are part of MirrorNotes Core.",
                onUpgrade: { showPaywall = true }
            )
        case .pendingNightlyGeneration:
            nightlyPendingDigestCard
        case .modelNotInstalled:
            ModelNotInstalledCard()
        case .groundingFallback(let insight):
            GroundingFallbackCard(message: insight.content) {
                // Instant feedback — loadWeeklyDigest's own generation call is
                // synchronous from here on out and gives no progress callback, so
                // without this the tap looks dead for however long inference takes.
                viewModel.digestState = .loading
                Task { await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext, forceRegenerate: true) }
            }
        case .error(let message):
            ErrorCard(message: message) {
                viewModel.digestState = .loading
                // forceRegenerate: a manual retry shouldn't be blocked by the
                // Sunday-only pacing gate meant for background auto-generation.
                Task { await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext, forceRegenerate: true) }
            }
        }
    }

    // MARK: - Explore

    private var explorationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Explore",
                subtitle: "Deep dives into your patterns",
                sentinelTitle: "Deep Scan",
                sentinelSubtitle: "Pattern analysis across your log",
                icon: "square.grid.2x2",
                color: .orange
            )
            monthlyReportSection
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                askSection
                moodTimelineSection
            }
            brainSection
        }
    }
}

// MARK: - Past Nudge Card

/// One earlier week's digest in the "Past digests" archive — the real
/// `WeeklyDigestView` renderer with its own collapse state so each row can be
/// opened independently.
private struct PastDigestCard: View {
    let insight: Insight
    @State private var expanded = false
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        WeeklyDigestView(
            insight: insight,
            isExpanded: expanded,
            showSourceButton: displayMode == .sentinel,
            onToggleExpanded: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded.toggle() }
            }
        )
    }
}

private struct PastNudgeCard: View {
    let insight: Insight
    /// The day it's about; labelled only when that isn't the day it was made.
    var aboutDay: Date? = nil
    @State private var isExpanded = false
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(insight.generatedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Spacer()
                if displayMode == .sentinel { InsightSourceButton(insight: insight) }
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary.opacity(0.5))
            }
            if let aboutDay, aboutDay < Calendar.current.startOfDay(for: insight.generatedAt) {
                ReflectedDayLabel(day: aboutDay, isSentinel: displayMode == .sentinel)
                    .padding(.top, -4)
            }
            Text(insight.content)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(MirrorTheme.textPrimary.opacity(0.85))
                .lineLimit(isExpanded ? nil : 3)
                .textSelection(.enabled)
            if insight.content.count > 120 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "Read more")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .themedCard(cornerRadius: 18)
    }
}

// MARK: - Shared Card Components

private struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    /// Sentinel-mode overrides. Sentinel doesn't just re-case the Classic title
    /// (SectionHeader already uppercases it) — some sections are renamed outright
    /// in this mode, the way the tiles under them are (Ask→Comms, etc.). nil =
    /// use the Classic string.
    let sentinelTitle: LocalizedStringKey?
    let sentinelSubtitle: LocalizedStringKey?
    let icon: String
    let color: Color
    var trailing: Trailing

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    private var displayTitle: LocalizedStringKey { isSentinel ? (sentinelTitle ?? title) : title }
    private var displaySubtitle: LocalizedStringKey { isSentinel ? (sentinelSubtitle ?? subtitle) : subtitle }

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        sentinelTitle: LocalizedStringKey? = nil,
        sentinelSubtitle: LocalizedStringKey? = nil,
        icon: String,
        color: Color,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sentinelTitle = sentinelTitle
        self.sentinelSubtitle = sentinelSubtitle
        self.icon = icon
        self.color = color
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSentinel ? MirrorTheme.ember : color)
                .frame(width: 30, height: 30)
                .background(
                    (isSentinel ? MirrorTheme.ember : color).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                if isSentinel {
                    Text(displayTitle)
                        .font(MirrorTheme.mono(13, weight: .bold))
                        .foregroundStyle(MirrorTheme.textPrimary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                } else {
                    Text(displayTitle)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(MirrorTheme.textPrimary)
                }
                Text(displaySubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            trailing
        }
        .padding(.top, 2)
    }
}

/// Deliberately not another `ExplorationTile` — dark canvas matching Brain
/// View's own aesthetic, with a tiny static constellation illustration
/// instead of an SF Symbol chip, so this entry point previews the feature
/// rather than blending into the flat light tiles around it.
///
/// `bg` and `hubColor` are intentionally off-`MirrorTheme`: `bg` is a
/// near-neutral #17171A (the ink tokens all carry a violet cast that would
/// tint the constellation art), and `hubColor` is a slightly bluer violet
/// than `violetLight` to match `BrainView`'s own node palette. These do not
/// theme-switch — the card is dark in both Classic and Sentinel by design;
/// only the border and the "Deep" badge follow `isSentinel`.
private struct BrainEntryCard: View {
    let isDeep: Bool
    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    private static let bg = Color(red: 0.09, green: 0.09, blue: 0.10)
    private static let hubColor = Color(red: 0.62, green: 0.5, blue: 1.0)
    private static let dots: [(x: CGFloat, y: CGFloat, r: CGFloat, color: Color)] = [
        (0.68, 0.24, 5, Color(red: 0.62, green: 0.5, blue: 1.0)),
        (0.84, 0.36, 4, .teal),
        (0.76, 0.6, 6, .orange),
        (0.94, 0.5, 3, .red),
        (0.88, 0.78, 4, .yellow),
        (0.6, 0.72, 3, .teal),
    ]

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isSentinel ? "Constellation" : "Brain View")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if !isDeep {
                        Text(isSentinel ? "DEEP" : "Deep")
                            .font(isSentinel ? MirrorTheme.mono(8.5, weight: .bold) : .system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                isSentinel ? MirrorTheme.ember : Self.hubColor,
                                in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous)) : AnyShape(Capsule())
                            )
                    }
                }
                Text("A living map of your people & themes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 60)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background {
            ZStack {
                Self.bg
                Canvas { context, size in
                    let hub = CGPoint(x: size.width * 0.78, y: size.height * 0.5)
                    for dot in Self.dots {
                        let p = CGPoint(x: size.width * dot.x, y: size.height * dot.y)
                        var path = Path()
                        path.move(to: hub)
                        path.addLine(to: p)
                        context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 0.8)
                    }
                    for dot in Self.dots {
                        let p = CGPoint(x: size.width * dot.x, y: size.height * dot.y)
                        let rect = CGRect(x: p.x - dot.r, y: p.y - dot.r, width: dot.r * 2, height: dot.r * 2)
                        context.fill(Circle().path(in: rect), with: .color(dot.color))
                    }
                    let hubRect = CGRect(x: hub.x - 7, y: hub.y - 7, width: 14, height: 14)
                    context.fill(Circle().path(in: hubRect), with: .color(Self.hubColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isSentinel ? 10 : 22, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: isSentinel ? 10 : 22, style: .continuous)
                .stroke(isSentinel ? MirrorTheme.ember.opacity(0.3) : Self.hubColor.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct ExplorationTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let color: Color
    let badge: LocalizedStringKey?
    var isProminent: Bool = false

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        Group {
            if isProminent {
                HStack(spacing: 14) {
                    tileIcon(size: 44, iconSize: 20)
                    textBlock(titleSize: 17, subtitleSize: 13)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        tileIcon(size: 38, iconSize: 18)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MirrorTheme.textTertiary)
                    }

                    textBlock(titleSize: 15, subtitleSize: 12)
                }
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            }
        }
        .padding(16)
        .themedCard(cornerRadius: 22)
        .overlay {
            if !isSentinel {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(color.opacity(0.30), lineWidth: 1)
            }
        }
    }

    private func tileIcon(size: CGFloat, iconSize: CGFloat) -> some View {
        let tint = isSentinel ? MirrorTheme.ember : color
        return Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.18),
                in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 12, style: .continuous)
            )
    }

    private func textBlock(titleSize: CGFloat, subtitleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let badge {
                    Text(badge)
                        .font(isSentinel ? MirrorTheme.mono(8.5, weight: .bold) : .system(size: 9, weight: .bold))
                        .textCase(isSentinel ? .uppercase : nil)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSentinel ? MirrorTheme.ember : color, in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous)) : AnyShape(Capsule()))
                }
            }
            Text(subtitle)
                .font(.system(size: subtitleSize, weight: .medium))
                .foregroundStyle(MirrorTheme.textSecondary)
                .lineLimit(2)
        }
    }
}

// Used by MonthlyReportView — must stay internal (not private).
struct NightlyPendingCard: View {
    let label: LocalizedStringKey
    let sublabel: LocalizedStringKey
    let icon: String
    var iconColor: Color = MirrorTheme.primary
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MirrorTheme.ember.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.ember)
                } else {
                    Circle()
                        .fill(iconColor.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if displayMode == .sentinel {
                        Text(label).font(MirrorTheme.mono(12, weight: .semibold)).textCase(.uppercase)
                    } else {
                        Text(label).font(.system(size: 15, weight: .medium))
                    }
                }
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                Group {
                    if displayMode == .sentinel {
                        Text(sublabel).font(MirrorTheme.mono(11, weight: .medium))
                    } else {
                        Text(sublabel).font(.system(size: 13))
                    }
                }
                .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle((displayMode == .sentinel ? MirrorTheme.ember : iconColor).opacity(0.35))
        }
        .padding(20)
        .themedCard(cornerRadius: 22)
    }
}

private struct LoadingInsightCard: View {
    let label: LocalizedStringKey
    let sublabel: LocalizedStringKey
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.primary.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                    Text(sublabel)
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
                Spacer()
            }
            // On-device generation (cold model load + inference, plus up to 3 internal retries
            // if grounding fails again) can run well past what the icon animation alone reads
            // as "working" — a real report: tapping Try Again with only that small icon moving
            // looked dead enough that the user kept re-tapping. `ProgressView().progressViewStyle(
            // .linear)` with no `value` was tried first and looked identical to this — on iOS,
            // unlike macOS, that style doesn't animate an indeterminate track at all, it just
            // renders a static empty bar. A custom sliding highlight, driven by explicit
            // `@State`, is guaranteed to actually move.
            IndeterminateProgressBar()
        }
        .padding(20)
        .inkSurface(cornerRadius: 22)
    }
}

private struct IndeterminateProgressBar: View {
    @State private var slideRight = false

    var body: some View {
        GeometryReader { geo in
            let highlightWidth = geo.size.width * 0.32
            Capsule()
                .fill(MirrorTheme.primary.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(MirrorTheme.primary)
                        .frame(width: highlightWidth)
                        .offset(x: slideRight ? geo.size.width - highlightWidth : 0)
                }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                slideRight = true
            }
        }
    }
}

// Used by BrainView — must stay internal (not private).
struct NeedsMoreEntriesCard: View {
    let remaining: Int
    var total: Int = 3
    var icon: String = "book.pages"
    var iconColor: Color = MirrorTheme.primary
    var unlockLabel: LocalizedStringKey = "First reflection unlocks after 3 entries."

    @Environment(\.appDisplayMode) private var displayMode

    private var done: Int { max(0, total - remaining) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((displayMode == .sentinel ? MirrorTheme.ember : iconColor).opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if displayMode == .sentinel {
                        Text("CALIBRATING · \(done)/\(total) SIGNALS")
                            .font(MirrorTheme.mono(13, weight: .bold))
                            .foregroundStyle(MirrorTheme.ember)
                            .kerning(0.4)
                    } else {
                        Text(remaining == 1 ? "1 more entry to go" : "\(remaining) more entries to go")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(displayMode == .sentinel ? "Reading signal patterns." : "Mirror learns from your writing patterns.")
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill((displayMode == .sentinel ? MirrorTheme.ember : iconColor).opacity(0.25))
                        .frame(height: 6)
                    Capsule()
                        .fill((displayMode == .sentinel ? MirrorTheme.ember : iconColor).opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(total), height: 6)
                }
            }
            .frame(height: 6)
            Text(unlockLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MirrorTheme.textTertiary)
        }
        .padding(20)
        .themedHeroCard(cornerRadius: 24)
    }
}

private struct UpgradePromptCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.primary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            Button(action: onUpgrade) {
                Text("View Plans")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Capsule())
            }
            .background(MirrorTheme.accentGradient, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(20)
        .inkSurface(cornerRadius: 24)
    }
}

// Deliberately distinct from ErrorCard below: this isn't a failure (generation succeeded, the
// model just didn't produce anything grounded in the entries after 3 attempts), so no orange
// warning triangle and no claim that it'll retry on its own — it won't, without either a manual
// retry here or a newer entry (see InsightService.weeklyDigestUngroundedFallback's comment).
// "Try Again" re-runs the same bounded grounding loop fresh — a real chance of a different
// result since generation is stochastic, not just a way to write more first.
private struct GroundingFallbackCard: View {
    // LocalizedStringKey, not String — a plain String param silently drops this out of
    // SwiftUI's auto-localization (Label(_:systemImage:) only picks the LocalizedStringKey
    // overload for a compile-time literal), which is exactly what happened here: the catalog
    // extraction tool removed "Couldn't confirm this digest" outright once this was typed as
    // String, and no key ever appeared for the new "Couldn't confirm this reflection" title.
    var title: LocalizedStringKey = "Couldn't confirm this digest"
    let message: String
    /// nil: nothing a retry could change (a language with no reflections), so no button.
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MirrorTheme.violetLight)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MirrorTheme.textSecondary)
            if let onRetry {
                Button("Try Again", action: onRetry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
            }
        }
        .padding(20)
        .inkSurface(cornerRadius: 22)
    }
}

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't load", systemImage: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MirrorTheme.textSecondary)
            Button("Try Again", action: onRetry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MirrorTheme.primary)
        }
        .padding(20)
        .inkSurface(cornerRadius: 22)
    }
}

// Used by MonthlyReportView — must stay internal (not private).
struct ModelNotInstalledCard: View {
    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(isSentinel ? "AI MODEL NEEDED" : "AI model needed", systemImage: isSentinel ? "waveform.path.ecg" : "brain.head.profile")
                .font(isSentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 15, weight: .semibold))
                .kerning(isSentinel ? 0.4 : 0)
                .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
            Text("MirrorNotes uses Gemma 3 1B, a small AI that runs entirely on your device — nothing you write is ever sent anywhere. It's a one-time ~800MB download so the app itself stays small.")
                .font(.subheadline)
                .foregroundStyle(MirrorTheme.textSecondary)
            ModelDownloadStateControl()
        }
        .padding(20)
        .inkSurface(cornerRadius: isSentinel ? 8 : 22)
        .overlay(
            RoundedRectangle(cornerRadius: isSentinel ? 8 : 22, style: .continuous)
                .stroke(isSentinel ? MirrorTheme.ember.opacity(0.3) : MirrorTheme.violet.opacity(0.18), lineWidth: 1)
        )
    }
}

/// Shared download-flow UI for every screen that gates on the on-device model
/// (ModelNotInstalledCard here, AskView's model-not-installed state) — keeps the
/// button wiring and copy for each ModelDownloadState case in one place.
struct ModelDownloadStateControl: View {
    @State private var manager = ModelDownloadManager.shared
    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        switch manager.state {
        case .notStarted:
            VStack(spacing: 10) {
                if manager.modelWasUpgraded {
                    Text("Mirror's on-device AI got an upgrade — download it again to keep using Ask, Nudge, and Digest.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                pillButton(isSentinel ? "DOWNLOAD MODEL" : "Download Model") { manager.startDownload() }
            }

        case .downloading(let progress, let written, let expected):
            VStack(spacing: 10) {
                ProgressView(value: progress)
                    .tint(isSentinel ? MirrorTheme.ember : MirrorTheme.primary)
                    .frame(maxWidth: 220)
                Text("\(Self.byteFormatter.string(fromByteCount: written)) of \(Self.byteFormatter.string(fromByteCount: expected))")
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .medium) : .system(size: 12, weight: .medium))
                    .foregroundStyle(isSentinel ? MirrorTheme.textSecondary : Color.secondary)
                Text(isSentinel ? "DOWNLOADING IN BACKGROUND — DO NOT FORCE-QUIT" : "Downloading in the background — lock your phone or switch apps freely, just don't force-quit.")
                    .font(isSentinel ? MirrorTheme.mono(9.5, weight: .semibold) : .system(size: 11))
                    .kerning(isSentinel ? 0.3 : 0)
                    .foregroundStyle(MirrorTheme.textTertiary)
                    .multilineTextAlignment(.center)
                Button(isSentinel ? "PAUSE" : "Pause") { manager.pauseDownload() }
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 13, weight: .semibold))
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : Color.accentColor)
            }

        case .paused(let resumable, let written, let expected):
            VStack(spacing: 10) {
                if resumable && written > 0 {
                    ProgressView(value: expected > 0 ? Double(written) / Double(expected) : 0)
                        .tint(isSentinel ? MirrorTheme.ember : MirrorTheme.primary)
                        .frame(maxWidth: 220)
                    Text("\(Self.byteFormatter.string(fromByteCount: written)) of \(Self.byteFormatter.string(fromByteCount: expected))")
                        .font(isSentinel ? MirrorTheme.mono(12, weight: .medium) : .system(size: 12, weight: .medium))
                        .foregroundStyle(isSentinel ? MirrorTheme.textSecondary : Color.secondary)
                }
                Text(resumable ? (isSentinel ? "PAUSED" : "Paused") : (isSentinel ? "PAUSED (WILL RESTART FROM 0%)" : "Paused (will restart from 0%)"))
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 14))
                    .foregroundStyle(isSentinel ? MirrorTheme.textSecondary : Color.secondary)
                pillButton(isSentinel ? "RESUME" : "Resume") { manager.resumeDownload() }
            }

        case .verifying:
            HStack(spacing: 8) {
                ProgressView().tint(isSentinel ? MirrorTheme.ember : nil)
                Text(isSentinel ? "VERIFYING…" : "Verifying…")
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 14))
                    .foregroundStyle(isSentinel ? MirrorTheme.textSecondary : Color.secondary)
            }

        case .installed:
            Label(isSentinel ? "MODEL ONLINE — REOPEN TO GENERATE" : "Model installed — reopen this screen to generate", systemImage: "checkmark.circle.fill")
                .font(isSentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 14, weight: .medium))
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .medium) : .system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                pillButton(isSentinel ? "TRY AGAIN" : "Try Again") { manager.resumeDownload() }
            }
        }
    }

    private func pillButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(isSentinel ? MirrorTheme.mono(14, weight: .bold) : .system(size: 16, weight: .semibold))
                .kerning(isSentinel ? 0.4 : 0)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient), in: Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: (isSentinel ? MirrorTheme.ember : MirrorTheme.primary).opacity(0.28), radius: 16, x: 0, y: 6)
    }
}

private struct InsightTextView: View {
    let insight: Insight
    /// What to show instead of `insight.content` (today's reflection with its second quote).
    var displayText: String? = nil
    let label: LocalizedStringKey
    let icon: String
    /// The day the reflection is about, shown under the header when set.
    var aboutDay: Date? = nil
    var accentColor: Color = MirrorTheme.primary
    var isExpanded: Bool = true
    var collapsedLineLimit: Int = 5
    var showSourceButton: Bool = false
    var onToggleExpanded: (() -> Void)? = nil

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Label(label, systemImage: icon)
                    .font(isSentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 11, weight: .bold))
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                    .tracking(0.8)
                Spacer()
                if showSourceButton { InsightSourceButton(insight: insight) }
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MirrorTheme.textTertiary)
            }
            if let aboutDay {
                ReflectedDayLabel(day: aboutDay, isSentinel: isSentinel)
                    .padding(.top, -8)
            }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [MirrorTheme.violet.opacity(0.40), MirrorTheme.violet.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            Text(displayText ?? insight.content)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .lineSpacing(8)
                .foregroundStyle(MirrorTheme.textPrimary)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .selectableUnlessSentinel(isSentinel)

            if let onToggleExpanded {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 6) {
                        Text(isSentinel
                             ? (isExpanded ? "SHOW LESS" : "FULL BRIEFING")
                             : (isExpanded ? "Show Less" : "Read Full Reflection"))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 13, weight: .semibold))
                    .kerning(isSentinel ? 0.4 : 0)
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        isSentinel ? AnyShapeStyle(MirrorTheme.ember.opacity(0.12)) : AnyShapeStyle(MirrorTheme.violetDim),
                        in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) : AnyShape(Capsule())
                    )
                    .overlay {
                        if isSentinel {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MirrorTheme.ember.opacity(0.35), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .themedHeroCard(cornerRadius: 26, classicBase: .hero)
        .overlay {
            RadialGradient(
                colors: [accentColor.opacity(0.16), .clear],
                center: .init(x: 0.90, y: 0.10),
                startRadius: 0,
                endRadius: 200
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Text("\u{201C}")
                .font(.system(size: 80, weight: .bold, design: .serif))
                .foregroundStyle(MirrorTheme.violetLight.opacity(0.13))
                .offset(x: -18, y: 8)
                .allowsHitTesting(false)
        }
    }
}


// MARK: - Mood Week Chart

private struct MoodWeekChartView: View {
    /// Merged entry moods + daily check-ins for the last 7 days (`MoodLog`).
    let events: [MoodEvent]
    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    private struct MoodPoint: Identifiable {
        let id: UUID
        let date: Date
        let mood: String
        let score: Double
    }

    private var points: [MoodPoint] {
        events.compactMap { event in
            guard let score = event.score else { return nil }
            return MoodPoint(id: event.id, date: event.date, mood: event.mood, score: score)
        }
    }

    private var dominantMood: String? {
        let counts = Dictionary(grouping: points, by: { $0.mood }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private var avgScore: Double {
        guard !points.isEmpty else { return 0 }
        return points.map { $0.score }.reduce(0, +) / Double(points.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("This Week's Mood", systemImage: "chart.line.uptrend.xyaxis")
                    .font(isSentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .semibold))
                    .kerning(isSentinel ? 0.3 : 0)
                    .textCase(isSentinel ? .uppercase : nil)
                    .foregroundStyle(MirrorTheme.textSecondary)
                Spacer()
                if let mood = dominantMood {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: mood))
                            .frame(width: 7, height: 7)
                        Text(isSentinel
                             ? "MOSTLY \(MirrorTheme.localizedMoodName(for: mood).uppercased())"
                             : "Mostly \(MirrorTheme.localizedMoodName(for: mood))")
                            .font(isSentinel ? MirrorTheme.mono(10, weight: .semibold) : .system(size: 11, weight: .medium))
                            .kerning(isSentinel ? 0.2 : 0)
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        MirrorTheme.moodColor(for: mood).opacity(0.1),
                        in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                    )
                    .overlay {
                        if isSentinel {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(MirrorTheme.moodColor(for: mood).opacity(0.3), lineWidth: 1)
                        }
                    }
                }
            }

            Chart(points) { point in
                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Mood", point.score)
                )
                .foregroundStyle(MirrorTheme.moodColor(for: point.mood))
                .symbolSize(120)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Mood", point.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [MirrorTheme.violet, MirrorTheme.violetLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...6)
            .chartYAxis {
                AxisMarks(values: [1, 3, 5]) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v == 1 ? LocalizedStringKey("Low") : v == 3 ? LocalizedStringKey("Mid") : LocalizedStringKey("High"))
                                .font(isSentinel ? MirrorTheme.mono(9.5) : .system(size: 10))
                                .foregroundStyle(MirrorTheme.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(isSentinel ? MirrorTheme.mono(9.5) : .system(size: 10))
                }
            }
            .frame(height: 130)
        }
        .padding(18)
        .themedCard(cornerRadius: 22)
    }
}

// Make NudgeState Equatable for onChange
extension NudgeState: Equatable {
    static func == (lhs: NudgeState, rhs: NudgeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading),
             (.subscriptionRequired, .subscriptionRequired),
             (.needsMoreEntries, .needsMoreEntries),
             (.pendingNightlyGeneration, .pendingNightlyGeneration),
             (.modelNotInstalled, .modelNotInstalled): return true
        case (.loaded(let a), .loaded(let b)): return a.id == b.id
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// "From what you wrote on 27 Sep": a daily reflection can be about an earlier day's writing
/// (made the next morning, or before that day's writing was reflected), so the card says which.
private struct ReflectedDayLabel: View {
    let day: Date
    let isSentinel: Bool

    var body: some View {
        Text("From what you wrote on \(day.formatted(.dateTime.day().month(.abbreviated)))")
            .font(isSentinel ? MirrorTheme.mono(10, weight: .medium) : .system(size: 12, weight: .medium))
            .textCase(isSentinel ? .uppercase : nil)
            .tracking(isSentinel ? 0.6 : 0)
            .foregroundStyle(MirrorTheme.textTertiary)
    }
}

#if os(macOS)
// MARK: - Mac Today (the design's Insights board)

enum MacInsightPage { case today, digest }

/// What the Mac Today card is rebuilt for: another reflection or another style.
private struct MacTodayKey: Equatable {
    var id: PersistentIdentifier?
    var style: ReflectionStyle
}

/// The loaded daily reflection, decrypted and parsed once (not in `body`).
private struct MacTodayContent: Equatable {
    var id: PersistentIdentifier
    var content: String
    var parts: InsightService.GroundedNudgeParts?
    var followUp: String?
    var generatedAt: Date
    /// True when the reflection came from the grammar-constrained Gemma path (its sentence is
    /// a verbatim quote and the app's own fixed text follows it).
    var isGrounded: Bool
}

private struct MacPastRow: Identifiable {
    var id: PersistentIdentifier
    var madeOn: Date
    var aboutDay: Date?
    var text: String
}

extension InsightView {
    private var macLoadedNudge: Insight? {
        if case .loaded(let insight) = viewModel.nudgeState { return insight }
        return nil
    }

    fileprivate var macTodayScreen: some View {
        GeometryReader { geo in
            // Beside the column when the window is wide enough, over it when it is not.
            let inspectorBesideColumn = geo.size.width >= 960
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        macTodayToolbar
                        ScrollView {
                            macTodayColumn
                                .frame(maxWidth: 640, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 44)
                                .padding(.bottom, 40)
                                .frame(maxWidth: .infinity)
                        }
                        .modifier(MacNoScrollEdgeEffect())
                    }
                    if macInspectorOpen, inspectorBesideColumn, let today = macToday {
                        MacInsightInspector(today: today, entries: entries, onClose: nil)
                            .frame(width: 300)
                    }
                }
                if macInspectorOpen, !inspectorBesideColumn, let today = macToday {
                    MacInsightInspector(today: today, entries: entries) {
                        withAnimation(.easeInOut(duration: 0.18)) { macInspectorOpen = false }
                    }
                        .frame(width: 300)
                        .shadow(color: .black.opacity(0.18), radius: 14, x: -4, y: 0)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(MirrorTheme.bgBase)
        .task(id: MacTodayKey(id: macLoadedNudge?.persistentModelID, style: reflectionStyle)) { recomputeMacToday() }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacDebugToggleInspector)) { note in
            macInspectorOpen = note.userInfo?["open"] as? Bool ?? !macInspectorOpen
        }
        #endif
        .task(id: insightCacheKey) { recomputeMacPast() }
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
        .sheet(isPresented: $showPaywallAfterFirstNudge) { PaywallView().environment(\.appDisplayMode, displayMode) }
    }

    private var macTodayToolbar: some View {
        MacPageBar(title: "Today") {
            MacBarToggle(icon: "panel-right", isOn: macInspectorOpen, label: "How this was generated", isDisabled: macToday == nil) {
                withAnimation(.easeInOut(duration: 0.18)) { macInspectorOpen.toggle() }
            }
        }
    }

    // MARK: Weekly digest page

    /// Weekly digest: this week's digest in every state the iOS tab has (loading, not enough
    /// entries, upgrade, pending, fallback…) in the Today column, then earlier weeks.
    fileprivate var macDigestScreen: some View {
        VStack(spacing: 0) {
            MacPageBar(title: "Weekly digest") {}
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    digestStatusContent
                    if !pastDigests.isEmpty { pastDigestsSection }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .modifier(MacNoScrollEdgeEffect())
        }
        .background(MirrorTheme.bgBase)
        .onAppear {
            // On its own page the digest opens in full and the archive is listed.
            digestExpanded = true
            pastDigestsExpanded = true
        }
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
    }

    @ViewBuilder
    private var macTodayColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let today = macToday, case .loaded(let insight) = viewModel.nudgeState {
                if let day = todayCardAboutDay(insight) {
                    Text("From what you wrote on \(Self.macDayName(day))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(MacTokens.secondaryInk)
                        .padding(.bottom, 14)
                }
                macTodayCard(today)
            } else {
                // Loading, needs more entries, upgrade, pending, no model, fallback and error
                // states use the existing cards.
                nudgeStatusContent
            }

            if !macPastRows.isEmpty, SubscriptionService.shared.isSubscribed {
                Text("PAST REFLECTIONS")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(MacTokens.secondaryInk)
                    .padding(.top, 36)
                    .padding(.bottom, 10)
                VStack(spacing: 0) {
                    ForEach(Array(macPastRows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(macPastLabel(row))
                                .font(.system(size: 12))
                                .foregroundStyle(MacTokens.secondaryInk)
                            Text(Self.macCurlyQuotes(row.text))
                                .font(.system(size: 15, design: .serif))
                                .lineSpacing(3)
                                .foregroundStyle(MacTokens.ink)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < macPastRows.count - 1 {
                            Rectangle().fill(MacTokens.divider).frame(height: 1)
                        }
                    }
                }
                .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MacTokens.divider, lineWidth: 1) }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// Display only: the stored text keeps its straight quotes, the board shows curly ones.
    fileprivate static func macCurlyQuotes(_ text: String) -> String {
        guard let parts = InsightService.groundedNudgeParts(of: text),
              let range = text.range(of: "\"" + parts.quote + "\"") else { return text }
        var curled = text.replacingCharacters(in: range, with: "\u{201C}" + parts.quote + "\u{201D}")
        if let also = parts.alsoQuote, let alsoRange = curled.range(of: "\"" + also + "\"", options: .backwards) {
            curled.replaceSubrange(alsoRange, with: "\u{201C}" + also + "\u{201D}")
        }
        return curled
    }

    /// "Wed 30 Sep", without the locale's comma.
    fileprivate static func macShortDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)) + " " + date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// The weekday for the last six days, the date beyond that.
    fileprivate static func macDayName(_ day: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: day), to: Calendar.current.startOfDay(for: Date())).day ?? 99
        return (0...6).contains(days) ? day.formatted(.dateTime.weekday(.wide)) : day.formatted(.dateTime.day().month(.abbreviated))
    }

    private func macPastLabel(_ row: MacPastRow) -> String {
        let made = Self.macShortDate(row.madeOn)
        if let about = row.aboutDay, !Calendar.current.isDate(about, inSameDayAs: row.madeOn) {
            return String(localized: "Made \(made) · about \(Self.macShortDate(about))")
        }
        return String(localized: "Made \(made)")
    }

    private func macTodayCard(_ today: MacTodayContent) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            macReflectionText(today)
                .font(.system(size: 21, design: .serif))
                .lineSpacing(8)
                .foregroundStyle(MacTokens.ink)
                .textSelection(.enabled)

            if let question = today.followUp {
                Button {
                    NotificationCenter.default.post(name: .mirrorMacNewEntrySeeded, object: nil, userInfo: ["text": question + "\n"])
                } label: {
                    Text(question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacTokens.accentInk)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(MirrorTheme.inkRaised, in: Capsule())
                        .overlay { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts a new entry with this question")
            }

            VStack(spacing: 0) {
                Rectangle().fill(MacTokens.divider).frame(height: 1)
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { macInspectorOpen = true }
                    } label: {
                        Text("How this was generated")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacTokens.accentInk)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    Text("Made at \(today.generatedAt.formatted(.dateTime.hour().minute()))")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTokens.secondaryInk)
                    Spacer(minLength: 0)
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MacTokens.divider, lineWidth: 1) }
    }

    /// The reflection with the user's own sentence highlighted. A reflection that isn't a
    /// grounded quote (Foundation Models output, older text) is shown as plain text.
    private func macReflectionText(_ today: MacTodayContent) -> Text {
        guard today.isGrounded, let parts = today.parts, let range = today.content.range(of: parts.quote) else {
            return Text(today.content)
        }
        let before = String(today.content[..<range.lowerBound])
        let after = String(today.content[range.upperBound...])
        guard before.hasSuffix(parts.open), after.hasPrefix(parts.close) else { return Text(today.content) }
        let straight = parts.open == "\"" && parts.close == "\""
        var text = AttributedString(String(before.dropLast(parts.open.count)))
        var highlighted = AttributedString((straight ? "\u{201C}" : parts.open) + parts.quote + (straight ? "\u{201D}" : parts.close))
        highlighted.backgroundColor = MacTokens.quoteHighlightUIColor
        text += highlighted
        text += AttributedString(String(after.dropFirst(parts.close.count)))
        return Text(text)
    }

    // MARK: Caches

    private func recomputeMacToday() {
        guard let insight = macLoadedNudge else { macToday = nil; return }
        // Shown with the second quote and the chosen style (display-time only; see reflectionWithAlsoQuote).
        let shown = InsightService.reflectionForDisplay(insight.content, entries: entries, generatedAt: insight.generatedAt, style: reflectionStyle)
        let content = shown.text
        let parts = shown.parts
        let grounded = InsightService.isGrammarGrounded(insight.content)
        // The chip asks about another part of the entry the reflection quoted, not the quote again.
        var followUp: String?
        if grounded, let parts {
            let window = entries.filter { $0.createdAt <= insight.generatedAt && $0.createdAt >= insight.generatedAt.addingTimeInterval(-14 * 86_400) }
            if let source = InsightService.entryQuoting(parts.quote, in: window) {
                followUp = InsightService.followUpQuestion(for: parts, sourceText: source.text)
            }
            // Curious already shows that question in the card; a chip would repeat it.
            if reflectionStyle == .curious, let question = followUp, content.contains(question) { followUp = nil }
        }
        macToday = MacTodayContent(
            id: insight.persistentModelID,
            content: content,
            parts: parts,
            followUp: followUp,
            generatedAt: insight.generatedAt,
            isGrounded: grounded && parts != nil
        )
    }

    private func recomputeMacPast() {
        // Not read from `pastNudges`: that cache is filled by a sibling task that may not have run yet.
        let past = Self.pastDailyReflections(from: insights, entriesNewestFirst: entries)
        let todayID = DateHelpers.dayIdentifier(for: Date())
        var onCard = Set<PersistentIdentifier>()
        if let loaded = macLoadedNudge { onCard.insert(loaded.persistentModelID) }
        if let newestToday = past.rows.first(where: { $0.periodIdentifier == todayID }) { onCard.insert(newestToday.persistentModelID) }
        macPastRows = past.rows.filter { !onCard.contains($0.persistentModelID) }.prefix(14).map { insight in
            MacPastRow(
                id: insight.persistentModelID,
                madeOn: insight.generatedAt,
                aboutDay: past.reflectedDays[insight.persistentModelID],
                text: insight.content
            )
        }
    }
}

extension MacTokens {
    static var quoteHighlightUIColor: Color { quoteHighlight }
}

/// The right-hand panel: how today's reflection was made, in the board's three blocks. It names
/// no engine (the app never shows which model ran) and says what the app, not the model, wrote.
private struct MacInsightInspector: View {
    let today: MacTodayContent
    let entries: [Entry]
    /// Set when the panel floats over the column and so covers the toolbar's toggle.
    let onClose: (() -> Void)?
    @State private var basedOn: BasedOn?

    struct BasedOn {
        var label: String
        var entryCount: Int
        var wordCount: Int
        var entryID: UUID?
    }

    private var authorship: InsightService.GroundedRestAuthorship? {
        guard today.isGrounded, let parts = today.parts else { return nil }
        return InsightService.groundedRestAuthorship(parts)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How this was generated")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTokens.ink)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        MacIcon(name: "panel-right", size: 17)
                            .frame(width: 34, height: 28)
                            .background(MacTokens.toggleActiveFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTokens.accentInk)
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 18)
            .frame(height: MacTokens.chromeHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(MacTokens.divider).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if today.isGrounded, let parts = today.parts {
                        block(title: "YOUR SENTENCE") {
                            Text("\u{201C}\(parts.quote)\u{201D}")
                                .font(.system(size: 15, design: .serif))
                                .lineSpacing(3)
                                .foregroundStyle(MacTokens.ink)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(MacTokens.quoteHighlight, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            caption("Copied word for word from your entry. The app never rewrites it.")
                        }
                        if let also = parts.alsoQuote {
                            block(title: "ALSO FROM YOUR ENTRY") {
                                card("\u{201C}\(also)\u{201D}")
                                caption("Another sentence from the same entry, word for word. The app picked it; the model didn't.")
                            }
                        }
                        if let authorship {
                            if let model = authorship.modelText {
                                block(title: "WHAT THE MODEL WROTE") {
                                    card(model)
                                    caption("One feeling sentence from the on-device model, written after reading your sentence.")
                                }
                            }
                            if let app = authorship.appText {
                                block(title: "ADDED BY THE APP") {
                                    card(app)
                                    caption(authorship.modelText == nil
                                            ? "Fixed text MirrorNotes picks by mood. The model only chose your sentence."
                                            : "A fixed line MirrorNotes adds on difficult days. The model didn't write it.")
                                }
                            }
                        }
                    } else {
                        block(title: "WRITTEN BY") {
                            card(String(localized: "The on-device model"))
                            caption("Written from your recent entries. Nothing was sent anywhere.")
                        }
                    }

                    if let basedOn {
                        block(title: "BASED ON") {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(basedOn.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(MacTokens.ink)
                                    Text(basedOn.entryCount == 1
                                         ? String(localized: "1 entry · \(basedOn.wordCount) words")
                                         : String(localized: "\(basedOn.entryCount) entries · \(basedOn.wordCount) words"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(MacTokens.secondaryInk)
                                }
                                Spacer(minLength: 8)
                                if let id = basedOn.entryID {
                                    Button {
                                        NotificationCenter.default.post(name: .mirrorMacOpenEntry, object: nil, userInfo: ["id": id])
                                    } label: {
                                        Text("Open")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(MacTokens.accentInk)
                                            .padding(.horizontal, 12)
                                            .frame(height: 26)
                                            .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MacTokens.divider, lineWidth: 1) }
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        MacIcon(name: "lock", size: 14).padding(.top, 2)
                        Text("This ran on your Mac. Your entry text did not leave it.")
                            .font(.system(size: 12))
                            .lineSpacing(2)
                    }
                    .foregroundStyle(MacTokens.secondaryInk)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
        }
        .frame(maxHeight: .infinity)
        .background(MirrorTheme.inkRaised)
        .overlay(alignment: .leading) { Rectangle().fill(MacTokens.divider).frame(width: 1) }
        .task(id: today.id) { basedOn = resolveBasedOn() }
    }

    private func block<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(MacTokens.secondaryInk)
            content()
        }
    }

    private func card(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(MacTokens.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MacTokens.divider, lineWidth: 1) }
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundStyle(MacTokens.controlInk)
    }

    /// The entries the reflection was made from: the same recent set `dailyNudgeContext` hands the
    /// generator (the newest few within 14 days of when it was made). Only that window is read,
    /// never the whole library.
    private func resolveBasedOn() -> BasedOn? {
        let asOf = today.generatedAt
        let floor = asOf.addingTimeInterval(-14 * 86_400)
        let readable = entries
            .filter { $0.createdAt <= asOf && $0.createdAt >= floor }
            .sorted { $0.createdAt > $1.createdAt }
            .lazy.filter(InsightService.hasReadableContext)
        let recent = InsightService.dailyNudgeContext(from: Array(readable.prefix(3)), asOf: asOf).recent
        guard let newest = recent.first else { return nil }
        let quoted = today.parts.flatMap { parts in InsightService.entryQuoting(parts.quote, in: recent) }
        let oldest = recent.last ?? newest
        let from = Calendar.current.startOfDay(for: oldest.createdAt)
        let to = Calendar.current.startOfDay(for: (quoted ?? newest).createdAt)
        let label = Calendar.current.isDate(from, inSameDayAs: newest.createdAt)
            ? InsightView.macShortDate(to)
            : InsightView.macShortDate(from) + " – " + InsightView.macShortDate(newest.createdAt)
        return BasedOn(
            label: label,
            entryCount: recent.count,
            wordCount: recent.reduce(0) { $0 + $1.wordCount },
            entryID: (quoted ?? newest).id
        )
    }
}
#endif
