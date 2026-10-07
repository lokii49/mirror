import Foundation
import SwiftData

// CloudKit constraints for both models: every stored property has a default, no
// `@Attribute(.unique)`, no relationships. Names and criteria are sealed with the
// content key, so CloudKit only sees ciphertext plus an id, a date and an order.
// Concurrent edits on two devices resolve last-writer-wins per record (CloudKit's
// behavior); a deleted collection or view never deletes entries.

/// A named group an entry can belong to (zero or one). `Entry.collectionID`
/// points here; deleting a collection moves its entries to Unfiled.
@Model final class JournalCollection {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    var encryptedPayload: Data? = nil

    struct Payload: Codable, Equatable, Sendable {
        var version = 1
        var name: String
        var icon: String = "folder"
        var colorIndex: Int = 0
    }

    init(id: UUID = UUID(), payload: Payload, sortIndex: Int) {
        self.id = id
        self.sortIndex = sortIndex
        _ = setPayload(payload)
    }

    /// Nil when this device can't decrypt it yet.
    var payload: Payload? {
        guard let encryptedPayload, let opened = MirrorEncryption.openData(encryptedPayload) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: opened)
    }

    /// False (and nothing changed) when the key is unavailable.
    @discardableResult
    func setPayload(_ payload: Payload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload), let sealed = MirrorEncryption.sealData(data) else { return false }
        encryptedPayload = sealed
        return true
    }
}

/// A saved search + filter + sort combination. Opening it re-runs the search;
/// no entries are copied.
@Model final class SavedEntryView {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    var encryptedPayload: Data? = nil

    struct Payload: Codable, Equatable, Sendable {
        var version = 1
        var name: String
        var query: String
        var criteria: SavedCriteria
        var sort: String
    }

    init(id: UUID = UUID(), payload: Payload, sortIndex: Int) {
        self.id = id
        self.sortIndex = sortIndex
        _ = setPayload(payload)
    }

    var payload: Payload? {
        guard let encryptedPayload, let opened = MirrorEncryption.openData(encryptedPayload) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: opened)
    }

    @discardableResult
    func setPayload(_ payload: Payload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload), let sealed = MirrorEncryption.sealData(data) else { return false }
        encryptedPayload = sealed
        return true
    }
}

/// A calendar day with no time or time zone: a saved "Sep 1 – Sep 30" stays those
/// days after travelling or a DST change, instead of shifting by the offset.
nonisolated struct CivilDate: Codable, Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day)).map { calendar.startOfDay(for: $0) }
    }
}

/// `EntryFilterCriteria` in a stable, versioned shape for storage.
nonisolated struct SavedCriteria: Codable, Equatable, Sendable {
    var moods: [String] = []
    var tags: [String] = []
    var tagMatch: String = EntryFilterCriteria.TagMatch.any.rawValue
    var dateScope: String = EntryFilterCriteria.DateScope.allTime.rawValue
    var start: CivilDate?
    var end: CivilDate?
    var photosOnly = false
    var audioOnly = false
    var pinnedOnly = false
    var collection: EntryFilterCriteria.CollectionScope = .all

    init(_ criteria: EntryFilterCriteria, calendar: Calendar = .current) {
        moods = criteria.moods.sorted()
        tags = criteria.tags.sorted()
        tagMatch = criteria.tagMatch.rawValue
        dateScope = criteria.dateScope.rawValue
        start = criteria.startDate.map { CivilDate($0, calendar: calendar) }
        end = criteria.endDate.map { CivilDate($0, calendar: calendar) }
        photosOnly = criteria.photosOnly
        audioOnly = criteria.audioOnly
        pinnedOnly = criteria.pinnedOnly
        collection = criteria.collection
    }

    private enum CodingKeys: String, CodingKey {
        case moods, tags, tagMatch, dateScope, start, end, photosOnly, audioOnly, pinnedOnly, collection
    }

    /// Missing keys fall back to defaults, so views saved by an older build (or
    /// read by a newer one) still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moods = try c.decodeIfPresent([String].self, forKey: .moods) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        tagMatch = try c.decodeIfPresent(String.self, forKey: .tagMatch) ?? EntryFilterCriteria.TagMatch.any.rawValue
        dateScope = try c.decodeIfPresent(String.self, forKey: .dateScope) ?? EntryFilterCriteria.DateScope.allTime.rawValue
        start = try c.decodeIfPresent(CivilDate.self, forKey: .start)
        end = try c.decodeIfPresent(CivilDate.self, forKey: .end)
        photosOnly = try c.decodeIfPresent(Bool.self, forKey: .photosOnly) ?? false
        audioOnly = try c.decodeIfPresent(Bool.self, forKey: .audioOnly) ?? false
        pinnedOnly = try c.decodeIfPresent(Bool.self, forKey: .pinnedOnly) ?? false
        collection = (try? c.decodeIfPresent(EntryFilterCriteria.CollectionScope.self, forKey: .collection)) ?? .all
    }

    func criteria(calendar: Calendar = .current) -> EntryFilterCriteria {
        var result = EntryFilterCriteria()
        result.moods = Set(moods)
        result.tags = Set(tags)
        result.tagMatch = EntryFilterCriteria.TagMatch(rawValue: tagMatch) ?? .any
        result.dateScope = EntryFilterCriteria.DateScope(rawValue: dateScope) ?? .allTime
        result.startDate = start?.date(in: calendar)
        result.endDate = end?.date(in: calendar)
        result.photosOnly = photosOnly
        result.audioOnly = audioOnly
        result.pinnedOnly = pinnedOnly
        result.collection = collection
        return result
    }
}
