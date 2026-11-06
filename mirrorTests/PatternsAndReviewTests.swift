import Foundation
import Testing
@testable import mirror

/// Patterns and Year in Review: counts only, from synthetic readings.
@Suite("Patterns and review counts")
struct PatternsAndReviewTests {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday first
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: Patterns

    @Test func groupsBelowThreeReadingsAreLeftOut() {
        #expect(PatternsService.row(key: "x", readings: [(date(2026, 1, 1), "Calm"), (date(2026, 1, 2), "Calm")]) == nil)
        let row = PatternsService.row(key: "x", readings: [(date(2026, 1, 1), "Sad"), (date(2026, 1, 2), "Joyful"), (date(2026, 1, 3), "Joyful")])
        #expect(row?.topMood == "Joyful")
        #expect(row?.count == 2)
        #expect(row?.total == 3)
    }

    @Test func aMoodSeenOnceIsNotAPattern() {
        #expect(PatternsService.row(key: "x", readings: [(date(2026, 1, 1), "Sad"), (date(2026, 1, 2), "Joyful"), (date(2026, 1, 3), "Calm")]) == nil)
    }

    @Test func aTieGoesToTheMoodReadMostRecently() {
        let row = PatternsService.row(key: "x", readings: [
            (date(2026, 1, 1), "Sad"), (date(2026, 1, 2), "Joyful"), (date(2026, 1, 3), "Sad"), (date(2026, 1, 4), "Joyful"),
        ])
        #expect(row?.topMood == "Joyful")
    }

    @Test func weekdaysFollowTheLocaleWeekAndDayReadings() {
        // Mondays: 2026-01-05, 12, 19 (Grateful x2, Sad); Sundays only twice (left out).
        let days: [(date: Date, mood: String)] = [
            (date(2026, 1, 5), "Grateful"), (date(2026, 1, 12), "Grateful"), (date(2026, 1, 19), "Sad"),
            (date(2026, 1, 4), "Calm"), (date(2026, 1, 11), "Calm"),
        ]
        let result = PatternsService.compute(entries: [], days: days, keptCollections: [], calendar: calendar)
        #expect(result.weekdays.map(\.key) == ["2"])
        #expect(result.weekdays.first?.topMood == "Grateful")
    }

    @Test func timeOfDayBandsAndLengths() {
        #expect(PatternsService.band(for: date(2026, 1, 1, 5), calendar: calendar) == .morning)
        #expect(PatternsService.band(for: date(2026, 1, 1, 12), calendar: calendar) == .afternoon)
        #expect(PatternsService.band(for: date(2026, 1, 1, 21), calendar: calendar) == .evening)
        #expect(PatternsService.band(for: date(2026, 1, 1, 23), calendar: calendar) == .night)
        #expect(PatternsService.band(for: date(2026, 1, 1, 4), calendar: calendar) == .night)
        #expect(PatternsService.length(for: 99) == .short)
        #expect(PatternsService.length(for: 100) == .medium)
        #expect(PatternsService.length(for: 300) == .long)
    }

    @Test func tagsAndOnlyKeptCollectionsAreCounted() {
        let work = UUID(), scratch = UUID()
        let entries = (1...4).map { PatternsService.Reading(date: date(2026, 2, $0), mood: "Drained", tags: ["work", "work"], collectionID: work, words: 50) }
            + (1...3).map { PatternsService.Reading(date: date(2026, 2, 10 + $0), mood: "Joyful", tags: [], collectionID: scratch, words: 400) }
        let result = PatternsService.compute(entries: entries, days: [], keptCollections: [work], calendar: calendar)
        #expect(result.tags.map(\.key) == ["work"])
        #expect(result.tags.first?.total == 4, "a tag repeated in one entry counts once")
        #expect(result.collections.map(\.key) == [work.uuidString])
        #expect(result.lengths.map(\.key) == ["short", "long"])
    }

    // MARK: Review

    @Test func reviewCountsWritingStreaksAndBusiestDays() {
        let writing: [ReviewStatsService.Writing] = [
            .init(date: date(2026, 3, 2), words: 100), .init(date: date(2026, 3, 3), words: 50),
            .init(date: date(2026, 3, 4), words: 25), .init(date: date(2026, 3, 4, 20), words: 25),
            .init(date: date(2026, 5, 1), words: 10),
        ]
        let stats = ReviewStatsService.compute(writing: writing, dayMoods: ["Calm", "Calm", "Sad"],
                                               tags: [["a"], ["a", "b"], []], isYear: true, calendar: calendar)
        #expect(stats.entries == 5)
        #expect(stats.words == 210)
        #expect(stats.activeDays == 4)
        #expect(stats.longestStreak == 3)
        #expect(stats.busiestMonth == 3)
        #expect(stats.busiestWeekday == calendar.component(.weekday, from: date(2026, 3, 4)))
        #expect(stats.topMoods.map(\.mood) == ["Calm", "Sad"])
        #expect(stats.topTags.map(\.tag) == ["a", "b"])
        #expect(stats.firstEntry == date(2026, 3, 2))
        #expect(stats.lastEntry == date(2026, 5, 1))
    }

    @Test func emptyPeriodAndMonthView() {
        #expect(ReviewStatsService.compute(writing: [], dayMoods: [], tags: [], isYear: true, calendar: calendar).isEmpty)
        let month = ReviewStatsService.compute(writing: [.init(date: date(2026, 3, 2), words: 5)], dayMoods: [], tags: [],
                                               isYear: false, calendar: calendar)
        #expect(month.busiestMonth == nil)
        #expect(month.longestStreak == 1)
    }

    @Test func reviewWeekIsTheFirstSevenDaysOfJanuary() {
        #expect(ReviewStatsService.isReviewWeek(date(2027, 1, 1), calendar: calendar))
        #expect(ReviewStatsService.isReviewWeek(date(2027, 1, 7), calendar: calendar))
        #expect(!ReviewStatsService.isReviewWeek(date(2027, 1, 8), calendar: calendar))
        #expect(!ReviewStatsService.isReviewWeek(date(2026, 12, 31), calendar: calendar))
    }
}
