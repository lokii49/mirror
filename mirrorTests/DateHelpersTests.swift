import Testing
import Foundation
@testable import mirror

// Monthly report generation gates on this (writing-roadmap.md-adjacent fix, 2026-09-17): a report
// about "this month" shouldn't generate until the month is nearly over, regardless of entry
// count. Pure date arithmetic, no LLM/device dependency — worth pinning down exactly.
@Suite("DateHelpers.isInLastWeekOfMonth")
struct DateHelpersTests {

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func dayBeforeWindow_31DayMonth_isFalse() {
        #expect(!DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 1, day: 24)))
    }

    @Test func firstDayOfWindow_31DayMonth_isTrue() {
        #expect(DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 1, day: 25)))
    }

    @Test func lastDayOfMonth_31Days_isTrue() {
        #expect(DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 1, day: 31)))
    }

    @Test func firstDayOfWindow_30DayMonth_isTrue() {
        #expect(DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 4, day: 24)))
    }

    @Test func dayBeforeWindow_30DayMonth_isFalse() {
        #expect(!DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 4, day: 23)))
    }

    @Test func firstDayOfWindow_28DayFebruary_isTrue() {
        // 2026 is not a leap year.
        #expect(DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 2, day: 22)))
    }

    @Test func dayBeforeWindow_28DayFebruary_isFalse() {
        #expect(!DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 2, day: 21)))
    }

    @Test func firstDayOfWindow_29DayLeapFebruary_isTrue() {
        // 2028 is a leap year.
        #expect(DateHelpers.isInLastWeekOfMonth(date(year: 2028, month: 2, day: 23)))
    }

    @Test func midMonth_isFalse() {
        #expect(!DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 6, day: 15)))
    }

    @Test func firstOfMonth_isFalse() {
        #expect(!DateHelpers.isInLastWeekOfMonth(date(year: 2026, month: 6, day: 1)))
    }
}

// Weekly digest generation gates on this — mirrorApp's own Sunday-only background pre-gen rule,
// shared with InsightViewModel.loadWeeklyDigest's on-demand path via this one predicate instead
// of two independently-drifting inline weekday checks.
@Suite("DateHelpers.isSunday")
struct DateHelpersIsSundayTests {

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func sunday_isTrue() {
        // September 13, 2026 is a Sunday.
        #expect(DateHelpers.isSunday(date(year: 2026, month: 9, day: 13)))
    }

    @Test func monday_isFalse() {
        #expect(!DateHelpers.isSunday(date(year: 2026, month: 9, day: 14)))
    }

    @Test func saturday_isFalse() {
        #expect(!DateHelpers.isSunday(date(year: 2026, month: 9, day: 12)))
    }
}
