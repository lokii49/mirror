import SwiftUI
import SwiftData
import Charts

struct MoodTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    @State private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var selectedRange: TimeRange = .thirtyDays

    // Full-history heatmap data — independent of selectedRange, but was being
    // recomputed from scratch on every body re-eval (range taps, paywall sheet, etc).
    @State private var cachedAllMoodPoints: [MoodPoint] = []
    @State private var cachedDayMoodMap: [String: String] = [:]
    @State private var cachedHeatmapWeeks: [[Date?]] = []

    private var contentMaxWidth: CGFloat { hSizeClass == .regular ? 700 : .infinity }

    enum TimeRange: String, CaseIterable {
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case allTime = "All"

        var days: Int? {
            switch self {
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .allTime: return nil
            }
        }

        var displayName: LocalizedStringKey {
            switch self {
            case .thirtyDays: return "30D"
            case .ninetyDays: return "90D"
            case .allTime: return "All"
            }
        }
    }


    private var filteredEntries: [Entry] {
        guard let days = selectedRange.days else { return entries }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return entries.filter { $0.createdAt >= cutoff }
    }

    private var moodEntries: [Entry] {
        filteredEntries.filter { $0.mood != nil && !($0.mood!.isEmpty) }
    }

    private var points: [MoodPoint] {
        moodEntries
            .compactMap { entry in
                guard let mood = entry.mood,
                      let score = MirrorTheme.moodScore[mood] else { return nil }
                return MoodPoint(id: entry.id, date: entry.createdAt, mood: mood, score: score)
            }
            .sorted { $0.date < $1.date }
    }

    private func recomputeHeatmapCache() {
        let cal = Calendar.current

        let points = entries
            .compactMap { entry -> MoodPoint? in
                guard let mood = entry.mood,
                      let score = MirrorTheme.moodScore[mood] else { return nil }
                return MoodPoint(id: entry.id, date: entry.createdAt, mood: mood, score: score)
            }
            .sorted { $0.date < $1.date }
        cachedAllMoodPoints = points

        // Most recent mood per calendar day (points sorted asc → last write wins)
        var dayMoodMap: [String: String] = [:]
        for point in points {
            let c = cal.dateComponents([.year, .month, .day], from: point.date)
            let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            dayMoodMap[key] = point.mood
        }
        cachedDayMoodMap = dayMoodMap

        // Array of weeks [[Date?]] from first entry's week to today. Each week = 7 slots (Mon–Sun).
        guard let earliest = points.first?.date else {
            cachedHeatmapWeeks = []
            return
        }
        let today = Date()
        var startComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: earliest)
        startComps.weekday = 2 // Monday
        guard var weekStart = cal.date(from: startComps) else {
            cachedHeatmapWeeks = []
            return
        }
        if weekStart > earliest {
            weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        }

        var weeks: [[Date?]] = []
        while weekStart <= today {
            var week: [Date?] = []
            for offset in 0..<7 {
                if let d = cal.date(byAdding: .day, value: offset, to: weekStart), d <= today {
                    week.append(d)
                } else {
                    week.append(nil)
                }
            }
            weeks.append(week)
            weekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
        }
        cachedHeatmapWeeks = weeks
    }

    private var moodDistribution: [(mood: String, count: Int, color: Color)] {
        let counts = Dictionary(grouping: moodEntries.compactMap(\.mood), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        return counts.map { (mood: $0.key, count: $0.value, color: MirrorTheme.moodColor(for: $0.key)) }
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        // Collect unique written days (newest first)
        var writtenDays: [Date] = []
        var seen = Set<Date>()
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if seen.insert(day).inserted {
                writtenDays.append(day)
            }
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

    private var consecutiveNegativeCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var count = 0
        for entry in entries {
            guard entry.createdAt >= sevenDaysAgo else { break }
            guard let mood = entry.mood else { continue }
            if MirrorTheme.negativeMoods.contains(mood) {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private var averageMoodScore: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.score).reduce(0, +) / Double(points.count)
    }

    var body: some View {
        Group {
            if subscriptionService.isDeep {
                mainContent
            } else {
                blurredDeepPreview
            }
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle("Mood Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if consecutiveNegativeCount >= 3 {
                    moodAlertBanner
                }

                rangeSelector
                statsRow
                moodScaleRow

                if selectedRange == .allTime {
                    if !cachedAllMoodPoints.isEmpty {
                        heatmapCard
                    } else {
                        noDataCard
                    }
                } else {
                    if points.count >= 2 {
                        moodChartCard
                    } else {
                        noDataCard
                    }
                }

                if !moodDistribution.isEmpty {
                    moodDistributionCard
                }
            }
            .padding(16)
            .padding(.bottom, 24)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .task(id: entries.map(\.encryptedMood).hashValue) {
            recomputeHeatmapCache()
        }
    }

    private var moodAlertBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MirrorTheme.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your last \(consecutiveNegativeCount) entries show low mood")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text("Consider taking a moment to check in with yourself.")
                    .font(.system(size: 12))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(MirrorTheme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MirrorTheme.ember.opacity(0.35), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MirrorTheme.ember)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.displayName)
                        .font(.system(size: 14, weight: selectedRange == range ? .bold : .medium))
                        .foregroundStyle(selectedRange == range ? MirrorTheme.primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedRange == range ? MirrorTheme.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .futureSurface(cornerRadius: 16)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(
                value: "\(moodEntries.count)",
                label: "Moods logged",
                icon: "face.smiling",
                color: MirrorTheme.primary
            )
            statPill(
                value: averageMoodScore > 0 ? String(format: "%.1f", averageMoodScore) : "—",
                valueSuffix: averageMoodScore > 0 ? "/5" : "",
                label: "Avg. score",
                icon: "chart.bar",
                color: averageMoodScore >= 3.5 ? .green : averageMoodScore >= 2.5 ? .orange : .red
            )
            statPill(
                value: "\(currentStreak)d",
                label: "Streak",
                icon: "flame.fill",
                color: .orange
            )
        }
    }

    private func statPill(value: String, valueSuffix: String = "", label: LocalizedStringKey, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                if !valueSuffix.isEmpty {
                    Text(valueSuffix)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .futureSurface(cornerRadius: 18)
    }

    @ViewBuilder
    private var moodScaleRow: some View {
        if averageMoodScore > 0 {
            let fraction = CGFloat((averageMoodScore - 1.0) / 4.0)
            let interpretation: LocalizedStringKey = {
                if averageMoodScore >= 4.5 { return "Thriving" }
                if averageMoodScore >= 3.5 { return "Positive" }
                if averageMoodScore >= 2.5 { return "Mixed, leaning neutral" }
                if averageMoodScore >= 1.5 { return "Mixed, leaning low" }
                return "Low mood"
            }()
            let barColor: Color = averageMoodScore >= 3.5 ? .green : averageMoodScore >= 2.5 ? .orange : .red

            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .opacity(0.35)
                        .clipShape(Capsule())

                        Circle()
                            .fill(barColor)
                            .frame(width: 11, height: 11)
                            .shadow(color: barColor.opacity(0.5), radius: 3, x: 0, y: 1)
                            .offset(x: max(0, min(geo.size.width - 11, geo.size.width * fraction - 5.5)))
                    }
                }
                .frame(height: 11)

                HStack {
                    Text("1 · Low")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(interpretation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(barColor)
                    Spacer()
                    Text("5 · High")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Scatter chart (30D / 90D)

    private var moodChartCard: some View {
        MoodChartCard(points: points)
    }

    // MARK: - Calendar heatmap (All)

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mood calendar", systemImage: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    heatmapGrid
                        .id("end")
                        .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo("end", anchor: .trailing)
                }
            }

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 11, height: 11)
                Text("No entry")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Color = mood")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 22)
    }

    @ViewBuilder
    private var heatmapGrid: some View {
        let cal = Calendar.current
        let weeks = cachedHeatmapWeeks
        let moodMap = cachedDayMoodMap
        let cell: CGFloat = 13
        let gap: CGFloat = 2

        // One VStack column per week — month label on top overflows its frame to the right
        HStack(alignment: .top, spacing: gap) {
            ForEach(weeks.indices, id: \.self) { wi in
                let first = weeks[wi].compactMap { $0 }.first
                let showMonth: Bool = {
                    guard let d = first else { return false }
                    return wi == 0 || cal.component(.day, from: d) <= 7
                }()
                let monthLabel = showMonth
                    ? (first.map { $0.formatted(.dateTime.month(.abbreviated)) } ?? "")
                    : ""

                VStack(alignment: .leading, spacing: gap) {
                    // fixedSize lets "Aug" render beyond the 13pt column width
                    Text(monthLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 12)

                    ForEach(0..<7, id: \.self) { di in
                        if let date = weeks[wi][di] {
                            let c = cal.dateComponents([.year, .month, .day], from: date)
                            let key = String(format: "%04d-%02d-%02d",
                                             c.year ?? 0, c.month ?? 0, c.day ?? 0)
                            let mood = moodMap[key]
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(mood != nil
                                      ? MirrorTheme.moodColor(for: mood!).opacity(0.85)
                                      : Color.secondary.opacity(0.12))
                                .frame(width: cell, height: cell)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
                .frame(width: cell) // HStack sees 13pt per column; label overflows visually
            }
        }
    }

    // MARK: - Empty state

    private var noDataCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Not enough mood data")
                .font(.system(size: 15, weight: .semibold))
            Text("Log your mood when writing entries to see your timeline.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .futureSurface(cornerRadius: 22)
    }

    private var moodDistributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Mood breakdown", systemImage: "chart.pie.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                let total = moodDistribution.map(\.count).reduce(0, +)
                ForEach(moodDistribution.prefix(8), id: \.mood) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 10, height: 10)
                        Text(MirrorTheme.localizedMoodName(for: item.mood))
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(item.count)×")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        GeometryReader { geo in
                            Capsule()
                                .fill(item.color.opacity(0.3))
                                .frame(width: total > 0 ? geo.size.width * CGFloat(item.count) / CGFloat(total) : 0)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 60, height: 6)
                    }
                }
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 22)
    }

    // MARK: - Blurred preview (free users)

    // Fake data matching the screenshot: Hopeful ×2, Anxious ×2, avg 3.0, 3d streak
    private var previewPoints: [MoodPoint] {
        let cal = Calendar.current
        let today = Date()
        func d(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today) ?? today }
        return [
            MoodPoint(id: UUID(), date: d(-4), mood: "Hopeful",  score: 4),
            MoodPoint(id: UUID(), date: d(-3), mood: "Anxious",  score: 2),
            MoodPoint(id: UUID(), date: d(-2), mood: "Hopeful",  score: 4),
            MoodPoint(id: UUID(), date: d(-1), mood: "Anxious",  score: 2),
        ]
    }

    private var blurredDeepPreview: some View {
        ZStack {
            // Blurred mock content behind the overlay
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewRangeSelector
                    previewStatsRow
                    previewMoodScaleRow
                    previewMoodChartCard
                    previewMoodDistributionCard
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(16)
                .padding(.bottom, 24)
            }
            .blur(radius: 8)
            .allowsHitTesting(false)

            // Lock overlay card
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.violetDim)
                        .frame(width: 72, height: 72)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(MirrorTheme.violetLight)
                }
                VStack(spacing: 8) {
                    Text("Mood Timeline")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Trend charts, analytics, and low-mood\nalerts are part of Deep.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button { showPaywall = true } label: {
                    Text("Unlock with Deep")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [MirrorTheme.violet, Color.indigo], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .shadow(color: MirrorTheme.violet.opacity(0.28), radius: 16, x: 0, y: 6)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 28)
            .shadow(color: .black.opacity(0.06), radius: 24, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview sub-views (static mock data, blurred)

    private var previewRangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.displayName)
                    .font(.system(size: 14, weight: range == .thirtyDays ? .bold : .medium))
                    .foregroundStyle(range == .thirtyDays ? MirrorTheme.primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        range == .thirtyDays ? MirrorTheme.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
        }
        .padding(4)
        .futureSurface(cornerRadius: 16)
    }

    private var previewStatsRow: some View {
        HStack(spacing: 12) {
            statPill(value: "4", label: "Moods logged", icon: "face.smiling", color: MirrorTheme.primary)
            statPill(value: "3.0", valueSuffix: "/5", label: "Avg. score", icon: "chart.bar", color: .orange)
            statPill(value: "3d", label: "Streak", icon: "flame.fill", color: .orange)
        }
    }

    @ViewBuilder
    private var previewMoodScaleRow: some View {
        let fraction: CGFloat = 0.5
        let barColor: Color = .orange
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [.red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing)
                        .opacity(0.35)
                        .clipShape(Capsule())
                    Circle()
                        .fill(barColor)
                        .frame(width: 11, height: 11)
                        .shadow(color: barColor.opacity(0.5), radius: 3, x: 0, y: 1)
                        .offset(x: max(0, min(geo.size.width - 11, geo.size.width * fraction - 5.5)))
                }
            }
            .frame(height: 11)
            HStack {
                Text("1 · Low").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("Mixed, leaning neutral").font(.system(size: 11, weight: .semibold)).foregroundStyle(barColor)
                Spacer()
                Text("5 · High").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var previewMoodChartCard: some View {
        MoodChartCard(points: previewPoints)
    }

    @ViewBuilder
    private var previewMoodDistributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Mood breakdown", systemImage: "chart.pie.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(["Hopeful", "Anxious"], id: \.self) { mood in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: mood))
                            .frame(width: 10, height: 10)
                        Text(MirrorTheme.localizedMoodName(for: mood))
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("2×")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        GeometryReader { geo in
                            Capsule()
                                .fill(MirrorTheme.moodColor(for: mood).opacity(0.3))
                                .frame(width: geo.size.width * 0.5)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 60, height: 6)
                    }
                }
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 22)
    }
}

// MARK: - Shared chart card (used by both real view and blurred preview)

private struct MoodPoint: Identifiable {
    let id: UUID
    let date: Date
    let mood: String
    let score: Double
}

private struct MoodChartCard: View {
    let points: [MoodPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mood over time", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart(points) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Mood", point.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [MirrorTheme.violet.opacity(0.18), MirrorTheme.violet.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Mood", point.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [MirrorTheme.violet, MirrorTheme.ember],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Mood", point.score)
                )
                .foregroundStyle(MirrorTheme.moodColor(for: point.mood))
                .symbolSize(80)
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
                AxisMarks(format: .dateTime.month(.abbreviated).day())
            }
            .frame(height: 160)
        }
        .padding(18)
        .futureSurface(cornerRadius: 22)
    }
}
