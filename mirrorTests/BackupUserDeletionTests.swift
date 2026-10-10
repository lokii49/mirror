import Testing
import SwiftData
import Foundation
@testable import mirror

/// Backlog A13: undoing an import or deleting entries froze the device backup and offered the
/// deleted entries back. Synthetic text only.
@Suite(.serialized)
@MainActor
struct BackupUserDeletionTests {
    private let defaults = UserDefaults(suiteName: "BackupUserDeletionTests")!

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: MirrorModelContainer.schema, configurations: config))
    }

    @Test func offerLeavesOutErasedAndUserDeletedRows() {
        let (a, b, c, d) = (UUID(), UUID(), UUID(), UUID())
        let offered = LocalJournalBackup.offeredIDs(backup: [a, b, c, d], journal: [a], erased: [b], userDeleted: [c])
        #expect(offered == [d], "a purge's missing rows are still offered")
    }

    @Test func ledgerRecordsAndForgetsBySnapshotTime() {
        defaults.removePersistentDomain(forName: "BackupUserDeletionTests")
        let old = UUID(), new = UUID()
        LocalJournalBackup.recordUserDeleted([old], at: Date(timeIntervalSince1970: 100), defaults: defaults)
        LocalJournalBackup.recordUserDeleted([new], at: Date(timeIntervalSince1970: 300), defaults: defaults)
        #expect(LocalJournalBackup.userDeletedIDs(defaults: defaults) == [old, new])
        LocalJournalBackup.forgetUserDeleted(before: Date(timeIntervalSince1970: 200), defaults: defaults)
        #expect(LocalJournalBackup.userDeletedIDs(defaults: defaults) == [new])
    }

    @Test func deletesInAContextAreRecordedBeforeTheSave() throws {
        let context = try makeContext()
        let entry = Entry(text: "A synthetic entry to delete.")
        let checkIn = MoodCheckIn(mood: "Content")
        let kept = Entry(text: "A synthetic entry that stays.")
        context.insert(entry); context.insert(checkIn); context.insert(kept)
        try context.save()
        let ids = (entry.id, checkIn.id, kept.id)
        context.delete(entry); context.delete(checkIn)
        JournalSafety.recordDeletions(in: context)
        let ledger = LocalJournalBackup.userDeletedIDs()
        #expect(ledger.contains(ids.0) && ledger.contains(ids.1))
        #expect(!ledger.contains(ids.2))
        try context.save()
        LocalJournalBackup.forgetUserDeleted(before: .distantFuture)
    }

    @Test func undoImportWritesASyncedErasure() throws {
        let context = try makeContext()
        let entry = Entry(text: "An imported synthetic entry.")
        context.insert(entry)
        try context.save()
        let digest = try #require(entry.archiveSnapshot()?.digest)
        let batch = ArchiveTransfer.ImportBatch(digests: [entry.id: digest])
        let id = entry.id
        let result = try ArchiveTransfer.undoImport(batch, context: context)
        #expect(result.removed == 1)
        #expect(JournalErasure.allErasedEntryIDs(in: context).contains(id))
    }
}
