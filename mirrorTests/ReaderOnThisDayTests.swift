import Testing
import SwiftData
import Foundation
@testable import mirror

/// The entry reader's On This Day list (per-year date-range fetches). Synthetic text only.
@Suite("Reader On This Day")
@MainActor
struct ReaderOnThisDayTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Entry.self, Insight.self, MoodCheckIn.self, configurations: config)
        return ModelContext(container)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func insert(_ date: Date, _ text: String, in context: ModelContext) -> Entry {
        let e = Entry(text: text); e.createdAt = date; context.insert(e); return e
    }

    @Test func findsTheSameDayInOtherYearsNewestFirst() throws {
        let context = try makeContext()
        let me = insert(day(2026, 3, 14), "Synthetic today.", in: context)
        _ = insert(day(2026, 3, 14, hour: 20), "Same day, same year.", in: context)
        let a = insert(day(2024, 3, 14, hour: 0), "Two years ago, midnight.", in: context)
        let b = insert(day(2025, 3, 14, hour: 23), "Last year, late.", in: context)
        _ = insert(day(2025, 3, 15), "The day after.", in: context)
        _ = insert(day(2023, 3, 13, hour: 23), "The day before.", in: context)
        try context.save()
        let found = EntryDetailView.onThisDay(for: me, in: context)
        #expect(found.map(\.id) == [b.id, a.id])
    }

    @Test func leapDayOnlyMatchesLeapDays() throws {
        let context = try makeContext()
        let me = insert(day(2028, 2, 29), "Leap day.", in: context)
        let leap = insert(day(2024, 2, 29), "Earlier leap day.", in: context)
        _ = insert(day(2025, 3, 1), "March first, no leap day that year.", in: context)
        try context.save()
        #expect(EntryDetailView.onThisDay(for: me, in: context).map(\.id) == [leap.id])
    }
}
