import Testing
import Foundation
@testable import mirror

/// Backlog A19: heatmap days read as a date and an entry count, not bare numbers.
@Suite("Heatmap accessibility label")
struct HeatmapAccessibilityTests {
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!

    @Test func includesTheFullDate() {
        let label = HeatmapAccessibility.label(for: day, count: 0)
        #expect(label == day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
    }

    @Test func addsTheEntryCount() {
        #expect(HeatmapAccessibility.label(for: day, count: 1).hasSuffix(", " + String(localized: "1 entry")))
        #expect(HeatmapAccessibility.label(for: day, count: 3).hasSuffix(", " + String(localized: "\(3) entries")))
    }
}
