import Testing
import SwiftData
import Foundation
@testable import mirror

/// Mood alerts count the latest days *with a reading*, and the nightly task's earliest start
/// (backlog E test gaps). Synthetic moods only, no journal text.
@Suite("Mood alert days and nightly schedule")
@MainActor
struct MoodAlertAndScheduleTests {
    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }
    private static let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 20))!

    private func entry(_ mood: String, daysAgo: Int, hour: Int = 12) -> Entry {
        let e = Entry(text: "Synthetic.", mood: mood)
        let day = Self.cal.date(byAdding: .day, value: -daysAgo, to: Self.now)!
        e.createdAt = Self.cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return e
    }

    private func count(_ entries: [Entry], checkIns: [MoodCheckIn] = []) -> Int {
        MoodLog.recentNegativeMoodDays(entries: entries, checkIns: checkIns, calendar: Self.cal, now: Self.now)
    }

    @Test func threeNegativeDaysWithGapsCountThree() {
        // Days with no reading are skipped: 0, 2 and 5 days ago are the three latest readings.
        #expect(count([entry("Anxious", daysAgo: 0), entry("Sad", daysAgo: 2), entry("Drained", daysAgo: 5)]) == 3)
    }

    @Test func aPositiveDayBreaksTheRun() {
        #expect(count([entry("Anxious", daysAgo: 0), entry("Content", daysAgo: 1), entry("Sad", daysAgo: 2)]) == 1)
    }

    @Test func theDaysLatestReadingWins() {
        // Same day: a calmer reading later in the day replaces the earlier negative one.
        #expect(count([entry("Anxious", daysAgo: 0, hour: 9), entry("Content", daysAgo: 0, hour: 18), entry("Sad", daysAgo: 1)]) == 0)
    }

    @Test func noRecentReadingMeansNoAlert() {
        // Newest reading 3 days ago: outside the 2-day anchor.
        #expect(count([entry("Anxious", daysAgo: 3), entry("Sad", daysAgo: 4), entry("Drained", daysAgo: 5)]) == 0)
    }

    @Test func readingsOlderThanTheLookbackDontCount() {
        #expect(count([entry("Anxious", daysAgo: 0), entry("Sad", daysAgo: 1), entry("Drained", daysAgo: 13)]) == 2)
    }

    @Test func nightlyRunIsTodaysThreeAMOrTomorrows() {
        let early = Self.cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 1))!
        let threeToday = Self.cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 3))!
        let threeTomorrow = Self.cal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 3))!
        #expect(mirrorApp.next3AM(after: early, calendar: Self.cal) == threeToday)
        #expect(mirrorApp.next3AM(after: Self.now, calendar: Self.cal) == threeTomorrow)
        #expect(mirrorApp.next3AM(after: threeToday, calendar: Self.cal) == threeTomorrow)
    }
}
