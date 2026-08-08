import SwiftUI

enum HeatmapMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var localizedName: LocalizedStringKey {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

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

    // MARK: - Mode & Navigation

    @AppStorage("heatmapMode") private var mode: HeatmapMode = .month
    @State private var viewDate: Date = Date()
    @Environment(\.appDisplayMode) private var displayMode

    // MARK: - Cache

    private struct DayCacheEntry {
        let count: Int
        let mood: String?
    }

    @State private var dayCache: [Date: DayCacheEntry] = [:]
    @State private var cachedStreak: Int = 0

    // MARK: - Haptic

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Data model (Year view)

    private struct WeekColumn: Identifiable {
        let id: Int
        let days: [Date?]
        let monthLabel: String?
        let monthDate: Date?
    }

    private struct MonthWeek: Identifiable {
        let id: Date
        let days: [Date]
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
            let isNewMonth = monthStr != lastMonthLabel
            if isNewMonth { lastMonthLabel = monthStr }

            var monthDate: Date? = nil
            if isNewMonth {
                let comps = cal.dateComponents([.year, .month], from: sunday)
                monthDate = cal.date(from: comps)
            }

            result.append(WeekColumn(id: i, days: days, monthLabel: isNewMonth ? monthStr : nil, monthDate: monthDate))
        }
        return result
    }

    // MARK: - Period entry counts (from cache, no re-filtering)

    private var weekEntryCount: Int {
        weekDays.reduce(0) { $0 + (dayCache[cal.startOfDay(for: $1)]?.count ?? 0) }
    }

    private var monthEntryCount: Int {
        monthDays.reduce(0) { $0 + (dayCache[cal.startOfDay(for: $1)]?.count ?? 0) }
    }

    private func periodSubtitle(_ count: Int) -> LocalizedStringKey {
        switch count {
        case 0: return "no entries"
        case 1: return "1 entry"
        default: return "\(count) entries"
        }
    }

    // MARK: - Cell color

    private func color(for date: Date?) -> Color {
        guard let date else { return Color(.systemFill).opacity(0.4) }
        guard let cached = dayCache[date] else { return Color(.systemFill) }
        let count = cached.count
        if let mood = cached.mood {
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
            if displayMode == .sentinel {
                rankXPRow
            }
            summaryRow

            Group {
                switch mode {
                case .week:  weekView
                case .month: monthView
                case .year:  yearView
                }
            }
            .animation(.easeInOut(duration: 0.2), value: mode)
        }
        .onChange(of: selectedDate) { _, newDate in
            if let newDate { viewDate = newDate }
        }
        .task(id: entries.map(\.encryptedMood).hashValue) {
            var dict: [Date: [Entry]] = [:]
            for e in entries {
                let day = cal.startOfDay(for: e.createdAt)
                dict[day, default: []].append(e)
            }
            var newCache: [Date: DayCacheEntry] = [:]
            for (day, dayEntries) in dict {
                newCache[day] = DayCacheEntry(count: dayEntries.count, mood: representativeMood(for: dayEntries))
            }
            dayCache = newCache

            let days = Set(dict.keys)
            var day = today
            if !days.contains(day) {
                guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                      days.contains(yesterday) else {
                    cachedStreak = 0
                    return
                }
                day = yesterday
            }
            var streak = 0
            while days.contains(day) {
                streak += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
            cachedStreak = streak
        }
    }

    // MARK: - Sentinel rank / XP row

    private var rankXPRow: some View {
        let xp = GamificationEngine.xp(for: entries)
        let level = GamificationEngine.level(forXP: xp)
        let rank = SentinelRank(level: level)
        let intoLevel = GamificationEngine.xpIntoLevel(xp)
        let forNext = GamificationEngine.xpForNextLevel()
        return HStack(spacing: 8) {
            Text("\(rank.rawValue.uppercased()) · LV\(level)")
                .font(MirrorTheme.mono(9.5, weight: .bold))
                .foregroundStyle(MirrorTheme.ember)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(MirrorTheme.ember.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MirrorTheme.inkBorder)
                    Capsule()
                        .fill(LinearGradient(colors: [MirrorTheme.violet, MirrorTheme.ember], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(intoLevel) / CGFloat(forNext))
                }
            }
            .frame(height: 5)
            Text("\(intoLevel)/\(forNext)")
                .font(MirrorTheme.mono(9.5))
                .foregroundStyle(MirrorTheme.textTertiary)
        }
        .padding(.horizontal, 16)
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
            modeMenu
            if cachedStreak > 0 {
                Spacer().frame(width: 12)
                statChip(
                    value: "\(cachedStreak)",
                    label: "Day streak",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private var modeMenu: some View {
        Menu {
            ForEach(HeatmapMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                } label: {
                    if mode == m {
                        Label(m.localizedName, systemImage: "checkmark")
                    } else {
                        Text(m.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Group {
                    if displayMode == .sentinel {
                        Text(mode.rawValue.uppercased())
                    } else {
                        Text(mode.localizedName)
                    }
                }
                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .semibold) : .system(size: 12, weight: .semibold))
                .kerning(displayMode == .sentinel ? 0.3 : 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.tertiarySystemFill)),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statChip(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: .bold) : .system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(displayMode == .sentinel ? MirrorTheme.mono(10.5, weight: .semibold) : .system(size: 12))
                .kerning(displayMode == .sentinel ? 0.2 : 0)
                .textCase(displayMode == .sentinel ? .uppercase : nil)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared nav header

    private func navHeader(
        title: String,
        subtitle: LocalizedStringKey? = nil,
        canGoBack: Bool,
        canGoForward: Bool,
        onBack: @escaping () -> Void,
        onForward: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canGoBack ? .secondary : Color(.systemFill))
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)

            Spacer()

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canGoForward ? .secondary : Color(.systemFill))
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Week View

    private var weekDays: [Date] {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: viewDate)
        comps.weekday = 1
        guard let sunday = cal.date(from: comps) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: sunday) }
    }

    private var canGoForwardWeek: Bool {
        var todayComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        todayComps.weekday = 1
        var viewComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: viewDate)
        viewComps.weekday = 1
        guard let thisSunday = cal.date(from: todayComps),
              let viewSunday = cal.date(from: viewComps) else { return false }
        return viewSunday < thisSunday
    }

    private var weekRangeTitle: String {
        let days = weekDays
        guard let first = days.first, let last = days.last else { return "" }
        let start = first.formatted(.dateTime.month(.abbreviated).day())
        let end = last.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    private var weekView: some View {
        VStack(spacing: 10) {
            navHeader(
                title: weekRangeTitle,
                subtitle: periodSubtitle(weekEntryCount),
                canGoBack: true,
                canGoForward: canGoForwardWeek,
                onBack: { viewDate = cal.date(byAdding: .weekOfYear, value: -1, to: viewDate) ?? viewDate },
                onForward: { viewDate = cal.date(byAdding: .weekOfYear, value: 1, to: viewDate) ?? viewDate }
            )

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    weekDayCell(for: day)
                }
            }
            .padding(.horizontal, 16)
        }
        // Swipe left/right to change week
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0, canGoForwardWeek {
                        viewDate = cal.date(byAdding: .weekOfYear, value: 1, to: viewDate) ?? viewDate
                        haptic()
                    } else if value.translation.width > 0 {
                        viewDate = cal.date(byAdding: .weekOfYear, value: -1, to: viewDate) ?? viewDate
                        haptic()
                    }
                }
        )
    }

    private func weekDayCell(for date: Date) -> some View {
        let startOfDay = cal.startOfDay(for: date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate ?? .distantPast)
        let isToday = cal.isDateInToday(date)
        let isFuture = date > today
        let isWeekend = cal.isDateInWeekend(date)
        let count = dayCache[startOfDay]?.count ?? 0

        return VStack(spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isFuture ? .quaternary : .tertiary)
                .opacity(isWeekend ? 0.55 : 1)

            RoundedRectangle(cornerRadius: displayMode == .sentinel ? 4 : 8, style: .continuous)
                .fill(displayMode == .sentinel ? MirrorTheme.inkMid : (isFuture ? Color(.systemFill).opacity(0.25) : color(for: startOfDay)))
                .overlay {
                    if displayMode == .sentinel, !isFuture, count > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(color(for: startOfDay), lineWidth: 1.5)
                    }
                }
                .frame(height: 46)
                .overlay {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.day()))
                            .font(displayMode == .sentinel ? MirrorTheme.mono(15, weight: isToday ? .bold : .semibold) : .system(size: 15, weight: isToday ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isFuture ? .quaternary : .primary)
                        if count > 0 {
                            Text("\(count)")
                                .font(displayMode == .sentinel ? MirrorTheme.mono(10, weight: .medium) : .system(size: 10, weight: .medium))
                                .foregroundStyle(displayMode == .sentinel ? color(for: startOfDay) : .white.opacity(0.8))
                        }
                    }
                }
                .overlay {
                    if isToday || isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected ? MirrorTheme.primary : Color.primary.opacity(0.4),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isFuture else { return }
                    haptic()
                    onDaySelected?(isSelected ? nil : startOfDay)
                }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Month View (week-separated strip)

    private var monthDays: [Date] {
        let comps = cal.dateComponents([.year, .month], from: viewDate)
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: firstOfMonth) }
    }

    private var monthWeeks: [MonthWeek] {
        var weeks: [MonthWeek] = []
        var currentWeek: [Date] = []

        for day in monthDays {
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1, !currentWeek.isEmpty {
                weeks.append(MonthWeek(id: currentWeek[0], days: currentWeek))
                currentWeek = []
            }
            currentWeek.append(day)
        }

        if !currentWeek.isEmpty {
            weeks.append(MonthWeek(id: currentWeek[0], days: currentWeek))
        }
        return weeks
    }

    private var canGoForwardMonth: Bool {
        let todayComps = cal.dateComponents([.year, .month], from: today)
        let viewComps = cal.dateComponents([.year, .month], from: viewDate)
        guard let todayMonth = cal.date(from: todayComps),
              let viewMonth = cal.date(from: viewComps) else { return false }
        return viewMonth < todayMonth
    }

    private var monthView: some View {
        VStack(spacing: 10) {
            navHeader(
                title: viewDate.formatted(.dateTime.month(.wide).year()),
                subtitle: periodSubtitle(monthEntryCount),
                canGoBack: true,
                canGoForward: canGoForwardMonth,
                onBack: { viewDate = cal.date(byAdding: .month, value: -1, to: viewDate) ?? viewDate },
                onForward: { viewDate = cal.date(byAdding: .month, value: 1, to: viewDate) ?? viewDate }
            )

            let weeks = monthWeeks
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(weeks) { week in
                            HStack(spacing: 6) {
                                ForEach(week.days, id: \.self) { day in
                                    monthStripCell(for: day)
                                        .id(day)
                                }
                            }

                            if week.id != weeks.last?.id {
                                weekSeparator(for: week)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .onAppear {
                    if let todayInMonth = monthDays.first(where: { cal.isDateInToday($0) }) {
                        proxy.scrollTo(todayInMonth, anchor: .center)
                    }
                }
                .onChange(of: viewDate) { _, _ in
                    if let todayInMonth = monthDays.first(where: { cal.isDateInToday($0) }) {
                        proxy.scrollTo(todayInMonth, anchor: .center)
                    } else if let first = monthDays.first {
                        proxy.scrollTo(first, anchor: .leading)
                    }
                }
            }
        }
    }

    private func weekEntryCount(for week: MonthWeek) -> Int {
        week.days.reduce(0) { total, day in
            total + (dayCache[cal.startOfDay(for: day)]?.count ?? 0)
        }
    }

    private func weekSeparator(for week: MonthWeek) -> some View {
        let count = weekEntryCount(for: week)

        return VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(count > 0 ? .secondary : .tertiary)
                .frame(minWidth: 14, minHeight: 12)
                .padding(.horizontal, 3)
                .background(Color(.tertiarySystemFill).opacity(count > 0 ? 1 : 0.55), in: Capsule())

            Rectangle()
                .fill(Color(.separator).opacity(0.35))
                .frame(width: 1, height: 44)
        }
        .padding(.horizontal, 7)
    }

    private func monthStripCell(for date: Date) -> some View {
        let startOfDay = cal.startOfDay(for: date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate ?? .distantPast)
        let isToday = cal.isDateInToday(date)
        let isFuture = date > today
        let isWeekend = cal.isDateInWeekend(date)
        let count = dayCache[startOfDay]?.count ?? 0

        return VStack(spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isFuture ? .quaternary : .tertiary)
                .opacity(isWeekend ? 0.55 : 1)

            RoundedRectangle(cornerRadius: displayMode == .sentinel ? 4 : 7, style: .continuous)
                .fill(displayMode == .sentinel ? MirrorTheme.inkMid : (isFuture ? Color(.systemFill).opacity(0.25) : color(for: startOfDay)))
                .overlay {
                    if displayMode == .sentinel, !isFuture, count > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(color(for: startOfDay), lineWidth: 1.5)
                    }
                }
                .frame(width: 36, height: 44)
                .overlay {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.day()))
                            .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: isToday ? .bold : .semibold) : .system(size: 13, weight: isToday ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isFuture ? .quaternary : .primary)
                        if count > 0 {
                            Text("\(count)")
                                .font(displayMode == .sentinel ? MirrorTheme.mono(9, weight: .medium) : .system(size: 9, weight: .medium))
                                .foregroundStyle(displayMode == .sentinel ? color(for: startOfDay) : .white.opacity(0.8))
                        }
                    }
                }
                .overlay {
                    if isToday || isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isSelected ? MirrorTheme.primary : Color.primary.opacity(0.4),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isFuture else { return }
                    haptic()
                    onDaySelected?(isSelected ? nil : startOfDay)
                }
        }
    }

    // MARK: - Year View

    private var yearView: some View {
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

    // MARK: - Day-of-week labels (Year view)

    private var dayLabels: some View {
        let symbols = cal.veryShortWeekdaySymbols // index 0 = Sunday, locale-aware
        return VStack(spacing: cellGap) {
            Color.clear.frame(height: 14)
            ForEach(0..<7, id: \.self) { i in
                Group {
                    switch i {
                    case 2: Text(symbols[1]) // Monday
                    case 4: Text(symbols[3]) // Wednesday
                    case 6: Text(symbols[5]) // Friday
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

    // MARK: - Week column (Year view)

    private func column(_ week: WeekColumn) -> some View {
        VStack(alignment: .leading, spacing: cellGap) {
            if let label = week.monthLabel {
                // Tap month label → jump to that month in Month mode
                Button {
                    if let monthDate = week.monthDate {
                        haptic()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewDate = monthDate
                            mode = .month
                        }
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(height: 14, alignment: .bottomLeading)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 14)
            }
            ForEach(0..<7, id: \.self) { i in
                cell(for: week.days[i])
            }
        }
        .id(week.id)
    }

    // MARK: - Individual day cell (Year view)

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
                haptic()
                onDaySelected?(isSelected ? nil : date)
            }
    }
}
