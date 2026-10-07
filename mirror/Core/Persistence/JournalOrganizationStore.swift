import Foundation
import SwiftData

/// Collections and saved views: every change goes through here so the rules hold
/// on iOS and Mac alike. Nothing here ever deletes an entry.
enum JournalOrganizationStore {
    enum StoreError: Error { case keyUnavailable }

    // MARK: - Collections

    static func collections(in context: ModelContext) -> [JournalCollection] {
        let all = (try? context.fetch(FetchDescriptor<JournalCollection>())) ?? []
        return all.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    @discardableResult
    static func createCollection(name: String, icon: String = "folder", colorIndex: Int = 0,
                                 in context: ModelContext) throws -> JournalCollection {
        let next = (collections(in: context).map(\.sortIndex).max() ?? -1) + 1
        let collection = JournalCollection(payload: .init(name: name, icon: icon, colorIndex: colorIndex), sortIndex: next)
        guard collection.encryptedPayload != nil else { throw StoreError.keyUnavailable }
        context.insert(collection)
        try save(context)
        return collection
    }

    static func rename(_ collection: JournalCollection, to name: String, in context: ModelContext) throws {
        guard var payload = collection.payload else { throw StoreError.keyUnavailable }
        payload.name = name
        guard collection.setPayload(payload) else { throw StoreError.keyUnavailable }
        try save(context)
    }

    static func entryCount(in collectionID: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.collectionID == collectionID })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Entries keep everything (ids, dates, pins, tags, media) and become Unfiled.
    static func delete(_ collection: JournalCollection, in context: ModelContext) throws {
        let id = collection.id
        let members = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.collectionID == id }))) ?? []
        members.forEach { $0.collectionID = nil }
        context.delete(collection)
        try save(context)
    }

    static func move(_ entries: [Entry], to collectionID: UUID?, in context: ModelContext) throws {
        entries.forEach { $0.collectionID = collectionID }
        try save(context)
    }

    static func reorderCollections(_ ordered: [JournalCollection], in context: ModelContext) throws {
        for (index, collection) in ordered.enumerated() where collection.sortIndex != index {
            collection.sortIndex = index
        }
        try save(context)
    }

    // MARK: - Saved views

    static func savedViews(in context: ModelContext) -> [SavedEntryView] {
        let all = (try? context.fetch(FetchDescriptor<SavedEntryView>())) ?? []
        return all.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    @discardableResult
    static func saveView(_ payload: SavedEntryView.Payload, in context: ModelContext) throws -> SavedEntryView {
        let next = (savedViews(in: context).map(\.sortIndex).max() ?? -1) + 1
        let view = SavedEntryView(payload: payload, sortIndex: next)
        guard view.encryptedPayload != nil else { throw StoreError.keyUnavailable }
        context.insert(view)
        try save(context)
        return view
    }

    static func rename(_ view: SavedEntryView, to name: String, in context: ModelContext) throws {
        guard var payload = view.payload else { throw StoreError.keyUnavailable }
        payload.name = name
        guard view.setPayload(payload) else { throw StoreError.keyUnavailable }
        try save(context)
    }

    /// Removes the view only; its entries are untouched.
    static func delete(_ view: SavedEntryView, in context: ModelContext) throws {
        context.delete(view)
        try save(context)
    }

    static func reorderViews(_ ordered: [SavedEntryView], in context: ModelContext) throws {
        for (index, view) in ordered.enumerated() where view.sortIndex != index {
            view.sortIndex = index
        }
        try save(context)
    }

    // MARK: - Housekeeping

    /// A restored copy and the CloudKit original can coexist briefly with the same
    /// id. Keep one per id (a readable one if possible).
    static func removeDuplicates(in context: ModelContext) {
        var changed = false
        func collapse<Model: PersistentModel>(_ models: [Model], id: (Model) -> UUID, readable: (Model) -> Bool) {
            for group in Dictionary(grouping: models, by: id).values where group.count > 1 {
                let keep = group.first(where: readable) ?? group[0]
                for model in group where model.persistentModelID != keep.persistentModelID {
                    context.delete(model)
                    changed = true
                }
            }
        }
        collapse((try? context.fetch(FetchDescriptor<JournalCollection>())) ?? [], id: \.id, readable: { $0.payload != nil })
        collapse((try? context.fetch(FetchDescriptor<SavedEntryView>())) ?? [], id: \.id, readable: { $0.payload != nil })
        if changed { try? save(context) }
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
