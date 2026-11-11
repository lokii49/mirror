import Foundation

/// Year (or month) in Review (Deep): counts from the journal itself. Writing numbers include every
/// entry (kept-out collections count as writing); moods and tags come only from what reflections
/// may read. Nothing here is model-written.
enum ReviewStatsService {
    struct Writing: Sendable {
        let date: Date
        let words: Int
    }

    struct Stats: Equatable, Sendable {
        var entries = 0
        var words = 0
        var activeDays = 0
        var longestStreak = 0
        var firstEntry: Date?
        var lastEntry: Date?
        /// 1...7 (Calendar weekday) with the most entries; nil with none.
        var busiestWeekday: Int?
        /// 1...12; year view only.
        var busiestMonth: Int?
        /// Mood → number of days it was the day's mood, most first (at most 3).
        var topMoods: [(mood: String, days: Int)] = []
        /// Tag → entries, most first (at most 5).
        var topTags: [(tag: String, entries: Int)] = []

        var isEmpty: Bool { entries == 0 }

        static func == (a: Stats, b: Stats) -> Bool {
            a.entries == b.entries && a.words == b.words && a.activeDays == b.activeDays && a.longestStreak == b.longestStreak
                && a.firstEntry == b.firstEntry && a.lastEntry == b.lastEntry && a.busiestWeekday == b.busiestWeekday
                && a.busiestMonth == b.busiestMonth && a.topMoods.map(\.mood) == b.topMoods.map(\.mood)
                && a.topMoods.map(\.days) == b.topMoods.map(\.days) && a.topTags.map(\.tag) == b.topTags.map(\.tag)
                && a.topTags.map(\.entries) == b.topTags.map(\.entries)
        }
    }

    /// - Parameters:
    ///   - writing: every entry in the period (including kept-out ones).
    ///   - dayMoods: one mood per day in the period (`MoodLog.dailyMoods` over what insights read).
    ///   - tags: each readable entry's tags in the period (kept-out left out).
    ///   - isYear: adds the busiest month.
    static func compute(writing: [Writing], dayMoods: [String], tags: [[String]], isYear: Bool,
                        calendar: Calendar = .current) -> Stats {
        var stats = Stats()
        guard !writing.isEmpty else { return stats }
        stats.entries = writing.count
        stats.words = writing.reduce(0) { $0 + max(0, $1.words) }
        let sorted = writing.map(\.date).sorted()
        stats.firstEntry = sorted.first
        stats.lastEntry = sorted.last

        let days = Set(sorted.map { calendar.startOfDay(for: $0) }).sorted()
        stats.activeDays = days.count
        var longest = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        stats.longestStreak = longest

        stats.busiestWeekday = mostCommon(sorted.map { calendar.component(.weekday, from: $0) })
        if isYear { stats.busiestMonth = mostCommon(sorted.map { calendar.component(.month, from: $0) }) }

        var moodCounts: [String: Int] = [:]
        for mood in dayMoods where !mood.isEmpty { moodCounts[mood, default: 0] += 1 }
        stats.topMoods = moodCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map { (mood: $0.key, days: $0.value) }

        var tagCounts: [String: Int] = [:]
        for entryTags in tags { for tag in Set(entryTags) { tagCounts[tag, default: 0] += 1 } }
        stats.topTags = tagCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(5).map { (tag: $0.key, entries: $0.value) }
        return stats
    }

    /// The most frequent value; a tie goes to the smaller value so the answer is stable.
    static func mostCommon(_ values: [Int]) -> Int? {
        var counts: [Int: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Jan 1–7 local: the year view is offered for the year that just ended.
    static func isReviewWeek(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == 1 && (parts.day ?? 99) <= 7
    }
}
