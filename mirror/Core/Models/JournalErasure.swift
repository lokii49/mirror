import Foundation
import SwiftData

/// Synced record of a "Delete Everything": which entries and mood check-ins were erased, so no device's
/// on-device backup (`LocalJournalBackup`) offers them back.
///
/// Without it, the deletes sync to the other devices, their stores collapse, their backups
/// freeze, and they offer "Restore N entries" — the very entries the user just permanently
/// deleted. Erased IDs rather than a timestamp: entries can be backdated, and device clocks
/// differ, so "created before the erase" would misjudge both ways.
///
/// Holds UUIDs only (already plaintext in CloudKit as `Entry.id` / `MoodCheckIn.id`), never content.
/// Synced via CloudKit — a new record type (`CD_JournalErasure`) that must be deployed to
/// the Production schema before any build that writes it ships.
@Model final class JournalErasure {
    var id: UUID = UUID()
    var erasedAt: Date = Date()
    /// Concatenated 16-byte UUIDs; ~160 KB for 10,000 entries (CKRecord limit is 1 MB).
    var erasedEntryIDsStorage: Data? = nil
    var erasedCheckInIDsStorage: Data? = nil

    init(erasedAt: Date = Date(), erasedEntryIDs: [UUID], erasedCheckInIDs: [UUID] = []) {
        self.erasedAt = erasedAt
        self.erasedEntryIDsStorage = Self.encode(erasedEntryIDs)
        self.erasedCheckInIDsStorage = Self.encode(erasedCheckInIDs)
    }

    var erasedEntryIDs: Set<UUID> {
        Self.decode(erasedEntryIDsStorage)
    }

    var erasedCheckInIDs: Set<UUID> {
        Self.decode(erasedCheckInIDsStorage)
    }

    static func encode(_ ids: [UUID]) -> Data {
        ids.reduce(into: Data(capacity: ids.count * 16)) { data, id in
            withUnsafeBytes(of: id.uuid) { data.append(contentsOf: $0) }
        }
    }

    static func decode(_ data: Data?) -> Set<UUID> {
        guard let data, data.count >= 16 else { return [] }
        let bytes = [UInt8](data)
        return Set(stride(from: 0, through: bytes.count - 16, by: 16).map { offset in
            let b = bytes[offset..<offset + 16].map { $0 }
            return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                               b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        })
    }

    /// Every entry ID erased by any "Delete Everything" on any device.
    @MainActor
    static func allErasedEntryIDs(in context: ModelContext) -> Set<UUID> {
        let erasures = (try? context.fetch(FetchDescriptor<JournalErasure>())) ?? []
        return erasures.reduce(into: Set<UUID>()) { $0.formUnion($1.erasedEntryIDs) }
    }

    /// Every mood check-in ID erased by any "Delete Everything" on any device.
    @MainActor
    static func allErasedCheckInIDs(in context: ModelContext) -> Set<UUID> {
        let erasures = (try? context.fetch(FetchDescriptor<JournalErasure>())) ?? []
        return erasures.reduce(into: Set<UUID>()) { $0.formUnion($1.erasedCheckInIDs) }
    }
}
