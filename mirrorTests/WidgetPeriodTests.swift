import Testing
import Foundation
@testable import mirror

/// Backlog A16: between digests and before the month-end report, widgets show the previous one,
/// labelled; anything older shows the placeholder.
@Suite("Widget stored period")
struct WidgetPeriodTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func classifiesCurrentPreviousAndOlder() {
        #expect(WidgetShared.storedPeriod("2026-W41", current: "2026-W41", previous: "2026-W40") == .current)
        #expect(WidgetShared.storedPeriod("2026-W40", current: "2026-W41", previous: "2026-W40") == .previous)
        #expect(WidgetShared.storedPeriod("2026-W39", current: "2026-W41", previous: "2026-W40") == .older)
        #expect(WidgetShared.storedPeriod(nil, current: "2026-W41", previous: "2026-W40") == .older)
    }

    @Test func mondayShowsLastWeeksDigest() {
        // Monday 2026-10-12 is in W42; Sunday's digest (W41) is "last week".
        let monday = date(2026, 10, 12)
        #expect(WidgetShared.previousDigestWeek(before: monday) == DateHelpers.digestWeekIdentifier(for: date(2026, 10, 11)))
    }

    @Test func isoYearBoundary() {
        // Monday 2027-01-04 starts 2027-W01; the week before is 2026-W53.
        #expect(WidgetShared.previousDigestWeek(before: date(2027, 1, 4)) == "2026-W53")
    }

    @Test func previousMonthAcrossTheYear() {
        #expect(WidgetShared.previousMonth(before: date(2027, 1, 15)) == DateHelpers.monthIdentifier(for: date(2026, 12, 15)))
        #expect(WidgetShared.previousMonth(before: date(2026, 3, 31)) == DateHelpers.monthIdentifier(for: date(2026, 2, 15)))
    }
}
