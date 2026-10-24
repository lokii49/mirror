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

// "This Week's Mood" said "Mostly Anxious" on one launch and "Mostly Hopeful" on the next for the
// same readings: a tie was settled by dictionary order. Ties now go to the latest reading.
@Suite("Dominant mood")
struct DominantMoodTests {
    private func event(_ mood: String, _ minutes: Double) -> MoodEvent {
        MoodEvent(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), mood: mood, origin: .entry)
    }

    @Test func mostFrequentWins() {
        let events = [event("Calm", 0), event("Anxious", 1), event("Calm", 2), event("Hopeful", 3)]
        #expect(MoodLog.dominantMood(events) == "Calm")
    }

    @Test func tieGoesToTheLatestReading_everyTime() {
        let events = [event("Anxious", 0), event("Hopeful", 1), event("Anxious", 2), event("Hopeful", 3)]
        for _ in 0..<50 {
            #expect(MoodLog.dominantMood(events) == "Hopeful")
            #expect(MoodLog.dominantMood(events.reversed()) == "Hopeful")
        }
    }

    @Test func noReadings_noMood() {
        #expect(MoodLog.dominantMood([]) == nil)
    }
}

// VoiceOver's summary of the mood chart (UI pass 2026-10-24): counts, most frequent mood, lowest
// reading and the direction of the line, all from the points the chart draws.
@Suite("Mood chart VoiceOver summary")
@MainActor
struct MoodChartSummaryTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func dot(_ mood: String, day: Int, hour: Int = 12) -> MoodDot {
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        return MoodDot(id: UUID(), date: date, mood: mood, score: MirrorTheme.moodScore[mood] ?? 3, origin: .entry)
    }

    private func day(_ dot: MoodDot) -> String { dot.date.formatted(.dateTime.day().month(.wide)) }

    @Test func namesCountRangeMostFrequentLowestAndRise() {
        let points = [dot("Anxious", day: 9), dot("Sad", day: 10), dot("Anxious", day: 12), dot("Content", day: 15), dot("Joyful", day: 20)]
        let text = MoodChartSummary.text(points, calendar: calendar)
        #expect(text.contains("5 mood readings from \(day(points[0])) to \(day(points[4]))."))
        #expect(text.contains("Most often \(MirrorTheme.localizedMoodName(for: "Anxious"))."))
        #expect(text.contains("Lowest: \(MirrorTheme.localizedMoodName(for: "Sad")) on \(day(points[1]))."))
        #expect(text.hasSuffix("Higher at the end than at the start."))
    }

    @Test func lowestTie_isTheMostRecent_andFallIsNamed() {
        let points = [dot("Joyful", day: 1), dot("Drained", day: 3), dot("Sad", day: 8)]
        let text = MoodChartSummary.text(points, calendar: calendar)
        #expect(text.contains("Lowest: \(MirrorTheme.localizedMoodName(for: "Sad")) on \(day(points[2]))."))
        #expect(text.hasSuffix("Lower at the end than at the start."))
    }

    @Test func flatLine_andOneReading() {
        #expect(MoodChartSummary.text([dot("Content", day: 2), dot("Peaceful", day: 4)], calendar: calendar)
            .hasSuffix("About the same at the end as at the start."))
        let one = dot("Hopeful", day: 6)
        #expect(MoodChartSummary.text([one], calendar: calendar) == "1 mood reading, on \(day(one)).")
        #expect(MoodChartSummary.text([], calendar: calendar).isEmpty)
    }

    @Test func levelNames_matchTheAxisBands() {
        #expect(MoodChartSummary.levelName(1) == "Low")
        #expect(MoodChartSummary.levelName(3) == "Mid")
        #expect(MoodChartSummary.levelName(5) == "High")
    }
}
