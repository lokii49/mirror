import Testing
import Foundation
@testable import mirror

// Pins how the Gemma grounded nudge picks its source: only the newest day's entries are
// quotable. Before 2026-09-28 that meant an entry written after today's reflection, followed by
// an entry the next morning before the next reflection, was never quoted. A second reflection on
// the day of writing (InsightService.allowsAnotherReflectionToday, DailyReflectionTimingTests)
// now reflects that entry the same day, so the source rule itself stays as it is.
struct DailyNudgeSourceDayTests {

    @Test func onlyTheNewestDaysEntriesAreQuotable_soAnEarlierUnreflectedDayIsSkipped() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let evening = Entry(text: "Went to the concert with Maya tonight and loved every single minute of it.", mood: "Content")
        evening.createdAt = startOfToday.addingTimeInterval(-3 * 3_600)
        let morning = Entry(text: "Dentist appointment at nine, then a long day of meetings ahead of me.", mood: "Content")
        morning.createdAt = startOfToday.addingTimeInterval(60)

        let (recent, background) = InsightService.dailyNudgeContext(from: [evening, morning], asOf: startOfToday.addingTimeInterval(2 * 3_600))
        #expect(recent.count == 2)
        let plan = InsightService.groundedNudgePlan(recent: recent, background: background, recentNudges: [])
        #expect(plan.quoteOptions.contains { $0.contains("Dentist appointment") })
        #expect(!plan.quoteOptions.contains { $0.contains("concert with Maya") })
    }
}
