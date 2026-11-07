import Foundation
import Testing
@testable import mirror

/// Calendar edges for the journal day (4 AM boundary) and the chart runs: leap day, daylight-saving
/// changes, year end (UI checklist, 2026-11-07).
@Suite("Journal day calendar edges")
struct JournalDayCalendarEdgeTests {
    private func calendar(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }
    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func leapDayIsItsOwnJournalDay() {
        let cal = calendar("Europe/London")
        let lateOn28th = date(cal, 2028, 2, 29, 2)          // 2 AM on the 29th belongs to the 28th
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: lateOn28th, calendar: cal)) == 28)
        let noonOn29th = date(cal, 2028, 2, 29, 12)
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: noonOn29th, calendar: cal)) == 29)
        let earlyMarch1 = date(cal, 2028, 3, 1, 3)
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: earlyMarch1, calendar: cal)) == 29)
    }

    @Test func springForwardAndFallBackKeepTheFourAMBoundary() {
        let cal = calendar("America/Los_Angeles")
        // 2026-03-08: clocks jump 2 AM → 3 AM. 3:30 AM is still the night before; 4:30 AM is the 8th.
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: date(cal, 2026, 3, 8, 3, 30), calendar: cal)) == 7)
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: date(cal, 2026, 3, 8, 4, 30), calendar: cal)) == 8)
        let start = DateHelpers.journalDayStart(for: date(cal, 2026, 3, 8, 12), calendar: cal)
        #expect(cal.component(.hour, from: start) == 4)
        // 2026-11-01: clocks fall back 2 AM → 1 AM.
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: date(cal, 2026, 11, 1, 3), calendar: cal)) == 31)
        #expect(cal.component(.day, from: DateHelpers.journalDay(of: date(cal, 2026, 11, 1, 5), calendar: cal)) == 1)
    }

    @Test func yearEndStaysOneChartRun() {
        let cal = calendar("Asia/Kolkata")
        let means = [date(cal, 2026, 12, 31, 0), date(cal, 2027, 1, 1, 0)].map { MoodDayMean(day: $0, score: 3) }
        #expect(MoodChartSeries.runs(means, calendar: cal).map(\.run) == [0, 0])
    }
}
