import SwiftUI
import SwiftData

struct InsightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var insights: [Insight]
    @State private var viewModel = InsightViewModel()
    @State private var showPaywall = false
    @State private var showPaywallAfterFirstNudge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Daily Nudge section
                    nudgeSection

                    // Weekly Digest section
                    if SubscriptionService.shared.isSubscribed || hasSeenFirstNudge {
                        Divider()
                            .padding(.horizontal, 4)
                        digestSection
                    }
                }
                .padding(16)
                .padding(.bottom, 16)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
                            await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showPaywallAfterFirstNudge) {
                PaywallView()
            }
        }
        .task {
            await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
            await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext)
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

    private var hasSeenMoreThanOneNudge: Bool {
        insights.filter { $0.type == .dailyNudge }.count > 1
    }

    // MARK: - Daily Nudge

    private var nudgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            nudgeHeroCard
            nudgeStatusContent
        }
    }

    private var nudgeHeroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Daily Reflection", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                Text("Patterns from your recent entries.")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 14, x: 0, y: 6)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 26)
    }

    @ViewBuilder
    private var nudgeStatusContent: some View {
        switch viewModel.nudgeState {
        case .idle:
            EmptyView()
        case .loading:
            LoadingInsightCard(label: "Preparing your reflection", sublabel: "Reading recent entries…", icon: "sparkles")
        case .loaded(let insight):
            InsightTextView(insight: insight, label: "Daily Reflection", icon: "sparkles")
                .glowShadow(color: MirrorTheme.primary, radius: 32)
        case .needsMoreEntries(let remaining):
            NeedsMoreEntriesCard(remaining: remaining)
        case .subscriptionRequired:
            UpgradePromptCard(
                title: "Mirror Core",
                subtitle: "Daily reflections are part of Core.",
                onUpgrade: { showPaywall = true }
            )
        case .error(let message):
            ErrorCard(message: message) {
                Task { await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext) }
            }
        }
    }

    // MARK: - Weekly Digest

    private var digestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            digestHeroCard
            digestStatusContent
        }
    }

    private var digestHeroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Weekly Digest", systemImage: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("Your week, shaped into five themes.")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.indigo.opacity(0.35), radius: 14, x: 0, y: 6)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 26)
    }

    @ViewBuilder
    private var digestStatusContent: some View {
        switch viewModel.digestState {
        case .idle:
            EmptyView()
        case .loading:
            LoadingInsightCard(label: "Preparing weekly digest", sublabel: "Analysing your week…", icon: "calendar.badge.clock")
        case .loaded(let insight):
            WeeklyDigestTextView(insight: insight)
                .glowShadow(color: .indigo, radius: 28)
        case .notEnoughEntries:
            VStack(alignment: .leading, spacing: 10) {
                Label("5 entries needed for a weekly digest", systemImage: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .futureSurface(cornerRadius: 20)
        case .subscriptionRequired:
            UpgradePromptCard(
                title: "Core required",
                subtitle: "Weekly digests are part of Mirror Core.",
                onUpgrade: { showPaywall = true }
            )
        case .error(let message):
            ErrorCard(message: message) {
                Task { await viewModel.loadWeeklyDigest(entries: entries, insights: insights, context: modelContext) }
            }
        }
    }
}

// MARK: - Shared Card Components

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.primary.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: "book.pages")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(remaining) more \(remaining == 1 ? "entry" : "entries") to go")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Mirror learns from your writing patterns.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(max(0, 3 - remaining)), total: 3)
                .tint(MirrorTheme.primary)
                .scaleEffect(x: 1, y: 1.4)
            Text("First reflection unlocks after 3 entries.")
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
            Button("View Plans", action: onUpgrade)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(MirrorTheme.accentGradient, in: Capsule())
                .foregroundStyle(.white)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label(label, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Divider().overlay(MirrorTheme.primary.opacity(0.15))
            Text(insight.content)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(22)
        .accentCard(cornerRadius: 26)
    }
}

private struct WeeklyDigestTextView: View {
    let insight: Insight

    private var sections: [(title: String, body: String)] {
        parseDigest(insight.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Weekly Digest", systemImage: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 14)

            Divider().overlay(Color.indigo.opacity(0.18)).padding(.bottom, 16)

            if sections.isEmpty {
                // Fallback: render raw content
                Text(insight.content)
                    .font(.system(size: 15, weight: .regular))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.title) { section in
                        DigestSection(title: section.title, content: section.body)
                    }
                }
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
                .opacity(0.55)
        }
    }

    private func parseDigest(_ text: String) -> [(title: String, body: String)] {
        let sectionHeaders = ["THIS WEEK'S THEME", "YOUR ENERGY", "WHAT'S BUILDING", "WATCH OUT FOR", "NEXT WEEK"]
        var results: [(title: String, body: String)] = []
        var remaining = text

        for (i, header) in sectionHeaders.enumerated() {
            guard let headerRange = remaining.range(of: header + ":") else { continue }
            let afterHeader = String(remaining[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Find end: next header or end of string
            var bodyEnd = afterHeader.endIndex
            for nextHeader in sectionHeaders[(i+1)...] {
                if let nextRange = afterHeader.range(of: nextHeader + ":") {
                    bodyEnd = nextRange.lowerBound
                    break
                }
            }

            let body = String(afterHeader[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            results.append((title: header, body: body))
        }

        return results
    }
}

private struct DigestSection: View {
    let title: String
    let content: String

    private var sectionColor: Color {
        switch title {
        case "THIS WEEK'S THEME": return .indigo
        case "YOUR ENERGY": return .orange
        case "WHAT'S BUILDING": return .green
        case "WATCH OUT FOR": return .red
        case "NEXT WEEK": return MirrorTheme.primary
        default: return MirrorTheme.primary
        }
    }

    private var sectionIcon: String {
        switch title {
        case "THIS WEEK'S THEME": return "quote.bubble"
        case "YOUR ENERGY": return "bolt"
        case "WHAT'S BUILDING": return "arrow.up.forward"
        case "WATCH OUT FOR": return "eye"
        case "NEXT WEEK": return "arrow.right.circle"
        default: return "circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: sectionIcon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(sectionColor)

            Text(content)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
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
