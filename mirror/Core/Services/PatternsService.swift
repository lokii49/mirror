import Foundation

/// Patterns (Deep): which mood comes up most, grouped by day of the week, time of day, tag,
/// collection and entry length. Counted by the app from the person's own mood picks and
/// check-ins; no model writes anything. A group is shown only once it has `minimumReadings`
/// readings, and the wording is "what happened together", never "why".
enum PatternsService {
    static let minimumReadings = 3
    /// The top mood must come up at least this often: one reading out of four isn't a pattern
    /// (Mac harness, 2026-11-06: "Tuesday · Joyful · 1 of 4").
    static let minimumRepeats = 2

    /// One entry's part in a pattern: when, which mood, its tags, collection and length.
    struct Reading: Sendable {
        let date: Date
        let mood: String
        var tags: [String] = []
        var collectionID: UUID? = nil
        var words: Int = 0
    }

    struct Row: Identifiable, Equatable, Sendable {
        /// Stable key for the group (weekday number, band, tag, collection id …).
        let key: String
        let topMood: String
        /// Readings with `topMood`, out of `total` readings in the group.
        let count: Int
        let total: Int
        var id: String { key }
        var share: Double { total > 0 ? Double(count) / Double(total) : 0 }
    }

    enum Band: String, CaseIterable, Sendable { case morning, afternoon, evening, night }
    enum Length: String, CaseIterable, Sendable { case short, medium, long }

    struct Result: Equatable, Sendable {
        var weekdays: [Row] = []
        var timesOfDay: [Row] = []
        var tags: [Row] = []
        var collections: [Row] = []
        var lengths: [Row] = []
        /// Mood readings counted at all (days for weekdays, entries for the rest).
        var readingCount = 0

        var isEmpty: Bool { weekdays.isEmpty && timesOfDay.isEmpty && tags.isEmpty && collections.isEmpty && lengths.isEmpty }
    }

    /// 5–11 morning, 12–16 afternoon, 17–21 evening, 22–4 night.
    static func band(for date: Date, calendar: Calendar = .current) -> Band {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }

    /// Under 100 words short, under 300 medium, else long.
    static func length(for words: Int) -> Length {
        words < 100 ? .short : (words < 300 ? .medium : .long)
    }

    /// The group's most frequent mood, ties to the one read most recently (as `MoodLog.dominantMood`).
    static func row(key: String, readings: [(date: Date, mood: String)]) -> Row? {
        guard readings.count >= minimumReadings else { return nil }
        var counts: [String: Int] = [:]
        var latest: [String: Date] = [:]
        for reading in readings {
            counts[reading.mood, default: 0] += 1
            latest[reading.mood] = max(latest[reading.mood] ?? .distantPast, reading.date)
        }
        guard let top = counts.max(by: { a, b in
            a.value != b.value ? a.value < b.value : (latest[a.key] ?? .distantPast) < (latest[b.key] ?? .distantPast)
        }), top.value >= minimumRepeats else { return nil }
        return Row(key: key, topMood: top.key, count: top.value, total: readings.count)
    }

    /// - Parameters:
    ///   - entries: entry readings (kept-out collections already left out by the caller).
    ///   - days: one reading per day (`MoodLog.dailyMoods`: entries and check-ins, latest wins),
    ///     for the weekday rows.
    ///   - keptCollections: the collections to show, in order (none that are kept out).
    ///   - maxTags: the most-used tags only.
    static func compute(entries: [Reading], days: [(date: Date, mood: String)], keptCollections: [UUID],
                        maxTags: Int = 6, calendar: Calendar = .current) -> Result {
        var result = Result()
        result.readingCount = max(entries.count, days.count)

        let byWeekday = Dictionary(grouping: days) { calendar.component(.weekday, from: $0.date) }
        // The locale's first weekday first.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        result.weekdays = order.compactMap { day in byWeekday[day].flatMap { row(key: "\(day)", readings: $0) } }

        let byBand = Dictionary(grouping: entries) { band(for: $0.date, calendar: calendar) }
        result.timesOfDay = Band.allCases.compactMap { band in
            byBand[band].flatMap { row(key: band.rawValue, readings: $0.map { ($0.date, $0.mood) }) }
        }

        var byTag: [String: [(Date, String)]] = [:]
        for reading in entries {
            for tag in Set(reading.tags) { byTag[tag, default: []].append((reading.date, reading.mood)) }
        }
        result.tags = byTag
            .filter { $0.value.count >= minimumReadings }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(maxTags)
            .compactMap { row(key: $0.key, readings: $0.value.map { (date: $0.0, mood: $0.1) }) }

        let kept = Set(keptCollections)
        let byCollection = Dictionary(grouping: entries.filter { $0.collectionID.map(kept.contains) ?? false }) { $0.collectionID! }
        result.collections = keptCollections.compactMap { id in
            byCollection[id].flatMap { row(key: id.uuidString, readings: $0.map { ($0.date, $0.mood) }) }
        }

        let byLength = Dictionary(grouping: entries) { length(for: $0.words) }
        result.lengths = Length.allCases.compactMap { length in
            byLength[length].flatMap { row(key: length.rawValue, readings: $0.map { ($0.date, $0.mood) }) }
        }
        return result
    }
}
