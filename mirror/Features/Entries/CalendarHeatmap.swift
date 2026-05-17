import SwiftUI

struct CalendarHeatmap: View {
    let entries: [Entry]
    var selectedDate: Date?
    var onDaySelected: ((Date?) -> Void)?

    private let cellSize: CGFloat = 12
    private let cellGap: CGFloat = 3
    private let weeksToShow = 53

    private var cellStep: CGFloat { cellSize + cellGap }
    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    // MARK: - Data model

    private struct WeekColumn: Identifiable {
        let id: Int
        let days: [Date?]
        let monthLabel: String?
    }

    private var weeks: [WeekColumn] {
        var startComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        startComps.weekday = 1
        guard
            let thisWeekSunday = cal.date(from: startComps),
            let firstSunday = cal.date(byAdding: .weekOfYear, value: -(weeksToShow - 1), to: thisWeekSunday)
        else { return [] }

        var result: [WeekColumn] = []
        var lastMonthLabel: String? = nil

        for i in 0..<weeksToShow {
            guard let sunday = cal.date(byAdding: .weekOfYear, value: i, to: firstSunday) else { continue }
            var days: [Date?] = []
            for d in 0..<7 {
                let day = cal.date(byAdding: .day, value: d, to: sunday)!
                days.append(day <= today ? day : nil)
            }

            let monthStr = sunday.formatted(.dateTime.month(.abbreviated))
            let label: String? = (monthStr != lastMonthLabel) ? monthStr : nil
            if label != nil { lastMonthLabel = monthStr }

            result.append(WeekColumn(id: i, days: days, monthLabel: label))
        }
        return result
    }

    private var entriesByDay: [Date: [Entry]] {
        var dict: [Date: [Entry]] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.createdAt)
            dict[day, default: []].append(e)
        }
        return dict
    }

    // MARK: - Stats

    private var streakCount: Int {
        let days = Set(entries.map { cal.startOfDay(for: $0.createdAt) })
        var day = today
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    // MARK: - Cell color

    private func color(for date: Date?) -> Color {
        guard let date else { return Color(.systemFill).opacity(0.4) }
        let dayEntries = entriesByDay[date] ?? []
        guard !dayEntries.isEmpty else { return Color(.systemFill) }

        let count = dayEntries.count
        if let mood = representativeMood(for: dayEntries) {
            let base = MirrorTheme.moodColor(for: mood)
            return count >= 3 ? base : base.opacity(0.35 + Double(count) * 0.25)
        }
        switch count {
        case 1: return MirrorTheme.primary.opacity(0.30)
        case 2: return MirrorTheme.primary.opacity(0.60)
        default: return MirrorTheme.primary
        }
    }

    private func representativeMood(for dayEntries: [Entry]) -> String? {
        let moodEntries = dayEntries
            .compactMap { entry -> (mood: String, createdAt: Date)? in
                guard let mood = entry.mood, !mood.isEmpty else { return nil }
                return (mood, entry.createdAt)
            }
        guard !moodEntries.isEmpty else { return nil }

        let counts = Dictionary(grouping: moodEntries, by: \.mood).mapValues(\.count)
        let highestCount = counts.values.max() ?? 0
        let topMoods = Set(counts.filter { $0.value == highestCount }.map(\.key))

        return moodEntries
            .filter { topMoods.contains($0.mood) }
            .max { $0.createdAt < $1.createdAt }?
            .mood
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        dayLabels
                        LazyHStack(alignment: .top, spacing: cellGap) {
                            ForEach(weeks) { week in
                                column(week)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                }
                .onAppear {
                    if let last = weeks.last {
                        proxy.scrollTo(last.id, anchor: .trailing)
                    }
                }
            }

        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack(spacing: 0) {
            statChip(
                value: "\(entries.count)",
                label: entries.count == 1 ? "entry" : "entries",
                icon: "book.pages",
                color: MirrorTheme.primary
            )
            Spacer()
            if streakCount > 0 {
                statChip(
                    value: "\(streakCount)",
                    label: "day streak",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private func statChip(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Day-of-week labels

    private var dayLabels: some View {
        VStack(spacing: cellGap) {
            Color.clear.frame(height: 14)
            ForEach(0..<7, id: \.self) { i in
                Group {
                    switch i {
                    case 2: Text("M")
                    case 4: Text("W")
                    case 6: Text("F")
                    default: Color.clear
                    }
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 12, height: cellSize, alignment: .trailing)
            }
        }
        .padding(.trailing, 4)
    }

    // MARK: - Week column

    private func column(_ week: WeekColumn) -> some View {
        VStack(alignment: .leading, spacing: cellGap) {
            if let label = week.monthLabel {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(height: 14, alignment: .bottomLeading)
                    .lineLimit(1)
            } else {
                Color.clear.frame(height: 14)
            }
            ForEach(0..<7, id: \.self) { i in
                cell(for: week.days[i])
            }
        }
        .id(week.id)
    }

    // MARK: - Individual day cell

    private func cell(for date: Date?) -> some View {
        let isSelected = date.map { cal.isDate($0, inSameDayAs: selectedDate ?? .distantPast) } ?? false
        let isToday = date.map { cal.isDateInToday($0) } ?? false

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: date))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isToday || isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            isSelected ? MirrorTheme.primary : Color.primary.opacity(0.45),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let date else { return }
                onDaySelected?(isSelected ? nil : date)
            }
    }
}
