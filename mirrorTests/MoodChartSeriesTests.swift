import Testing
import Foundation
@testable import mirror

// The mood timeline drew its area fill and smoothed line through every reading. Several readings
// on one day gave them duplicate x values, which showed as faint wedges inside the plot
// (backlog E). The line and area now get one point per day; the dots still show every reading.
@Suite("Mood chart line series")
@MainActor
struct MoodChartSeriesTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func severalReadingsOnADay_becomeOnePointAtTheirMean() {
        let readings = [
            (date: date(6, 21), score: 5.0),
            (date: date(5, 9), score: 2.0),
            (date: date(5, 22), score: 4.0),
            (date: date(7, 8), score: 1.0),
        ]
        let series = MoodChartSeries.dailyMeans(readings, calendar: calendar)
        #expect(series.map(\.day) == [5, 6, 7].map { calendar.startOfDay(for: date($0, 12)) })
        #expect(series.map(\.score) == [3.0, 5.0, 1.0])
    }

    @Test func noDayAppearsTwice() {
        let readings = (0..<12).map { (date: date(3 + $0 / 4, 8 + $0), score: Double($0 % 5 + 1)) }
        let days = MoodChartSeries.dailyMeans(readings, calendar: calendar).map(\.day)
        #expect(Set(days).count == days.count)
        #expect(days == days.sorted())
    }

    @Test func noReadings_noLine() {
        #expect(MoodChartSeries.dailyMeans([], calendar: calendar).isEmpty)
    }
}
