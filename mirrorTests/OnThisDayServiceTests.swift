import Testing
import Foundation
@testable import mirror

// OnThisDayService is pure date-component matching over existing Entry.createdAt — no model, no
// network, no fabrication risk (unlike every InsightService generator). These tests run in
// milliseconds with no simulator/model dependency.
@Suite("OnThisDayService")
struct OnThisDayServiceTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private func entry(_ text: String, createdAt: Date) -> Entry {
        let e = Entry(text: text)
        e.createdAt = createdAt
        return e
    }

    @Test func matches_sameMonthDayPastYear_included() {
        let today = date(2026, 9, 12)
        let pastYearSameDay = entry("A year ago today.", createdAt: date(2025, 9, 12))
        let result = OnThisDayService.matches(in: [pastYearSameDay], today: today)
        #expect(result.count == 1)
    }

    @Test func matches_sameYear_excluded() {
        // Written earlier this same year on the same month/day is impossible in practice
        // (that would BE today), but guards the year-equality check directly regardless.
        let today = date(2026, 9, 12)
        let thisYear = entry("Today itself.", createdAt: date(2026, 9, 12))
        let result = OnThisDayService.matches(in: [thisYear], today: today)
        #expect(result.isEmpty)
    }

    @Test func matches_differentMonthOrDay_excluded() {
        let today = date(2026, 9, 12)
        let differentDay = entry("Wrong day.", createdAt: date(2025, 9, 11))
        let differentMonth = entry("Wrong month.", createdAt: date(2025, 8, 12))
        let result = OnThisDayService.matches(in: [differentDay, differentMonth], today: today)
        #expect(result.isEmpty)
    }

    @Test func matches_multipleYears_sortedNewestFirst() {
        let today = date(2026, 9, 12)
        let threeYearsAgo = entry("Three years ago.", createdAt: date(2023, 9, 12))
        let oneYearAgo = entry("One year ago.", createdAt: date(2025, 9, 12))
        let twoYearsAgo = entry("Two years ago.", createdAt: date(2024, 9, 12))
        let result = OnThisDayService.matches(in: [threeYearsAgo, oneYearAgo, twoYearsAgo], today: today)
        #expect(result.map(\.createdAt) == [oneYearAgo, twoYearsAgo, threeYearsAgo].map(\.createdAt))
    }

    @Test func matches_noEntries_returnsEmpty() {
        #expect(OnThisDayService.matches(in: [], today: date(2026, 9, 12)).isEmpty)
    }

    @Test func matches_mixedEntries_onlyReturnsQualifying() {
        let today = date(2026, 9, 12)
        let qualifies = entry("Matches.", createdAt: date(2024, 9, 12))
        let doesNotQualify = entry("Doesn't match.", createdAt: date(2024, 5, 3))
        let result = OnThisDayService.matches(in: [qualifies, doesNotQualify], today: today)
        #expect(result.count == 1)
        #expect(result.first?.createdAt == qualifies.createdAt)
    }
}
