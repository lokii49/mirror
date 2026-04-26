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
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Daily Reflection", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MirrorTheme.primary)
                        Text("Patterns from your recent entries, shaped into one useful observation.")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                    .padding(18)
                    .futureSurface(cornerRadius: 26)

                    statusContent
                }
                .padding(16)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
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

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.nudgeState {
        case .idle:
            EmptyView()

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Preparing your reflection")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .futureSurface(cornerRadius: 22)

        case .loaded(let insight):
            InsightTextView(insight: insight)

        case .needsMoreEntries(let remaining):
            VStack(alignment: .leading, spacing: 10) {
                Label("\(remaining) more \(remaining == 1 ? "entry" : "entries") needed", systemImage: "book.pages")
                    .font(.headline)
                ProgressView(value: Double(max(0, 7 - remaining)), total: 7)
                    .tint(MirrorTheme.primary)
                Text("Write a few more entries to unlock a useful daily reflection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .futureSurface(cornerRadius: 22)

        case .subscriptionRequired:
            VStack(alignment: .leading, spacing: 12) {
                Label("Core required", systemImage: "sparkles")
                    .font(.headline)
                Text("Daily reflections are part of Mirror Core.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("View Plans") { showPaywall = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .futureSurface(cornerRadius: 22)

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("Couldn’t load insight", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await viewModel.loadNudge(entries: entries, insights: insights, context: modelContext) }
                }
            }
            .padding(18)
            .futureSurface(cornerRadius: 22)
        }
    }
}

private struct InsightTextView: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(insight.content)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)

            Text(insight.generatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .futureSurface(cornerRadius: 22)
    }
}
