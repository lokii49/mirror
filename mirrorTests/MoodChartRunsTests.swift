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
}
