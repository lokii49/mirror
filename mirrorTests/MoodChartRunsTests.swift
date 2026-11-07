import Foundation
import Testing
@testable import mirror

/// The mood charts draw one line per run of consecutive days, so a day with no mood is a gap
/// (UI checklist, 2026-11-07).
@Suite("Mood chart runs")
struct MoodChartRunsTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ d: Int, month: Int = 11) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: d))! }

    @Test func aMissingDayStartsANewRun() {
        let means = [1, 2, 4, 5, 6, 9].map { MoodDayMean(day: day($0), score: 3) }
        #expect(MoodChartSeries.runs(means, calendar: cal).map(\.run) == [0, 0, 1, 1, 1, 2])
    }

    @Test func consecutiveDaysAcrossAMonthStayOneRun() {
        let means = [day(31, month: 10), day(1), day(2)].map { MoodDayMean(day: $0, score: 2) }
        #expect(MoodChartSeries.runs(means, calendar: cal).map(\.run) == [0, 0, 0])
    }

    @Test func emptyAndSingleDay() {
        #expect(MoodChartSeries.runs([], calendar: cal).isEmpty)
        #expect(MoodChartSeries.runs([MoodDayMean(day: day(3), score: 4)], calendar: cal).map(\.run) == [0])
    }

    // Chart data cases from the UI checklist: 2 and 7 days, several readings a day, a week over a
    // month boundary, and a daylight-saving week.

    @Test func twoAndSevenConsecutiveDaysAreOneLine() {
        let two = [day(6), day(7)].map { MoodDayMean(day: $0, score: 3) }
        #expect(MoodChartSeries.runs(two, calendar: cal).map(\.run) == [0, 0])
        let week = (1...7).map { MoodDayMean(day: day($0), score: Double($0 % 5 + 1)) }
        #expect(Set(MoodChartSeries.runs(week, calendar: cal).map(\.run)) == [0])
    }

    @Test func severalReadingsADayAreOnePointAtTheirMean() {
        let morning = cal.date(byAdding: .hour, value: 8, to: day(4))!
        let night = cal.date(byAdding: .hour, value: 22, to: day(4))!
        let next = cal.date(byAdding: .hour, value: 9, to: day(5))!
        let means = MoodChartSeries.dailyMeans([(morning, 1), (night, 4), (next, 5)], calendar: cal)
        #expect(means.map(\.day) == [day(4), day(5)])
        #expect(means.map(\.score) == [2.5, 5])
        #expect(MoodChartSeries.runs(means, calendar: cal).map(\.run) == [0, 0])
    }

    @Test func aWeekOverAMonthBoundaryWithAGap() {
        let means = [day(29, month: 10), day(30, month: 10), day(1), day(2), day(3)].map { MoodDayMean(day: $0, score: 3) }
        // 31 October has no mood: the line breaks there and picks up on 1 November.
        #expect(MoodChartSeries.runs(means, calendar: cal).map(\.run) == [0, 0, 1, 1, 1])
    }

    @Test func aDaylightSavingWeekStaysOneLine() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // US clocks change on 1 November 2026 (fall back) and 8 March 2026 (spring forward).
        for (month, days) in [(10, 29...31), (3, 6...10)] as [(Int, ClosedRange<Int>)] {
            var dates = days.map { la.date(from: DateComponents(year: 2026, month: month, day: $0, hour: 12))! }
            if month == 10 { dates += (1...3).map { la.date(from: DateComponents(year: 2026, month: 11, day: $0, hour: 12))! } }
            let means = MoodChartSeries.dailyMeans(dates.map { ($0, 3) }, calendar: la)
            #expect(means.count == dates.count)
            #expect(Set(MoodChartSeries.runs(means, calendar: la).map(\.run)) == [0])
        }
    }

    @Test func summaryForNoneAndOneReading() {
        #expect(MoodChartSummary.text([], calendar: cal).isEmpty)
        let one = MoodDot(id: UUID(), date: day(3), mood: "Hopeful", score: 4, origin: .entry)
        #expect(!MoodChartSummary.text([one], calendar: cal).isEmpty)
    }
}
