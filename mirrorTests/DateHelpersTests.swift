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

// The digest runs only on Sunday. With the locale week, Sunday-first regions (US, India) put that
// Sunday in a new, empty week, so the 3-entry gate never passed and digests silently stopped
// (2026-09-27 device report: 6 entries Mon–Sat, no digest on Sunday).
@Suite("DateHelpers.digestWeekIdentifier")
struct DateHelpersDigestWeekTests {

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func sundayBelongsToTheWeekThatStartedOnMonday() {
        let sunday = DateHelpers.digestWeekIdentifier(for: noon(2026, 9, 27))
        for day in 21...26 {
            #expect(DateHelpers.digestWeekIdentifier(for: noon(2026, 9, day)) == sunday, "Sep \(day)")
        }
        #expect(DateHelpers.digestWeekIdentifier(for: noon(2026, 9, 28)) != sunday)
        #expect(DateHelpers.digestWeekIdentifier(for: noon(2026, 9, 20)) != sunday)
    }

    @Test func lateSundayNightStaysInTheSameWeek() {
        let lateSunday = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 23, minute: 50))!
        #expect(DateHelpers.digestWeekIdentifier(for: lateSunday) == DateHelpers.digestWeekIdentifier(for: noon(2026, 9, 21)))
    }

    @Test func yearBoundaryUsesISOWeekYear() {
        // Thu 31 Dec 2026 and Sun 3 Jan 2027 are both in ISO week 2026-W53.
        #expect(DateHelpers.digestWeekIdentifier(for: noon(2026, 12, 31)) == "2026-W53")
        #expect(DateHelpers.digestWeekIdentifier(for: noon(2027, 1, 3)) == "2026-W53")
        #expect(DateHelpers.digestWeekIdentifier(for: noon(2027, 1, 4)) == "2027-W01")
    }
}
