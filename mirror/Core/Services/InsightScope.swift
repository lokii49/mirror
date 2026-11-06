import Foundation
import SwiftData

/// Which entries reflections and insights may read. A collection can be kept out (Organize ›
/// collection › Keep out of reflections; the ready-made Scratch collection starts that way), for
/// quick notes, lists and reminders that shouldn't come back quoted in a reflection.
///
/// Kept-out entries still count as writing (Entries list, search, heatmap, streaks, XP), but
/// nothing on the insight side reads them: no reflection, digest, report or Ask answer quotes them,
/// no model detects their mood, and no mood chart, mood alert or widget mood counts them. Filter
/// at the source with this type (a view's `@Query`, a background runner's fetch) rather than
/// inside InsightService, whose statics have no context.
///
/// The flag lives in the collection's encrypted payload, so there is no CloudKit schema change.
struct InsightScope: Equatable, Sendable {
    let excludedCollectionIDs: Set<UUID>

    static let everything = InsightScope(excludedCollectionIDs: [])

    init(excludedCollectionIDs: Set<UUID>) {
        self.excludedCollectionIDs = excludedCollectionIDs
    }

    /// A collection this device can't decrypt yet counts as included: its entries share the same
    /// key, so they can't be read for an insight either.
    init(collections: [JournalCollection]) {
        excludedCollectionIDs = Set(collections.lazy.filter { $0.payload?.keepsOutOfInsights == true }.map(\.id))
    }

    init(context: ModelContext) {
        self.init(collections: (try? context.fetch(FetchDescriptor<JournalCollection>())) ?? [])
    }

    var excludesNothing: Bool { excludedCollectionIDs.isEmpty }

    func includes(collectionID: UUID?) -> Bool {
        guard let collectionID else { return true }
        return !excludedCollectionIDs.contains(collectionID)
    }

    func includes(_ entry: Entry) -> Bool {
        excludesNothing || includes(collectionID: entry.collectionID)
    }

    /// The same array when nothing is kept out, so journals without such a collection pay nothing.
    func filter(_ entries: [Entry]) -> [Entry] {
        excludesNothing ? entries : entries.filter { includes(collectionID: $0.collectionID) }
    }
}

/// A view's journal with kept-out entries removed, rebuilt only when the journal or the
/// collections change (views read `entries` many times per render; the 2026-11-04 audit was about
/// exactly that kind of per-render pass over every entry). Hold one in `@State`; it is a plain
/// class so filling it in `body` doesn't invalidate the view.
@MainActor
final class InsightEntriesMemo {
    private struct CollectionsKey: Equatable {
        var ids: [UUID]
        var payloads: [Int]
    }

    private struct EntriesKey: Equatable {
        var revision: Int
        var count: Int
        var first: PersistentIdentifier?
        var last: PersistentIdentifier?
        var scope: InsightScope
    }

    private var collectionsKey: CollectionsKey?
    private var lastScope = InsightScope.everything
    private var entriesKey: EntriesKey?
    private var filtered: [Entry] = []

    init() {}

    func entries(_ all: [Entry], collections: [JournalCollection]) -> [Entry] {
        let currentScope = scope(for: collections)
        guard !currentScope.excludesNothing else { return all }
        // Moving an entry into or out of a kept-out collection changes neither the count nor the
        // ends of the list; the save that did it bumps the journal revision.
        let key = EntriesKey(revision: JournalRevision.shared.value, count: all.count,
                             first: all.first?.persistentModelID, last: all.last?.persistentModelID,
                             scope: currentScope)
        if key != entriesKey {
            filtered = currentScope.filter(all)
            entriesKey = key
        }
        return filtered
    }

    /// Decrypts the collections' payloads only when one of them changed.
    func scope(for collections: [JournalCollection]) -> InsightScope {
        let key = CollectionsKey(ids: collections.map(\.id), payloads: collections.map { $0.encryptedPayload?.hashValue ?? 0 })
        if key != collectionsKey {
            lastScope = InsightScope(collections: collections)
            collectionsKey = key
        }
        return lastScope
    }
}
