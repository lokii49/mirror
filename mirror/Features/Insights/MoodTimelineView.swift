import SwiftUI
import SwiftData
import Charts

struct MoodTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    @State private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var selectedRange: TimeRange = .thirtyDays

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
    }

    private static let moodScore: [String: Double] = [
        "Joyful": 5, "Grateful": 5, "Peaceful": 4, "Content": 4, "Energized": 4, "Hopeful": 4,
        "Anxious": 2, "Overwhelmed": 1, "Frustrated": 2, "Drained": 1, "Sad": 1, "Numb": 2,
    ]

    private static let negativeMoods: Set<String> = [
        "Anxious", "Overwhelmed", "Frustrated", "Drained", "Sad", "Numb",
    ]

    private var filteredEntries: [Entry] {
        guard let days = selectedRange.days else { return entries }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return entries.filter { $0.createdAt >= cutoff }
    }

    private var moodEntries: [Entry] {
        filteredEntries.filter { $0.mood != nil && !($0.mood!.isEmpty) }
    }

    private struct MoodPoint: Identifiable {
        let id: UUID
        let date: Date
        let mood: String
        let score: Double
    }

    private var points: [MoodPoint] {
        moodEntries
            .compactMap { entry in
                guard let mood = entry.mood,
                      let score = MoodTimelineView.moodScore[mood] else { return nil }
                return MoodPoint(id: entry.id, date: entry.createdAt, mood: mood, score: score)
            }
            .sorted { $0.date < $1.date }
    }

    private var moodDistribution: [(mood: String, count: Int, color: Color)] {
        let counts = Dictionary(grouping: moodEntries.compactMap(\.mood), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        return counts.map { (mood: $0.key, count: $0.value, color: MirrorTheme.moodColor(for: $0.key)) }
    }

    private var currentStreak: Int {
        var streak = 0
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let calendar = Calendar.current
        var checkDate = calendar.startOfDay(for: Date())

        for entry in sorted {
            let entryDay = calendar.startOfDay(for: entry.createdAt)
            if entryDay == checkDate {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if entryDay < checkDate {
                break
            }
        }
        return streak
    }

    private var consecutiveNegativeCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let sorted = entries.filter { $0.createdAt >= sevenDaysAgo }.sorted { $0.createdAt > $1.createdAt }
        var count = 0
        for entry in sorted {
            guard let mood = entry.mood else { break }
            if MoodTimelineView.negativeMoods.contains(mood) {
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
                deepLockedState
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

                if points.count >= 2 {
                    moodChartCard
                } else {
                    noDataCard
                }

                if !moodDistribution.isEmpty {
                    moodDistributionCard
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private var moodAlertBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your last \(consecutiveNegativeCount) entries show low mood")
                    .font(.system(size: 14, weight: .semibold))
                Text("Consider taking a moment to check in with yourself.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var rangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.rawValue)
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

    private func statPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .futureSurface(cornerRadius: 18)
    }

    private var moodChartCard: some View {
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
                        colors: [MirrorTheme.primary.opacity(0.15), MirrorTheme.primary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Mood", point.score)
                )
                .foregroundStyle(MirrorTheme.primary.opacity(0.6))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))

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
                        Text(item.mood)
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

    private var deepLockedState: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            VStack(spacing: 8) {
                Text("Mood Timeline")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Full mood analytics, trend charts,\nand low-mood alerts are part of Deep.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showPaywall = true
            } label: {
                Text("Upgrade to Deep")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .shadow(color: Color.purple.opacity(0.28), radius: 16, x: 0, y: 6)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
