import Foundation
import SwiftData

/// Recently Deleted. Every user delete of an entry goes through `moveToTrash`; rows older than
/// `retention` are removed for good on app-active and the nightly pass.
enum EntryTrash {
    static let retentionDays = 30
    static var retention: TimeInterval { TimeInterval(retentionDays) * 24 * 60 * 60 }

    /// Moves the entries to Recently Deleted and saves. Their unsaved edit drafts are dropped,
    /// as a delete always did. On a failed save nothing changes and the error is thrown.
    @MainActor
    static func moveToTrash(_ entries: [Entry], in context: ModelContext, now: Date = Date()) throws {
        guard !entries.isEmpty else { return }
        // Read before the delete is saved: a deleted model's attributes may not be readable after.
        let ids = entries.map(\.id)
        for entry in entries {
            context.insert(TrashedEntry(copying: entry, deletedAt: now))
            context.delete(entry)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        for id in ids {
            WriteDraftStore.clearIncludingPreserved(slot: .entry(id))
        }
    }

    /// Everything in Recently Deleted, most recently deleted first, one row per entry (two
    /// devices deleting the same entry leave two rows; the newer one is shown).
    @MainActor
    static func items(in context: ModelContext) -> [TrashedEntry] {
        let all = (try? context.fetch(FetchDescriptor<TrashedEntry>(sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]))) ?? []
        return newestPerEntry(all)
    }

    static func newestPerEntry(_ rows: [TrashedEntry]) -> [TrashedEntry] {
        var seen = Set<UUID>()
        return rows
            .sorted { $0.deletedAt > $1.deletedAt }
            .filter { seen.insert($0.entryID).inserted }
    }

    /// Puts the entries back with their original ids and removes every trash row for them. An
    /// entry that is already back (restored on another device) only loses its trash rows. A
    /// collection deleted meanwhile leaves the entry Unfiled.
    @MainActor
    @discardableResult
    static func restore(_ items: [TrashedEntry], in context: ModelContext) throws -> [UUID] {
        let ids = Set(items.map(\.entryID))
        guard !ids.isEmpty else { return [] }
        let rows = rows(for: ids, in: context)
        let existing = existingEntryIDs(ids, in: context)
        let collections = Set(((try? context.fetch(FetchDescriptor<JournalCollection>())) ?? []).map(\.id))
        var restored: [UUID] = []
        for row in newestPerEntry(rows) where !existing.contains(row.entryID) {
            let entry = row.restoredEntry()
            if let collectionID = entry.collectionID, !collections.contains(collectionID) {
                entry.collectionID = nil
            }
            context.insert(entry)
            restored.append(row.entryID)
        }
        rows.forEach(context.delete)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return restored
    }

    /// Removes the entries for good (Delete Now / Empty Recently Deleted).
    @MainActor
    static func deletePermanently(_ items: [TrashedEntry], in context: ModelContext) throws {
        let ids = Set(items.map(\.entryID))
        guard !ids.isEmpty else { return }
        rows(for: ids, in: context).forEach(context.delete)
        try context.save()
    }

    @MainActor
    static func empty(in context: ModelContext) throws {
        ((try? context.fetch(FetchDescriptor<TrashedEntry>())) ?? []).forEach(context.delete)
        try context.save()
    }

    /// Removes rows deleted more than `retention` ago. Idempotent across devices: each one
    /// removes the same rows.
    @MainActor
    static func purgeExpired(in context: ModelContext, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        let descriptor = FetchDescriptor<TrashedEntry>(predicate: #Predicate { $0.deletedAt < cutoff })
        guard let expired = try? context.fetch(descriptor), !expired.isEmpty else { return }
        expired.forEach(context.delete)
        try? context.save()
    }

    /// Whole days left before the row is removed for good (0 on its last day).
    static func daysRemaining(for row: TrashedEntry, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let expiry = row.deletedAt.addingTimeInterval(retention)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiry)).day ?? 0
        return max(0, days)
    }

    // MARK: - Private

    @MainActor
    private static func rows(for ids: Set<UUID>, in context: ModelContext) -> [TrashedEntry] {
        ((try? context.fetch(FetchDescriptor<TrashedEntry>())) ?? []).filter { ids.contains($0.entryID) }
    }

    @MainActor
    private static func existingEntryIDs(_ ids: Set<UUID>, in context: ModelContext) -> Set<UUID> {
        var found = Set<UUID>()
        for id in ids {
            var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let count = try? context.fetchCount(descriptor), count > 0 { found.insert(id) }
        }
        return found
    }
}
