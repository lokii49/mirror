import Foundation

/// One evaluator for visual archive filters on every platform. Search syntax is
/// evaluated separately and combined with these criteria using AND.
nonisolated struct EntryFilterCriteria: Equatable, Sendable {
    enum TagMatch: String, CaseIterable, Sendable { case any, all }
    enum DateScope: String, CaseIterable, Sendable { case allTime, range, today, thisWeek, thisMonth }
    enum CollectionScope: Codable, Hashable, Sendable {
        case all, unfiled
        case collection(UUID)
    }

    var moods: Set<String> = []
    var tags: Set<String> = []
    var tagMatch: TagMatch = .any
    var dateScope: DateScope = .allTime
    var startDate: Date?
    var endDate: Date?
    var photosOnly = false
    var audioOnly = false
    var pinnedOnly = false
    var collection: CollectionScope = .all

    var isActive: Bool {
        !moods.isEmpty || !tags.isEmpty || dateScope != .allTime || photosOnly || audioOnly || pinnedOnly || collection != .all
    }
    var isRelativeDate: Bool { [.today, .thisWeek, .thisMonth].contains(dateScope) }
    var selectedDay: Date? {
        guard dateScope == .range, let startDate, let endDate,
              Calendar.current.isDate(startDate, inSameDayAs: endDate) else { return nil }
        return startDate
    }
    mutating func selectDay(_ date: Date?) {
        dateScope = date == nil ? .allTime : .range
        startDate = date
        endDate = date
    }
    func hasValidRange(calendar: Calendar = .current) -> Bool {
        guard dateScope == .range, let startDate, let endDate else { return true }
        return calendar.startOfDay(for: startDate) <= calendar.startOfDay(for: endDate)
    }

    func matches(_ document: EntrySearchDocument, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isActive else { return true }
        // Membership is a plain id, readable without the key. A collection that no
        // longer exists matches nothing; the UI shows it as missing.
        switch collection {
        case .all: break
        case .unfiled: if document.collectionID != nil { return false }
        case .collection(let id): if document.collectionID != id { return false }
        }
        // Collection alone: an entry this device can't decrypt still belongs there.
        let filtersContent = !moods.isEmpty || !tags.isEmpty || dateScope != .allTime || photosOnly || audioOnly || pinnedOnly
        guard filtersContent else { return true }
        guard document.isReadable, hasValidRange(calendar: calendar) else { return false }
        if !moods.isEmpty, !moods.contains(where: { document.moods.contains(EntrySearch.fold($0)) }) { return false }
        if !tags.isEmpty {
            let matches = tags.map { document.tags.contains(EntrySearch.fold($0)) }
            if tagMatch == .all ? matches.contains(false) : !matches.contains(true) { return false }
        }
        if photosOnly && !document.hasPhoto { return false }
        if audioOnly && !document.hasAudio { return false }
        if pinnedOnly && !document.isPinned { return false }
        switch dateScope {
        case .allTime: break
        case .range:
            if let startDate, document.createdAt < calendar.startOfDay(for: startDate) { return false }
            if let endDate {
                let day = calendar.startOfDay(for: endDate)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
                if document.createdAt >= calendar.startOfDay(for: next) { return false }
            }
        case .today, .thisWeek, .thisMonth:
            let component: Calendar.Component = dateScope == .today ? .day : (dateScope == .thisWeek ? .weekOfYear : .month)
            guard let interval = calendar.dateInterval(of: component, for: now),
                  document.createdAt >= interval.start, document.createdAt < interval.end else { return false }
        }
        return true
    }
}
