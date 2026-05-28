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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    explorationSection

                    if moodEntries.count >= 2, chartVisible {
                        MoodWeekChartView(entries: moodEntries)
                    }

                    nudgeSection

                    if SubscriptionService.shared.isSubscribed || hasSeenFirstNudge {
                        digestSection
                    }
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

    private var hasSeenFirstNudge: Bool {
        insights.contains { $0.type == .dailyNudge }
    }

    private var moodEntries: [Entry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.mood != nil && !($0.mood!.isEmpty) && $0.createdAt >= cutoff }
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
        NightlyPendingCard(
            label: "Preparing in the background",
            sublabel: "Generates overnight while your phone charges.",
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
            )
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
                subtitle: "Search your patterns",
                icon: "bubble.left.and.text.bubble.right.fill",
                color: MirrorTheme.primary,
                badge: nil
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
                subtitle: "See long arcs",
                icon: "waveform.path.ecg",
                color: .teal,
                badge: SubscriptionService.shared.isDeep ? nil : "Deep"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly Report

    private var monthlyReportSection: some View {
        NavigationLink {
            MonthlyReportView(viewModel: viewModel)
        } label: {
            ExplorationTile(
                title: "Monthly Report",
                subtitle: "\(thisMonthEntries.count) \(thisMonthEntries.count == 1 ? "entry" : "entries") this month",
                icon: "doc.text.magnifyingglass",
                color: .indigo,
                badge: SubscriptionService.shared.isDeep ? nil : "Deep",
                isProminent: true
            )
        }
        .buttonStyle(.plain)
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
        case .error(let message):
            ErrorCard(message: message) {
                Task { await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext) }
            }
        }
    }

    // MARK: - Explore

    private var explorationSection: some View {
        VStack(spacing: 12) {
            if hasSeenFirstNudge || SubscriptionService.shared.isSubscribed {
                VStack(spacing: 12) {
                    monthlyReportSection
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        askSection
                        moodTimelineSection
                    }
                }
            } else {
                askSection
            }
        }
    }
}

// MARK: - Shared Card Components

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
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
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        tileIcon(size: 38, iconSize: 18)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }

                    textBlock(titleSize: 15, subtitleSize: 12)
                }
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            }
        }
        .padding(16)
        .futureSurface(cornerRadius: 22)
    }

    private func tileIcon(size: CGFloat, iconSize: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func textBlock(titleSize: CGFloat, subtitleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
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
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

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
                Text(sublabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.quaternary)
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
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
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
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
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(max(0, total - remaining)), total: Double(total))
                .tint(iconColor)
                .scaleEffect(x: 1, y: 1.4)
            Text(unlockLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .futureSurface(cornerRadius: 24)
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
                        .foregroundStyle(.secondary)
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
        .futureSurface(cornerRadius: 24)
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
                .foregroundStyle(.secondary)
            Button("Try Again", action: onRetry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MirrorTheme.primary)
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Divider().overlay(accentColor.opacity(0.15))
            Text(insight.content)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(.primary)
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
                    .foregroundStyle(accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(accentColor.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .accentCard(cornerRadius: 26)
    }
}


// MARK: - Mood Week Chart

private struct MoodWeekChartView: View {
    let entries: [Entry]

    private static let moodScore: [String: Double] = [
        "Joyful": 5, "Grateful": 5, "Peaceful": 4, "Content": 4, "Energized": 4, "Hopeful": 4,
        "Anxious": 2, "Overwhelmed": 1, "Frustrated": 2, "Drained": 1, "Sad": 1, "Numb": 2
    ]

    private struct MoodPoint: Identifiable {
        let id: UUID
        let date: Date
        let mood: String
        let score: Double
    }

    private var points: [MoodPoint] {
        entries.compactMap { entry in
            guard let mood = entry.mood, let score = Self.moodScore[mood] else { return nil }
            return MoodPoint(id: entry.id, date: entry.createdAt, mood: mood, score: score)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This Week's Mood", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

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
                .foregroundStyle(MirrorTheme.primary.opacity(0.25))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...6)
            .chartYAxis {
                AxisMarks(values: [1, 3, 5]) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v == 1 ? "Low" : v == 3 ? "Mid" : "High")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
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
        .futureSurface(cornerRadius: 22)
    }
}

// Make NudgeState Equatable for onChange
extension NudgeState: Equatable {
    static func == (lhs: NudgeState, rhs: NudgeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading),
             (.subscriptionRequired, .subscriptionRequired),
             (.needsMoreEntries, .needsMoreEntries): return true
        case (.loaded(let a), .loaded(let b)): return a.id == b.id
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
