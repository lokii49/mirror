import Testing
import Foundation
@testable import mirror

// Documents how the Gemma grounded nudge picks its source (checked 2026-09-28 for the "is an
// evening entry ever missed?" question): only the newest day's entries are quotable. So an
// entry written after today's reflection, followed by an entry the next morning before the next
// reflection is generated, never gets quoted. Open item in .claude/3.0.6-roadmap.md; update this
// test if the source rule changes.
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
