import SwiftUI
import SwiftData

struct MonthlyReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var insights: [Insight]

    @State private var showPaywall = false
    var viewModel: InsightViewModel

    private var thisMonthEntries: [Entry] {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return entries.filter { $0.createdAt >= start }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                reportContent
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle("Monthly Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task {
            await viewModel.loadMonthlyReport(entries: entries, insights: insights, context: modelContext)
        }
        .onChange(of: insights.count) { _, _ in
            Task { await viewModel.loadMonthlyReport(entries: entries, insights: insights, context: modelContext) }
        }
    }

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Monthly Deep Report", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text(Self.monthFormatter.string(from: Date()))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.purple.opacity(0.35), radius: 14, x: 0, y: 6)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 26)
    }

    @ViewBuilder
    private var reportContent: some View {
        switch viewModel.monthlyReportState {
        case .idle:
            EmptyView()
        case .loading:
            reportLoadingCard
        case .loaded(let insight):
            MonthlyStatsStrip(entries: thisMonthEntries)
            MonthlyReportCard(insight: insight)
                .glowShadow(color: .purple, radius: 28)
        case .notEnoughEntries(let remaining):
            notEnoughEntriesCard(remaining: remaining)
        case .subscriptionRequired:
            deepLockedCard
        case .pendingNightlyGeneration:
            nightlyPendingCard
        case .error(let message):
            errorCard(message: message)
        }
    }

    private var reportLoadingCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Building your monthly report")
                        .font(.system(size: 15, weight: .medium))
                    Text("Reading all your entries this month…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Keep mirror open — this takes 1–2 minutes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                Spacer()
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
    }

    private func notEnoughEntriesCard(remaining: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(remaining) more \(remaining == 1 ? "entry" : "entries") to go")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Your deep monthly report unlocks at 20 entries.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(max(0, 20 - remaining)), total: 20)
                .tint(.purple)
                .scaleEffect(x: 1, y: 1.4)
            Text("Keep writing — generates automatically when ready.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .futureSurface(cornerRadius: 24)
    }

    private var deepLockedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep required")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Monthly reports are part of MirrorNotes Deep.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: { showPaywall = true }) {
                Text("Upgrade to Deep")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(20)
        .futureSurface(cornerRadius: 24)
    }

    private var nightlyPendingCard: some View {
        NightlyPendingCard(
            label: "Report generates overnight",
            sublabel: "Mirror will prepare this while your phone is charging. To protect device performance.",
            icon: "doc.text.magnifyingglass",
            iconColor: .purple
        )
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't generate report", systemImage: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Mirror will retry automatically tonight while your phone charges.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
    }
}

private struct MonthlyStatsStrip: View {
    let entries: [Entry]

    private var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    private var topMood: String? {
        Dictionary(grouping: entries.compactMap(\.mood), by: { $0 })
            .mapValues(\.count)
            .max(by: { $0.value < $1.value })?
            .key
    }

    private var voiceCount: Int {
        entries.filter { $0.source == .voice || $0.hasVoiceNotes }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            statCell(
                value: "\(entries.count)",
                label: "entries"
            )
            Divider().frame(height: 32)
            statCell(
                value: totalWords >= 1000 ? String(format: "%.1fk", Double(totalWords) / 1000.0) : "\(totalWords)",
                label: "words"
            )
            if let mood = topMood {
                Divider().frame(height: 32)
                statCell(value: mood, label: "top mood")
            }
            if voiceCount > 0 {
                Divider().frame(height: 32)
                statCell(value: "\(voiceCount)", label: "voice notes")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .futureSurface(cornerRadius: 18)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.purple)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MonthlyReportCard: View {
    let insight: Insight

    private let headers = [
        "YOUR MONTH IN ONE IMAGE",
        "THE TENSION AT THE CENTER",
        "A MOMENT THAT SHIFTED SOMETHING",
        "WHAT YOU'RE BECOMING",
        "WHAT WANTS TO BE RELEASED",
        "YOUR QUESTION FOR NEXT MONTH",
    ]

    private let headerIcons: [String: (String, Color)] = [
        "YOUR MONTH IN ONE IMAGE": ("moon.stars.fill", .purple),
        "THE TENSION AT THE CENTER": ("arrow.left.arrow.right", .orange),
        "A MOMENT THAT SHIFTED SOMETHING": ("sparkles", .blue),
        "WHAT YOU'RE BECOMING": ("leaf.fill", .green),
        "WHAT WANTS TO BE RELEASED": ("wind", .secondary),
        "YOUR QUESTION FOR NEXT MONTH": ("questionmark.circle.fill", Color(red: 0.9, green: 0.7, blue: 0.1)),
    ]

    private struct Section: Identifiable {
        let id = UUID()
        let header: String
        let body: String
        let icon: String
        let color: Color
    }

    private var sections: [Section] {
        headers.compactMap { header in
            guard let body = extractBody(for: header) else { return nil }
            let (icon, color) = headerIcons[header] ?? ("circle.fill", .secondary)
            return Section(header: header, body: body, icon: icon, color: color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Monthly Deep Report", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 16)

            Divider().overlay(Color.purple.opacity(0.15))
                .padding(.bottom, 16)

            if sections.isEmpty {
                Text(insight.content)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineSpacing(7)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        reportSection(section)
                    }
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(MirrorTheme.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func reportSection(_ section: Section) -> some View {
        let isQuestion = section.header == "YOUR QUESTION FOR NEXT MONTH"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(section.color)
                Text(section.header.localizedCapitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(section.color)
                    .tracking(0.3)
            }
            if isQuestion {
                Text(section.body)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .italic()
                    .lineSpacing(5)
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.top, 2)
            } else {
                Text(section.body)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    private func extractBody(for header: String) -> String? {
        let text = insight.content
        let normalizedText = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        guard let headerRange = normalizedText.range(of: "\(header):", options: [.caseInsensitive]) else { return nil }
        let afterHeader = String(normalizedText[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let allHeaders = [
            "YOUR MONTH IN ONE IMAGE",
            "THE TENSION AT THE CENTER",
            "A MOMENT THAT SHIFTED SOMETHING",
            "WHAT YOU'RE BECOMING",
            "WHAT WANTS TO BE RELEASED",
            "YOUR QUESTION FOR NEXT MONTH",
        ]
        var bodyEnd = afterHeader.endIndex
        for nextHeader in allHeaders {
            if nextHeader == header { continue }
            if let nextRange = afterHeader.range(of: "\(nextHeader):", options: [.caseInsensitive]) {
                if nextRange.lowerBound < bodyEnd {
                    bodyEnd = nextRange.lowerBound
                }
            }
        }
        return String(afterHeader[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
