import SwiftUI
import SwiftData

struct MonthlyReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var insights: [Insight]

    @State private var showPaywall = false
    @State private var selectedMonth: Date = Calendar.current.startOfMonth(Date())
    var viewModel: InsightViewModel

    private var contentMaxWidth: CGFloat { hSizeClass == .regular ? 700 : .infinity }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var isCurrentMonth: Bool {
        DateHelpers.monthIdentifier(for: selectedMonth) == DateHelpers.monthIdentifier(for: Date())
    }

    private var selectedMonthEntries: [Entry] {
        let cal = Calendar.current
        let start = cal.startOfMonth(selectedMonth)
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return entries.filter { $0.createdAt >= start && $0.createdAt < end }
    }

    private var cachedReportForSelectedMonth: Insight? {
        let period = DateHelpers.monthIdentifier(for: selectedMonth)
        return insights.first { $0.type == .monthlyReport && $0.periodIdentifier == period }
    }

    private var earliestAllowedMonth: Date {
        guard let oldest = entries.last else { return Calendar.current.startOfMonth(Date()) }
        return Calendar.current.startOfMonth(oldest.createdAt)
    }

    private var canGoBack: Bool { selectedMonth > earliestAllowedMonth }
    private var canGoForward: Bool { !isCurrentMonth }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                reportContent
            }
            .padding(16)
            .padding(.bottom, 24)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
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
        HStack(alignment: .center, spacing: 14) {
            Button {
                guard canGoBack else { return }
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canGoBack ? MirrorTheme.violetLight : MirrorTheme.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(canGoBack ? MirrorTheme.violetDim : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)

            VStack(alignment: .center, spacing: 4) {
                Label("Monthly Deep Report", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MirrorTheme.violetLight)
                    .tracking(0.8)
                Text(Self.monthFormatter.string(from: selectedMonth))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .animation(.none, value: selectedMonth)
            }
            .frame(maxWidth: .infinity)

            Button {
                guard canGoForward else { return }
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canGoForward ? MirrorTheme.violetLight : MirrorTheme.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(canGoForward ? MirrorTheme.violetDim : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(20)
        .inkSurface(cornerRadius: 26)
    }

    @ViewBuilder
    private var reportContent: some View {
        if !isCurrentMonth {
            // Past month: show cached report only, no generation
            if let cached = cachedReportForSelectedMonth {
                MonthlyStatsStrip(entries: selectedMonthEntries)
                MonthlyReportCard(insight: cached)
                    .glowShadow(color: MirrorTheme.violet, radius: 28)
            } else {
                pastMonthNoReportCard
            }
        } else {
            // Current month: full generation flow via ViewModel
            switch viewModel.monthlyReportState {
            case .idle:
                EmptyView()
            case .loading:
                reportLoadingCard
            case .loaded(let insight):
                MonthlyStatsStrip(entries: selectedMonthEntries)
                MonthlyReportCard(insight: insight)
                    .glowShadow(color: MirrorTheme.violet, radius: 28)
            case .notEnoughEntries(let remaining, let total):
                notEnoughEntriesCard(remaining: remaining, total: total)
            case .endOfMonthTooFewEntries(let count):
                endOfMonthTooFewEntriesCard(count: count)
            case .subscriptionRequired:
                deepLockedCard
            case .pendingNightlyGeneration:
                nightlyPendingCard
            case .modelNotInstalled:
                ModelNotInstalledCard()
            case .error(let message):
                errorCard(message: message) {
                    Task {
                        await viewModel.loadMonthlyReport(
                            entries: entries,
                            insights: insights,
                            context: modelContext,
                            forceRegenerate: true
                        )
                    }
                }
            }
        }
    }

    private var pastMonthNoReportCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(MirrorTheme.violetLight.opacity(0.5))
            Text("No report for \(Self.monthFormatter.string(from: selectedMonth))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MirrorTheme.textPrimary)
            Text("Reports generate automatically during the month. This month didn't have one.")
                .font(.system(size: 13))
                .foregroundStyle(MirrorTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .inkSurface(cornerRadius: 22)
    }

    private var reportLoadingCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.violetDim)
                        .frame(width: 40, height: 40)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.violetLight)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Building your monthly report")
                        .font(.system(size: 15, weight: .medium))
                    Text("Reading all your entries this month…")
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
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
        .inkSurface(cornerRadius: 22)
    }

    private func notEnoughEntriesCard(remaining: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.violetDim)
                        .frame(width: 40, height: 40)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.violetLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(remaining == 1 ? "1 more entry to go" : "\(remaining) more entries to go")
                        .font(.system(size: 16, weight: .semibold))
                    Text(total == 1 ? "Your deep monthly report unlocks at 1 entry." : "Your deep monthly report unlocks at \(total) entries.")
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            ProgressView(value: Double(max(0, total - remaining)), total: Double(total))
                .tint(MirrorTheme.violet)
                .scaleEffect(x: 1, y: 1.4)
            Text("Keep writing — generates automatically when ready.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MirrorTheme.textTertiary)
        }
        .padding(20)
        .inkSurface(cornerRadius: 24)
    }

    private func endOfMonthTooFewEntriesCard(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not enough entries this month")
                        .font(.system(size: 16, weight: .semibold))
                    Text(count == 1 ? "Only 1 entry written so far." : "Only \(count) entries written so far.")
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            Text("The monthly report needs at least 10 entries to reflect your month meaningfully. With just a few days left, there isn't enough to generate one for this month.")
                .font(.system(size: 13))
                .foregroundStyle(MirrorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep writing — your report will be ready next month.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MirrorTheme.textTertiary)
        }
        .padding(20)
        .inkSurface(cornerRadius: 24)
    }

    private var deepLockedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.violetDim)
                        .frame(width: 40, height: 40)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MirrorTheme.violetLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep required")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Monthly reports are part of MirrorNotes Deep.")
                        .font(.system(size: 14))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            Button(action: { showPaywall = true }) {
                Text("Upgrade to Deep")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .background(LinearGradient(colors: [MirrorTheme.violet, MirrorTheme.violetLight], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(20)
        .inkSurface(cornerRadius: 24)
    }

    private var nightlyPendingCard: some View {
        NightlyPendingCard(
            label: "Report generates overnight",
            sublabel: "Mirror will prepare this while your phone is charging. To protect device performance.",
            icon: "doc.text.magnifyingglass",
            iconColor: MirrorTheme.violet
        )
    }

    private func errorCard(message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't generate report", systemImage: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MirrorTheme.textSecondary)
            Text("Mirror will retry automatically tonight while your phone charges.")
                .font(.system(size: 13))
                .foregroundStyle(MirrorTheme.textTertiary)
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.violetLight)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .inkSurface(cornerRadius: 22)
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
                statCell(value: MirrorTheme.localizedMoodName(for: mood), label: "top mood")
            }
            if voiceCount > 0 {
                Divider().frame(height: 32)
                statCell(value: "\(voiceCount)", label: "voice notes")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .inkSurface(cornerRadius: 18)
    }

    private func statCell(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(MirrorTheme.violet)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MirrorTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MonthlyReportCard: View {
    let insight: Insight

    private let headerDisplayNames: [String: LocalizedStringKey] = [
        "YOUR MONTH IN ONE IMAGE": "Your Month In One Image",
        "THE TENSION AT THE CENTER": "The Tension At The Center",
        "A MOMENT THAT SHIFTED SOMETHING": "A Moment That Shifted Something",
        "WHAT YOU'RE BECOMING": "What You're Becoming",
        "WHAT WANTS TO BE RELEASED": "What Wants To Be Released",
        "YOUR QUESTION FOR NEXT MONTH": "Your Question For Next Month",
    ]

    private let headerIcons: [String: (String, Color)] = [
        "YOUR MONTH IN ONE IMAGE": ("moon.stars.fill", MirrorTheme.violet),
        "THE TENSION AT THE CENTER": ("arrow.left.arrow.right", .orange),
        "A MOMENT THAT SHIFTED SOMETHING": ("sparkles", .blue),
        "WHAT YOU'RE BECOMING": ("leaf.fill", .green),
        "WHAT WANTS TO BE RELEASED": ("wind", MirrorTheme.textTertiary),
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
        sectionHeaderAliases.compactMap { header in
            guard let body = extractBody(for: header.aliases) else { return nil }
            let (icon, color) = headerIcons[header.canonical] ?? ("circle.fill", .secondary)
            return Section(header: header.canonical, body: body, icon: icon, color: color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Monthly Deep Report", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MirrorTheme.violetLight)
                    .tracking(0.8)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MirrorTheme.textTertiary)
            }
            .padding(.bottom, 16)

            Divider().overlay(MirrorTheme.violet.opacity(0.25))
                .padding(.bottom, 16)

            if sections.isEmpty {
                Text(insight.content)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineSpacing(7)
                    .foregroundStyle(MirrorTheme.textPrimary)
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
        .inkCard(cornerRadius: 26)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(MirrorTheme.violet.opacity(0.25), lineWidth: 1)
        )
    }

    private func reportSection(_ section: Section) -> some View {
        let isQuestion = section.header == "YOUR QUESTION FOR NEXT MONTH"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(section.color)
                Text(headerDisplayNames[section.header] ?? LocalizedStringKey(section.header.localizedCapitalized))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(section.color)
                    .tracking(0.3)
            }
            if isQuestion {
                Text(section.body)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .italic()
                    .lineSpacing(5)
                    .foregroundStyle(MirrorTheme.textPrimary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.top, 2)
            } else {
                Text(section.body)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    private func extractBody(for aliases: [String]) -> String? {
        let text = insight.content
        let normalizedText = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        guard let headerRange = firstHeaderRange(in: normalizedText, aliases: aliases) else { return nil }
        let afterHeader = String(normalizedText[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var bodyEnd = afterHeader.endIndex
        for nextHeader in sectionHeaderAliases {
            if nextHeader.aliases == aliases { continue }
            if let nextRange = firstHeaderRange(in: afterHeader, aliases: nextHeader.aliases) {
                if nextRange.lowerBound < bodyEnd {
                    bodyEnd = nextRange.lowerBound
                }
            }
        }
        return String(afterHeader[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstHeaderRange(in text: String, aliases: [String]) -> Range<String.Index>? {
        aliases
            .lazy
            .compactMap { text.range(of: "\($0):", options: [.caseInsensitive, .diacriticInsensitive]) }
            .min(by: { $0.lowerBound < $1.lowerBound })
    }

    private var sectionHeaderAliases: [(canonical: String, aliases: [String])] {
        InsightService.monthlyReportSectionLabels.map { section in
            (canonical: section["en"] ?? "", aliases: Array(section.values))
        }
    }
}
