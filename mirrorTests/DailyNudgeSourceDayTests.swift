import Testing
import Foundation
@testable import mirror

// Pins how the Gemma grounded nudge picks its source: only the newest journal day's entries are
// quotable. Before 2026-09-28 that meant an entry written after today's reflection, followed by
// an entry the next morning before the next reflection, was never quoted. A second reflection on
// the day of writing (InsightService.allowsAnotherReflectionToday, DailyReflectionTimingTests)
// now reflects that entry the same day, so the source rule itself stays as it is.
//
// Since 3.1.7 the day boundary is 4 AM (DateHelpers.journalDay): writing just after midnight
// belongs to the night before.
struct DailyNudgeSourceDayTests {

    @Test func onlyTheNewestDaysEntriesAreQuotable_soAnEarlierUnreflectedDayIsSkipped() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let evening = Entry(text: "Went to the concert with Maya tonight and loved every single minute of it.", mood: "Content")
        evening.createdAt = startOfToday.addingTimeInterval(-3 * 3_600)
        let morning = Entry(text: "Dentist appointment at nine, then a long day of meetings ahead of me.", mood: "Content")
        morning.createdAt = startOfToday.addingTimeInterval(5 * 3_600)

        let (recent, background) = InsightService.dailyNudgeContext(from: [evening, morning], asOf: startOfToday.addingTimeInterval(6 * 3_600))
        #expect(recent.count == 2)
        let plan = InsightService.groundedNudgePlan(recent: recent, background: background, recentNudges: [])
        #expect(plan.quoteOptions.contains { $0.contains("Dentist appointment") })
        #expect(!plan.quoteOptions.contains { $0.contains("concert with Maya") })
    }

    @Test func journalDay_startsAtFourAM() {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: midnight)!
        #expect(DateHelpers.journalDay(of: midnight.addingTimeInterval(30 * 60)) == yesterday)
        #expect(DateHelpers.journalDay(of: midnight.addingTimeInterval(4 * 3_600 - 1)) == yesterday)
        #expect(DateHelpers.journalDay(of: midnight.addingTimeInterval(4 * 3_600)) == midnight)
        #expect(DateHelpers.journalDay(of: midnight.addingTimeInterval(23 * 3_600)) == midnight)
        #expect(DateHelpers.journalDayStart(for: midnight.addingTimeInterval(2 * 3_600)) == yesterday.addingTimeInterval(4 * 3_600))
        #expect(DateHelpers.journalDayStart(for: midnight.addingTimeInterval(9 * 3_600)) == midnight.addingTimeInterval(4 * 3_600))
    }

    /// 11 PM and 12:30 AM are one night's writing: both are quoted, and the reflection is about
    /// the evening's day, not the new calendar day.
    @Test func entryJustAfterMidnight_belongsToTheNightBefore() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let lateEvening = Entry(text: "Went to the concert with Maya tonight and loved every single minute of it.", mood: "Content")
        lateEvening.createdAt = startOfToday.addingTimeInterval(-3_600)
        let afterMidnight = Entry(text: "Still awake after the concert, my ears are ringing and I am happy.", mood: "Content")
        afterMidnight.createdAt = startOfToday.addingTimeInterval(30 * 60)

        let (recent, background) = InsightService.dailyNudgeContext(from: [lateEvening, afterMidnight], asOf: startOfToday.addingTimeInterval(9 * 3_600))
        #expect(InsightService.groundedNudgeSourceEntries(recent).count == 2)
        let plan = InsightService.groundedNudgePlan(recent: recent, background: background, recentNudges: [])
        #expect(plan.quoteOptions.contains { $0.contains("concert with Maya") })
        #expect(plan.quoteOptions.contains { $0.contains("ears are ringing") })

        let reflection = Insight(type: .dailyNudge, content: "real", periodIdentifier: DateHelpers.dayIdentifier(for: startOfToday))
        reflection.generatedAt = startOfToday.addingTimeInterval(9 * 3_600)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: startOfToday)!
        #expect(InsightService.reflectedDay(of: reflection, entriesNewestFirst: [afterMidnight, lateEvening]) == yesterday)
    }

    /// The widget's mood follows the same day: at 9 AM a 12:30 AM entry's mood is last night's.
    @Test func widgetMood_comesFromTodaysJournalDay() {
        let midnight = Calendar.current.startOfDay(for: Date())
        let afterMidnight = Entry(text: "Still awake after the concert, my ears are ringing.", mood: "Anxious")
        afterMidnight.createdAt = midnight.addingTimeInterval(30 * 60)
        let morning = Entry(text: "Coffee on the balcony before work, slow and quiet.", mood: "Calm")
        morning.createdAt = midnight.addingTimeInterval(7 * 3_600)
        let nineAM = midnight.addingTimeInterval(9 * 3_600)
        #expect(mirrorApp.journalDayMood(entriesNewestFirst: [afterMidnight], now: nineAM) == nil)
        #expect(mirrorApp.journalDayMood(entriesNewestFirst: [morning, afterMidnight], now: nineAM) == "Calm")
        #expect(mirrorApp.journalDayMood(entriesNewestFirst: [afterMidnight], now: midnight.addingTimeInterval(3_600)) == "Anxious")
    }

    /// Writing from the previous journal day is not "Today's journal entry" in the prompt.
    @Test func promptHeading_callsLastNightsEntryMostRecent() {
        let lastNight = Entry(text: "Still awake after the concert, my ears are ringing and I am happy.", mood: "Content")
        lastNight.createdAt = DateHelpers.journalDayStart(for: Date()).addingTimeInterval(-30 * 60)
        #expect(InsightService.groundedNudgeUserMessage([lastNight]).hasPrefix("Most recent journal entry:"))

        let today = Entry(text: "Dentist appointment at nine, then a long day of meetings ahead of me.", mood: "Content")
        today.createdAt = DateHelpers.journalDayStart(for: Date()).addingTimeInterval(1)
        #expect(InsightService.groundedNudgeUserMessage([today]).hasPrefix("Today's journal entry:"))
    }
}
