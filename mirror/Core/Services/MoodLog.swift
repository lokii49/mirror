import Foundation

/// Where a mood reading came from.
enum MoodOrigin: String, Codable {
    /// A mood tagged on a journal entry (auto-detected or set by hand).
    case entry
    /// A standalone daily check-in — one tap, no writing.
    case checkIn
}

/// One mood reading at one moment.
struct MoodEvent: Identifiable {
    let id: UUID
    let date: Date
    let mood: String
    let origin: MoodOrigin

    /// 1–5 scale from `MirrorTheme.moodScore`; nil for an unrecognized label.
    var score: Double? { MirrorTheme.moodScore[mood] }
}

/// Single source of truth for "what was the user's mood, and when" — merges
/// journal-entry moods (`Entry.mood`) and standalone daily check-ins
/// (`MoodCheckIn`) under one set of rules, so every surface (Mood Timeline,
/// the weekly chart on Insights, the Mood Map widget, the low-mood alert)
/// gives the same answer.
///
/// Every function here is pure: the caller passes the already-loaded `entries`
/// and `checkIns`. `Entry.mood` decrypts on every access, so these MUST be
/// called off the view body — from `.task` / `.onChange` into `@State`, never
/// inline in `body`.
///
/// Deliberately NOT wired into the writing streak: a streak counts days the
/// user *wrote*, by definition — a mood tap isn't writing. That's a permanent
/// line, not a v1 shortcut.
enum MoodLog {

    /// All mood events, optionally clipped to `range` (nil = all time),
    /// sorted ascending by date (oldest first, newest last).
    static func events(
        in range: DateInterval? = nil,
        origins: Set<MoodOrigin> = [.entry, .checkIn],
        entries: [Entry],
        checkIns: [MoodCheckIn]
    ) -> [MoodEvent] {
        var out: [MoodEvent] = []

        if origins.contains(.entry) {
            for entry in entries {
                guard let mood = entry.mood, !mood.isEmpty else { continue }
                guard range?.contains(entry.createdAt) ?? true else { continue }
                out.append(MoodEvent(id: entry.id, date: entry.createdAt, mood: mood, origin: .entry))
            }
        }
        if origins.contains(.checkIn) {
            for checkIn in checkIns {
                let mood = checkIn.mood
                guard !mood.isEmpty else { continue }
                guard range?.contains(checkIn.createdAt) ?? true else { continue }
                out.append(MoodEvent(id: checkIn.id, date: checkIn.createdAt, mood: mood, origin: .checkIn))
            }
        }

        return out.sorted { $0.date < $1.date }
    }

    /// One representative mood per calendar day: the latest event of that day
    /// wins — whichever the user logged later, an entry mood or a check-in.
    static func dailyMoods(
        in range: DateInterval? = nil,
        origins: Set<MoodOrigin> = [.entry, .checkIn],
        entries: [Entry],
        checkIns: [MoodCheckIn],
        calendar: Calendar = .current
    ) -> [Date: MoodEvent] {
        var byDay: [Date: MoodEvent] = [:]
        for event in events(in: range, origins: origins, entries: entries, checkIns: checkIns) {
            let day = calendar.startOfDay(for: event.date)
            if let existing = byDay[day], existing.date >= event.date { continue }
            byDay[day] = event
        }
        return byDay
    }

    /// Length of the unbroken run of negative-mood days ending today — or ending
    /// yesterday, if today has no reading yet.
    ///
    /// A day with **no** mood event breaks the run: three negative readings
    /// spread across a two-week gap are not "3 consecutive". A day whose latest
    /// reading is non-negative also breaks it. Returns 0 when neither today nor
    /// yesterday has a reading (no active run to speak of).
    static func consecutiveNegativeDays(
        entries: [Entry],
        checkIns: [MoodCheckIn],
        negativeMoods: Set<String> = MirrorTheme.negativeMoods,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int {
        let byDay = dailyMoods(entries: entries, checkIns: checkIns, calendar: calendar)
        guard !byDay.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        let anchor: Date
        if byDay[today] != nil {
            anchor = today
        } else if byDay[yesterday] != nil {
            anchor = yesterday
        } else {
            return 0
        }

        var count = 0
        var cursor = anchor
        while let event = byDay[cursor], negativeMoods.contains(event.mood) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }
}
