import Foundation
import Testing
@testable import mirror

@Suite("Archive visual filters")
struct EntryFilterCriteriaTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }
    private func date(_ day: Int, month: Int = 10, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
    private func document(mood: String = "Content", tags: [String] = ["work", "travel"],
                          date: Date? = nil, photo: Bool = true, audio: Bool = true,
                          pinned: Bool = true, readable: Bool = true) -> EntrySearchDocument {
        .init(passages: [.init("Coffee by the river.", source: .body)], tags: tags.map(EntrySearch.fold),
              moods: [EntrySearch.fold(mood)], createdAt: date ?? self.date(7),
              hasPhoto: photo, hasAudio: audio, isPinned: pinned, isReadable: readable)
    }

    @Test func moodsUseOrAndCategoriesUseAnd() {
        var filters = EntryFilterCriteria()
        filters.moods = ["Content", "Anxious"]
        filters.tags = ["work"]
        #expect(filters.matches(document(mood: "Content")))
        #expect(filters.matches(document(mood: "Anxious")))
        #expect(!filters.matches(document(mood: "Sad")))
        #expect(!filters.matches(document(mood: "Anxious", tags: ["travel"])))
    }
    @Test func tagsSupportAnyAndAllWithFullNameAndDiacritics() {
        var filters = EntryFilterCriteria()
        filters.tags = ["WORK", "café"]
        #expect(filters.matches(document(tags: ["work"])))
        #expect(filters.matches(document(tags: ["CAFE"])))
        #expect(!filters.matches(document(tags: ["work trip"])))
        filters.tagMatch = .all
        #expect(!filters.matches(document(tags: ["work"])))
        #expect(filters.matches(document(tags: ["work", "cafe"])))
        filters.tags = []
        #expect(filters.matches(document(tags: [])))
    }
    @Test func fixedRangeIncludesBothWholeDaysAndSupportsOpenEnds() {
        var filters = EntryFilterCriteria()
        filters.dateScope = .range
        filters.startDate = date(6, hour: 16)
        filters.endDate = date(7, hour: 9)
        #expect(filters.matches(document(date: date(6, hour: 0)), calendar: calendar))
        #expect(filters.matches(document(date: date(7, hour: 23, minute: 59)), calendar: calendar))
        #expect(!filters.matches(document(date: date(5, hour: 23, minute: 59)), calendar: calendar))
        #expect(!filters.matches(document(date: date(8, hour: 0)), calendar: calendar))
        filters.startDate = nil
        #expect(filters.matches(document(date: date(1)), calendar: calendar))
        filters.startDate = date(6)
        filters.endDate = nil
        #expect(filters.matches(document(date: date(20)), calendar: calendar))
    }
    @Test func rangeHandlesDaylightSavingAndRejectsReversedDates() {
        var filters = EntryFilterCriteria()
        filters.dateScope = .range
        filters.startDate = date(8, month: 3)
        filters.endDate = date(8, month: 3)
        #expect(filters.matches(document(date: date(8, month: 3, hour: 23, minute: 59)), calendar: calendar))
        #expect(!filters.matches(document(date: date(9, month: 3, hour: 0)), calendar: calendar))
        filters.endDate = date(7, month: 3)
        #expect(!filters.hasValidRange(calendar: calendar))
        #expect(!filters.matches(document(), calendar: calendar))
    }
    @Test func relativeDatesReevaluateAtDayWeekAndMonthBoundaries() {
        var filters = EntryFilterCriteria()
        filters.dateScope = .today
        #expect(filters.matches(document(date: date(7)), now: date(7), calendar: calendar))
        #expect(!filters.matches(document(date: date(7)), now: date(8), calendar: calendar))
        filters.dateScope = .thisWeek
        #expect(filters.matches(document(date: date(5)), now: date(7), calendar: calendar))
        #expect(!filters.matches(document(date: date(4)), now: date(7), calendar: calendar))
        filters.dateScope = .thisMonth
        #expect(filters.matches(document(date: date(31)), now: date(7), calendar: calendar))
        #expect(!filters.matches(document(date: date(31)), now: date(1, month: 11), calendar: calendar))
    }
    @Test func mediaAndPinsCombineWithSearchWithoutBroadeningIt() {
        var filters = EntryFilterCriteria()
        filters.photosOnly = true
        filters.audioOnly = true
        filters.pinnedOnly = true
        #expect(filters.matches(document()))
        #expect(!filters.matches(document(photo: false)))
        #expect(!filters.matches(document(audio: false)))
        #expect(!filters.matches(document(pinned: false)))
        let query = EntrySearchQuery.parse("coffee -river")
        #expect(!(filters.matches(document()) && EntrySearch.matches(document(), query: query)))
        let included = UUID(), excluded = UUID()
        filters.tags = ["work", "travel"]
        filters.tagMatch = .all
        let results = EntrySearch.evaluate([(included, document()), (excluded, document(tags: ["work"]))],
                                           query: .parse("coffee"), filters: filters)
        #expect(results.ids == [included])
        #expect(results.excerpts[included] != nil)
    }
    @Test func unreadableEntriesRemainVisibleOnlyWithoutFilters() {
        var filters = EntryFilterCriteria()
        #expect(filters.matches(document(readable: false)))
        filters.pinnedOnly = true
        #expect(!filters.matches(document(readable: false)))
        filters = EntryFilterCriteria()
        #expect(!filters.isActive)
    }
    @Test func heatmapSelectionReplacesDateRangeWithoutRemovingOtherFilters() {
        var filters = EntryFilterCriteria()
        filters.moods = ["Content", "Sad"]
        filters.tags = ["work"]
        filters.photosOnly = true
        filters.selectDay(date(7))
        #expect(filters.startDate == filters.endDate)
        #expect(filters.moods.count == 2 && filters.tags == ["work"] && filters.photosOnly)
        filters.selectDay(nil)
        #expect(filters.dateScope == .allTime && filters.startDate == nil && filters.endDate == nil)
        #expect(filters.isActive)
    }
}
