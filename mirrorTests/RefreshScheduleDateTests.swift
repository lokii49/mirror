import Testing
import Foundation
@testable import mirror

/// Earliest dates for the weekly digest and monthly report background refreshes (backlog A4).
/// Checked under both first-weekday settings: locale-week math broke digests once (2026-09-27).
@Suite("Refresh schedule dates")
struct RefreshScheduleDateTests {
    private static func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        cal.firstWeekday = firstWeekday
        return cal
    }

    private static func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // 2026-10-11 is a Sunday.
    @Test(arguments: [1, 2])
    func midweekGoesToComingSunday(firstWeekday: Int) {
        let cal = Self.calendar(firstWeekday: firstWeekday)
        let wednesday = Self.date(cal, 2026, 10, 7)
        #expect(DateHelpers.nextSunday7AM(after: wednesday, calendar: cal) == Self.date(cal, 2026, 10, 11, 7))
    }

    @Test(arguments: [1, 2])
    func mondayGoesToSundaySixDaysOn(firstWeekday: Int) {
        let cal = Self.calendar(firstWeekday: firstWeekday)
        let monday = Self.date(cal, 2026, 10, 12, 9)
        #expect(DateHelpers.nextSunday7AM(after: monday, calendar: cal) == Self.date(cal, 2026, 10, 18, 7))
    }

    @Test(arguments: [1, 2])
    func sundayBeforeSevenIsToday(firstWeekday: Int) {
        let cal = Self.calendar(firstWeekday: firstWeekday)
        let early = Self.date(cal, 2026, 10, 11, 6, 30)
        #expect(DateHelpers.nextSunday7AM(after: early, calendar: cal) == Self.date(cal, 2026, 10, 11, 7))
    }

    @Test(arguments: [1, 2])
    func sundayAfterSevenIsNextWeek(firstWeekday: Int) {
        let cal = Self.calendar(firstWeekday: firstWeekday)
        let late = Self.date(cal, 2026, 10, 11, 8)
        #expect(DateHelpers.nextSunday7AM(after: late, calendar: cal) == Self.date(cal, 2026, 10, 18, 7))
    }

    @Test func yearBoundary() {
        let cal = Self.calendar(firstWeekday: 2)
        // Wednesday 2026-12-30 → Sunday 2027-01-03.
        #expect(DateHelpers.nextSunday7AM(after: Self.date(cal, 2026, 12, 30), calendar: cal) == Self.date(cal, 2027, 1, 3, 7))
    }

    @Test func monthlyIsThisMonthsLastDay() {
        let cal = Self.calendar(firstWeekday: 2)
        #expect(DateHelpers.lastDayOfMonth9PM(after: Self.date(cal, 2026, 10, 10), calendar: cal) == Self.date(cal, 2026, 10, 31, 21))
        #expect(DateHelpers.lastDayOfMonth9PM(after: Self.date(cal, 2026, 2, 3), calendar: cal) == Self.date(cal, 2026, 2, 28, 21))
    }

    @Test func monthlyAfterLastEveningIsNextMonth() {
        let cal = Self.calendar(firstWeekday: 2)
        #expect(DateHelpers.lastDayOfMonth9PM(after: Self.date(cal, 2026, 10, 31, 22), calendar: cal) == Self.date(cal, 2026, 11, 30, 21))
        #expect(DateHelpers.lastDayOfMonth9PM(after: Self.date(cal, 2026, 12, 31, 21, 30), calendar: cal) == Self.date(cal, 2027, 1, 31, 21))
    }
}
