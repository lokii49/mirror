import SwiftUI
import SwiftData

struct InsightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var insights: [Insight]
    @State private var viewModel = InsightViewModel()
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    statusContent
                }
                .padding(16)
                .padding(.bottom, 16)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
        .task {
            await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext)
        }
    }

    private var heroCard: some View {
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
    private var statusContent: some View {
        switch viewModel.nudgeState {
        case .idle:
            EmptyView()

        case .loading:
            LoadingInsightCard()

        case .loaded(let insight):
            InsightTextView(insight: insight)
                .glowShadow(color: MirrorTheme.primary, radius: 32)

        case .needsMoreEntries(let remaining):
            NeedsMoreEntriesCard(remaining: remaining)

        case .subscriptionRequired:
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
                        Text("Mirror Core")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Daily reflections unlock with Core.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                Button("View Plans") { showPaywall = true }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(MirrorTheme.accentGradient, in: Capsule())
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
            }
            .padding(20)
            .futureSurface(cornerRadius: 24)

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("Couldn't load", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MirrorTheme.primary)
            }
            .padding(20)
            .futureSurface(cornerRadius: 22)
        }
    }
}

private struct LoadingInsightCard: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MirrorTheme.primary.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Preparing your reflection")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Reading recent entries…")
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

            ProgressView(value: Double(max(0, 7 - remaining)), total: 7)
                .tint(MirrorTheme.primary)
                .scaleEffect(x: 1, y: 1.4)
                .padding(.top, 2)

            Text("First reflection unlocks after 7 entries.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .futureSurface(cornerRadius: 24)
    }
}

private struct InsightTextView: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Daily Reflection", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .overlay(MirrorTheme.primary.opacity(0.15))

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
