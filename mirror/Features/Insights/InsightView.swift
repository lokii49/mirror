import SwiftUI
import SwiftData
import Charts

struct InsightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var insights: [Insight]
    let viewModel: InsightViewModel
    @State private var showPaywall = false
    @State private var showPaywallAfterFirstNudge = false
    @State private var showSettings = false
    @State private var chartVisible = false
    @State private var promptIndex: Int = Int.random(in: 0..<WritingPrompts.all.count)
    @State private var showWriteFromPrompt = false
    @State private var nudgeExpanded = false
    @State private var digestExpanded = false
    @State private var pastNudgesExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nudgeSection

                    if !pastNudges.isEmpty {
                        pastNudgesSection
                    }

                    if moodEntries.count >= 2, chartVisible {
                        MoodWeekChartView(entries: moodEntries)
                    }

                    digestSection

                    explorationSection
                }
                .padding(16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MirrorTheme.bgBase)
            .navigationTitle("Insights")
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
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showPaywallAfterFirstNudge) { PaywallView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showWriteFromPrompt) {
                NavigationStack {
                    WriteView(autoFocus: true, initialText: WritingPrompts.all[promptIndex])
                }
            }
        }
        .task {
            async let showChart: Void = showChartAfterInitialRender()
            async let load: Void = refreshInsights()
            _ = await (showChart, load)
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

    private var moodEntries: [Entry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.mood != nil && !($0.mood!.isEmpty) && $0.createdAt >= cutoff }
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var seen = Set<Date>()
        var writtenDays: [Date] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if seen.insert(day).inserted { writtenDays.append(day) }
        }

        guard let mostRecentDay = writtenDays.first, mostRecentDay >= yesterday else { return 0 }

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
        return streak
    }

    private var thisMonthEntries: [Entry] {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return entries.filter { $0.createdAt >= start }
    }

    private var hasSeenMoreThanOneNudge: Bool {
        insights.filter { $0.type == .dailyNudge }.count > 1
    }

    private var pastNudges: [Insight] {
        guard SubscriptionService.shared.isSubscribed else { return [] }
        let today = DateHelpers.dayIdentifier(for: Date())
        return insights
            .filter { $0.type == .dailyNudge && $0.periodIdentifier != today }
            .sorted { $0.generatedAt > $1.generatedAt }
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
                        .foregroundStyle(MirrorTheme.textSecondary)
                    Text(pastNudgesExpanded
                         ? "Hide past reflections"
                         : "Past reflections (\(pastNudges.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MirrorTheme.textSecondary)
                    Spacer()
                    Image(systemName: pastNudgesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .inkSurface(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            if pastNudgesExpanded {
                VStack(spacing: 10) {
                    ForEach(pastNudges.prefix(14)) { insight in
                        PastNudgeCard(insight: insight)
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
            label: "Available each Sunday morning",
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
                        Text("\(currentStreak)d")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
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
            LoadingInsightCard(label: "Preparing your reflection", sublabel: "Reading recent entries…", icon: "sparkles")
        case .loaded(let insight):
            InsightTextView(
                insight: insight,
                label: "Daily Reflection",
                icon: "sparkles",
                accentColor: MirrorTheme.primary,
                isExpanded: nudgeExpanded,
                collapsedLineLimit: 5,
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        nudgeExpanded.toggle()
                    }
                }
            )
                .glowShadow(color: MirrorTheme.primary, radius: 32)
        case .needsMoreEntries(let remaining):
            VStack(spacing: 12) {
                NeedsMoreEntriesCard(remaining: remaining)
                WritingPromptCard(
                    prompt: WritingPrompts.all[promptIndex],
                    onShuffle: {
                        var next = Int.random(in: 0..<WritingPrompts.all.count)
                        if WritingPrompts.all.count > 1 {
                            while next == promptIndex { next = Int.random(in: 0..<WritingPrompts.all.count) }
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            promptIndex = next
                        }
                    },
                    onUse: { showWriteFromPrompt = true }
                )
            }
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
        case .error(let message):
            ErrorCard(message: message) {
                Task { await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext) }
            }
        }
    }

    // MARK: - Ask Mirror

    private var askSection: some View {
        NavigationLink {
            AskView()
        } label: {
            ExplorationTile(
                title: "Ask Mirror",
                subtitle: entries.isEmpty ? "Start writing to ask questions" : "Search \(entries.count) \(entries.count == 1 ? "entry" : "entries")",
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
                title: "Mood Timeline",
                subtitle: dominantMoodThisWeek.map { "Mostly \($0) this week" } ?? "See long arcs",
                icon: "waveform.path.ecg",
                color: .teal,
                badge: SubscriptionService.shared.isDeep ? nil : "Deep"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly Report

    private var monthlyReportSection: some View {
        let count = thisMonthEntries.count
        let daysLeft = daysRemainingInMonth
        let contextLabel = daysLeft <= 3
            ? "\(count) entries · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
            : "\(count) \(count == 1 ? "entry" : "entries") this month"
        return NavigationLink {
            MonthlyReportView(viewModel: viewModel)
        } label: {
            ExplorationTile(
                title: "Monthly Report",
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
        guard !moodEntries.isEmpty else { return nil }
        let counts = Dictionary(grouping: moodEntries, by: { $0.mood ?? "" }).mapValues { $0.count }
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
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        digestExpanded.toggle()
                    }
                }
            )
                .glowShadow(color: .indigo, radius: 28)
        case .notEnoughEntries(let remaining):
            NeedsMoreEntriesCard(
                remaining: remaining,
                total: 5,
                icon: "calendar.badge.clock",
                iconColor: .indigo,
                unlockLabel: "Weekly digest unlocks after 5 entries."
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
        case .error(let message):
            ErrorCard(message: message) {
                Task { await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext) }
            }
        }
    }

    // MARK: - Explore

    private var explorationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Explore",
                subtitle: "Deep dives into your patterns",
                icon: "square.grid.2x2",
                color: .orange
            )
            monthlyReportSection
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                askSection
                moodTimelineSection
            }
        }
    }
}

// MARK: - Past Nudge Card

private struct PastNudgeCard: View {
    let insight: Insight
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(insight.generatedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary.opacity(0.5))
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
        .inkSurface(cornerRadius: 18)
    }
}

// MARK: - Shared Card Components

private struct SectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var trailing: Trailing

    init(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text(subtitle)
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

private struct ExplorationTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let badge: String?
    var isProminent: Bool = false

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
        .inkSurface(cornerRadius: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.30), lineWidth: 1)
        )
    }

    private func tileIcon(size: CGFloat, iconSize: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color, in: Capsule())
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
    let label: String
    let sublabel: String
    let icon: String
    var iconColor: Color = MirrorTheme.primary

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(sublabel)
                    .font(.system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor.opacity(0.35))
        }
        .padding(20)
        .inkSurface(cornerRadius: 22)
    }
}

private struct LoadingInsightCard: View {
    let label: String
    let sublabel: String
    let icon: String

    var body: some View {
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
        .padding(20)
        .inkSurface(cornerRadius: 22)
    }
}

private struct NeedsMoreEntriesCard: View {
    let remaining: Int
    var total: Int = 3
    var icon: String = "book.pages"
    var iconColor: Color = MirrorTheme.primary
    var unlockLabel: String = "First reflection unlocks after 3 entries."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(remaining) more \(remaining == 1 ? "entry" : "entries") to go")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Mirror learns from your writing patterns.")
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(iconColor.opacity(0.25))
                        .frame(height: 6)
                    Capsule()
                        .fill(iconColor.opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(max(0, total - remaining)) / CGFloat(total), height: 6)
                }
            }
            .frame(height: 6)
            Text(unlockLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MirrorTheme.textTertiary)
        }
        .padding(20)
        .inkSurface(cornerRadius: 24)
    }
}

private struct UpgradePromptCard: View {
    let title: String
    let subtitle: String
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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI model not installed", systemImage: "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MirrorTheme.violetLight)
            Text("MirrorNotes uses Gemma 3 1B, a small AI that runs entirely on your device. The model file needs to be added once.")
                .font(.subheadline)
                .foregroundStyle(MirrorTheme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                Label("Download **gemma-3-1b-it-Q4_K_M.gguf** from Hugging Face (bartowski/gemma-3-1b-it-GGUF)", systemImage: "1.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Label("Copy it to the app via Files or iTunes File Sharing", systemImage: "2.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Label("Reopen MirrorNotes — AI features activate automatically", systemImage: "3.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
        }
        .padding(20)
        .inkSurface(cornerRadius: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MirrorTheme.violet.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct InsightTextView: View {
    let insight: Insight
    let label: String
    let icon: String
    var accentColor: Color = MirrorTheme.primary
    var isExpanded: Bool = true
    var collapsedLineLimit: Int = 5
    var onToggleExpanded: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label(label, systemImage: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MirrorTheme.violetLight)
                    .tracking(0.8)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MirrorTheme.textTertiary)
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
            Text(insight.content)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .lineSpacing(8)
                .foregroundStyle(MirrorTheme.textPrimary)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .textSelection(.enabled)

            if let onToggleExpanded {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Show Less" : "Read Full Reflection")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MirrorTheme.violetLight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(MirrorTheme.violetDim, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .inkHero(cornerRadius: 26)
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
    let entries: [Entry]

    private struct MoodPoint: Identifiable {
        let id: UUID
        let date: Date
        let mood: String
        let score: Double
    }

    private var points: [MoodPoint] {
        entries.compactMap { entry in
            guard let mood = entry.mood, let score = MirrorTheme.moodScore[mood] else { return nil }
            return MoodPoint(id: entry.id, date: entry.createdAt, mood: mood, score: score)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Spacer()
                if let mood = dominantMood {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: mood))
                            .frame(width: 7, height: 7)
                        Text("Mostly \(mood)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MirrorTheme.moodColor(for: mood).opacity(0.1), in: Capsule())
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
                            Text(v == 1 ? "Low" : v == 3 ? "Mid" : "High")
                                .font(.system(size: 10))
                                .foregroundStyle(MirrorTheme.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10))
                }
            }
            .frame(height: 130)
        }
        .padding(18)
        .inkSurface(cornerRadius: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
        )
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
