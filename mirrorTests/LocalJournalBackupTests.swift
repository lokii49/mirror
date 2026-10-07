import Testing
import Foundation
import SwiftData
@testable import mirror

@Suite("LocalJournalBackup")
struct LocalJournalBackupTests {
    // MARK: - Decision rule

    @Test func collapseToZeroOrUnderHalfLooksPurged() {
        #expect(LocalJournalBackup.looksPurged(current: 0, backup: 1))
        #expect(LocalJournalBackup.looksPurged(current: 4, backup: 40))
        #expect(!LocalJournalBackup.looksPurged(current: 1, backup: 4))   // < 5 apart: ordinary deletes
        #expect(!LocalJournalBackup.looksPurged(current: 30, backup: 40))
        #expect(!LocalJournalBackup.looksPurged(current: 0, backup: 0))
    }

    @Test func unknownCountNeverFreezesOrOverwrites() {
        let state = LocalJournalBackup.State(entryCount: 40, snapshotAt: Date())
        #expect(LocalJournalBackup.decide(current: .unknown, state: state) == .keep)
    }

    @Test func frozenBackupIsNeverRefreshed() {
        let state = LocalJournalBackup.State(entryCount: 40, frozen: true)
        #expect(LocalJournalBackup.decide(current: .entries(80), state: state) == .keep)
    }

    @Test func decideFreezesOnCollapseAndRefreshesOtherwise() {
        let state = LocalJournalBackup.State(entryCount: 40)
        #expect(LocalJournalBackup.decide(current: .entries(0), state: state) == .freeze)
        #expect(LocalJournalBackup.decide(current: .entries(41), state: state) == .refresh)
        #expect(LocalJournalBackup.decide(current: .entries(0), state: .init()) == .keep)
    }

    // MARK: - SQLite against a real SwiftData store

    @Test @MainActor func countsAndCopiesARealStore() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("journal.store")
        try makeStore(at: storeURL, entries: 3)

        // Proves the ZENTRY table name SwiftData uses for Entry.
        #expect(LocalJournalBackup.entryCount(at: storeURL) == .entries(3))

        let copyURL = dir.appendingPathComponent("copy.store")
        #expect(LocalJournalBackup.copyDatabase(from: storeURL, to: copyURL))
        #expect(LocalJournalBackup.entryCount(at: copyURL) == .entries(3))
    }

    /// The restore path: SwiftData must open a backup copy and read the entries back.
    @Test @MainActor func backupCopyOpensInSwiftData() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("journal.store")
        try makeStore(at: storeURL, entries: 4)
        let copyURL = dir.appendingPathComponent("copy.store")
        #expect(LocalJournalBackup.copyDatabase(from: storeURL, to: copyURL))

        let config = ModelConfiguration("RestoreTest", schema: MirrorModelContainer.schema, url: copyURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let restored = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(restored.count == 4)
        #expect(restored.allSatisfy { $0.encryptedText == "synthetic" })
    }

    @Test func missingOrForeignFileIsUnknown() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(LocalJournalBackup.entryCount(at: dir.appendingPathComponent("absent.store")) == .unknown)
        let junk = dir.appendingPathComponent("junk.store")
        try Data("not a database".utf8).write(to: junk)
        #expect(LocalJournalBackup.entryCount(at: junk) == .unknown)
    }

    @Test @MainActor func snapshotRefreshesThenFreezesAfterPurge() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = try #require(UserDefaults(suiteName: "LocalJournalBackupTests-\(UUID())"))
        let storeURL = dir.appendingPathComponent("journal.store")
        let backupURL = dir.appendingPathComponent("backup/journal-backup.store")
        try makeStore(at: storeURL, entries: 6)

        #expect(LocalJournalBackup.snapshotIfNeeded(storeURL: storeURL, backupURL: backupURL, defaults: defaults) == .refresh)
        #expect(LocalJournalBackup.loadState(defaults).entryCount == 6)
        #expect(LocalJournalBackup.entryCount(at: backupURL) == .entries(6))

        // Simulate the CloudKit purge: same store, every entry gone.
        try deleteAllEntries(at: storeURL)
        #expect(LocalJournalBackup.snapshotIfNeeded(storeURL: storeURL, backupURL: backupURL, defaults: defaults) == .freeze)
        #expect(LocalJournalBackup.loadState(defaults).frozen)
        // The good backup survived.
        #expect(LocalJournalBackup.entryCount(at: backupURL) == .entries(6))

        LocalJournalBackup.deleteBackup(backupURL: backupURL, defaults: defaults)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        #expect(LocalJournalBackup.loadState(defaults) == LocalJournalBackup.State())
    }

    /// Restored rows are tracked by PersistentIdentifier saved as JSON in UserDefaults; the
    /// decoded ID must still match the row after a relaunch (a new container on the same
    /// file), or reconcileRestoredCopies would treat every restored row as user-deleted.
    @Test @MainActor func persistentIdentifierSurvivesJSONAndRelaunch() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("journal.store")
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, url: storeURL, cloudKitDatabase: .none)

        let encoded: Data = try {
            let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
            let entry = Entry(text: "")
            container.mainContext.insert(entry)
            try container.mainContext.save()
            return try JSONEncoder().encode([entry.persistentModelID])
        }()

        let decoded = try JSONDecoder().decode([PersistentIdentifier].self, from: encoded)
        let relaunched = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let live = try relaunched.mainContext.fetch(FetchDescriptor<Entry>()).map(\.persistentModelID)
        #expect(decoded.count == 1)
        #expect(live.contains(decoded[0]))
    }

    // MARK: - Restore copies every stored property

    @Test func entryCopyCoversEveryStoredProperty() throws {
        let entity = try #require(Schema([Entry.self]).entitiesByName["Entry"])
        #expect(Set(entity.storedProperties.map(\.name)) == Entry.copiedProperties)
    }

    @Test func moodCheckInCopyCoversEveryStoredProperty() throws {
        let entity = try #require(Schema([MoodCheckIn.self]).entitiesByName["MoodCheckIn"])
        #expect(Set(entity.storedProperties.map(\.name)) == MoodCheckIn.copiedProperties)
    }

    @Test func organizationCopiesCoverEveryStoredProperty() throws {
        let collection = try #require(Schema([JournalCollection.self]).entitiesByName["JournalCollection"])
        #expect(Set(collection.storedProperties.map(\.name)) == JournalCollection.copiedProperties)
        let view = try #require(Schema([SavedEntryView.self]).entitiesByName["SavedEntryView"])
        #expect(Set(view.storedProperties.map(\.name)) == SavedEntryView.copiedProperties)
    }

    @Test @MainActor func restoredCopyKeepsCiphertextAndID() {
        let original = Entry(text: "")
        original.encryptedText = "mirror:v1:opaque-ciphertext"
        original.encryptedMood = "mirror:v1:opaque-mood"
        original.isPinned = true
        original.wordCount = 7
        let copy = Entry.restoredCopy(of: original)
        #expect(copy.id == original.id)
        #expect(copy.encryptedText == original.encryptedText)
        #expect(copy.encryptedMood == original.encryptedMood)
        #expect(copy.isPinned && copy.wordCount == 7)
    }

    // MARK: - Helpers

    private func scratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalJournalBackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeStore(at url: URL, entries: Int) throws {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let context = container.mainContext
        for _ in 0..<entries {
            let entry = Entry(text: "")
            entry.encryptedText = "synthetic"
            context.insert(entry)
        }
        try context.save()
    }

    @MainActor
    private func deleteAllEntries(at url: URL) throws {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        try container.mainContext.delete(model: Entry.self)
        try container.mainContext.save()
    }
}
