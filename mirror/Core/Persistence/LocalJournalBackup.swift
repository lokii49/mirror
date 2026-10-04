import Foundation
import SQLite3
import os
import SwiftData

/// An on-device copy of the journal store, kept so a CloudKit purge doesn't lose writing
/// that never reached iCloud.
///
/// When the user turns iCloud off for the app or signs out, NSPersistentCloudKitContainer
/// (under SwiftData) erases the local store on the next launch, by design. Anything that
/// hadn't been exported yet is gone. iOS gives the app no warning before that toggle, so
/// the only protection is a copy taken earlier:
///
/// - **Snapshot** (`snapshotIfNeeded`): taken when the app goes to the background — never
///   at launch, where a full copy of a photo-heavy store could trip the watchdog. Uses the
///   SQLite online-backup API, which is consistent even while Core Data has the store open.
/// - **Freeze** (`decide`): if the store's entry count has collapsed relative to the backup
///   (`looksPurged`), the backup is frozen — never overwritten — until the user restores
///   or discards it. Checked before the store opens each launch (count only, cheap) and
///   before every snapshot.
/// - **Unknown is not zero**: any read that fails (device locked during a background
///   launch, missing `-shm`, schema not there) is `.unknown`, which never freezes and
///   never overwrites — same rule as `KeychainManager.ReadResult`.
///
/// Restore and the restored-copy bookkeeping live in `JournalSafety`.
enum LocalJournalBackup {
    enum Count: Equatable {
        case entries(Int)
        case unknown
    }

    enum Decision: Equatable {
        case keep, freeze, refresh
    }

    struct State: Codable, Equatable {
        var entryCount = 0
        var snapshotAt: Date? = nil
        var frozen = false
        /// Rows this device inserted by restoring. Only the restoring device ever removes a
        /// duplicate, and only its own copy — see `JournalSafety.reconcileRestoredCopies`.
        var restoredEntryIDs: [PersistentIdentifier] = []
        var restoredCheckInIDs: [PersistentIdentifier] = []
        var restoredAt: Date? = nil
    }

    // MARK: - Decision (pure)

    /// A collapse to zero, or to under half of a backup that held at least 5 more entries.
    /// A real purge drops to zero, then partially refills as CloudKit re-imports; the
    /// "under half" arm catches a store that was already mid-refill when we looked.
    static func looksPurged(current: Int, backup: Int) -> Bool {
        guard backup > 0 else { return false }
        return current == 0 || (current * 2 < backup && backup - current >= 5)
    }

    static func decide(current: Count, state: State) -> Decision {
        guard !state.frozen, case .entries(let count) = current else { return .keep }
        if looksPurged(current: count, backup: state.entryCount) { return .freeze }
        return count > 0 ? .refresh : .keep
    }

    // MARK: - Locations

    static var backupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalJournalBackup", isDirectory: true)
            .appendingPathComponent("journal-backup.store")
    }

    /// The live store's file, or nil when there's nothing on disk to protect (in-memory
    /// configurations: tests, the Mac snapshot harness).
    static func liveStoreURL(_ configuration: ModelConfiguration = MirrorModelContainer.defaultConfiguration) -> URL? {
        #if DEBUG
        // The perf seed's scratch store must never be snapshotted over (or freeze) the real backup.
        if PerfSeed.isRequested { return nil }
        #endif
        return configuration.isStoredInMemoryOnly ? nil : configuration.url
    }

    // MARK: - State

    private static let stateKey = "mirror.localJournalBackup.state"
    private static let stateLock = NSLock()

    static func loadState(_ defaults: UserDefaults = .standard) -> State {
        stateLock.withLock { readState(defaults) }
    }

    /// Read-modify-write under one lock, so a background snapshot and a main-thread restore
    /// never interleave.
    @discardableResult
    static func updateState(_ defaults: UserDefaults = .standard, _ change: (inout State) -> Void) -> State {
        stateLock.withLock {
            var state = readState(defaults)
            change(&state)
            if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
            return state
        }
    }

    private static func readState(_ defaults: UserDefaults) -> State {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    // MARK: - Launch check

    /// Before the store opens: freeze if the last session's purge already emptied it. Count
    /// only — the copy itself never runs at launch.
    static func evaluateBeforeOpen(storeURL: URL?, defaults: UserDefaults = .standard) {
        guard let storeURL, FileManager.default.fileExists(atPath: backupURL.path) else { return }
        let current = entryCount(at: storeURL)
        updateState(defaults) { state in
            if decide(current: current, state: state) == .freeze { state.frozen = true }
        }
    }

    // MARK: - Snapshot

    private nonisolated(unsafe) static var snapshotInFlight = false

    /// Set by the background task's expiration handler. The copy checks it between small
    /// steps, so it releases its SQLite lock on the app-group store before iOS suspends us
    /// (holding a lock on a shared-container database across suspension is a 0xdead10cc kill).
    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    /// Refreshes the backup from the live store unless frozen, unchanged since the last
    /// snapshot, or unreadable. Blocking — call off the main thread.
    @discardableResult
    static func snapshotIfNeeded(
        storeURL: URL,
        backupURL: URL = backupURL,
        defaults: UserDefaults = .standard,
        cancel: CancelFlag? = nil
    ) -> Decision {
        let claimed: Bool = stateLock.withLock {
            guard !snapshotInFlight else { return false }
            snapshotInFlight = true
            return true
        }
        guard claimed else { return .keep }
        defer { stateLock.withLock { snapshotInFlight = false } }

        let state = loadState(defaults)
        if state.frozen { return .keep }
        if let at = state.snapshotAt,
           FileManager.default.fileExists(atPath: backupURL.path),
           let modified = lastModified(storeURL), modified <= at {
            return .keep
        }

        let current = entryCount(at: storeURL)
        switch decide(current: current, state: state) {
        case .keep:
            return .keep
        case .freeze:
            updateState(defaults) { $0.frozen = true }
            return .freeze
        case .refresh:
            let signpost = PerfSignpost.signposter.beginInterval("backup.snapshot")
            defer { PerfSignpost.signposter.endInterval("backup.snapshot", signpost) }
            let startedAt = Date()
            let dir = backupURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            removeLeftoverTemps(in: dir)
            let temp = dir.appendingPathComponent("journal-backup-\(UUID().uuidString).tmp")
            defer { removeDatabase(at: temp) }
            // Verify the copy reads back before it may replace a good backup.
            guard copyDatabase(from: storeURL, to: temp, cancel: cancel),
                  case .entries(let copied) = entryCount(at: temp), copied > 0 else { return .keep }
            removeDatabase(sidecarsOnlyAt: temp)
            do {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    _ = try FileManager.default.replaceItemAt(backupURL, withItemAt: temp)
                } else {
                    try FileManager.default.moveItem(at: temp, to: backupURL)
                }
            } catch {
                return .keep
            }
            updateState(defaults) { state in
                // A restore or freeze that landed while we copied wins.
                guard !state.frozen else { return }
                state.entryCount = copied
                state.snapshotAt = startedAt
            }
            return .refresh
        }
    }

    /// Discards the backup and its state ("Delete Everything", or the user dismissing a
    /// restore offer — then the next background snapshot starts fresh).
    static func deleteBackup(backupURL: URL = backupURL, defaults: UserDefaults = .standard) {
        removeDatabase(at: backupURL)
        updateState(defaults) { $0 = State() }
    }

    /// Unfreezes without deleting, keeping the restored-row bookkeeping.
    static func unfreeze(defaults: UserDefaults = .standard) {
        updateState(defaults) { $0.frozen = false }
    }

    // MARK: - SQLite

    /// Entry rows in a SwiftData store (`Entry` → table `ZENTRY`). Opens read-only; any
    /// failure is `.unknown`, never `.entries(0)`.
    static func entryCount(at url: URL) -> Count {
        guard FileManager.default.fileExists(atPath: url.path) else { return .unknown }
        var db: OpaquePointer?
        defer { sqlite3_close_v2(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return .unknown }
        sqlite3_busy_timeout(db, 2_000)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZENTRY", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return .unknown }
        return .entries(Int(sqlite3_column_int64(statement, 0)))
    }

    /// Consistent single-file copy via the online-backup API (safe while Core Data holds the
    /// source open, includes un-checkpointed WAL pages). The copy is left in rollback-journal
    /// mode so it opens read-only on its own.
    static func copyDatabase(from source: URL, to destination: URL, cancel: CancelFlag? = nil) -> Bool {
        removeDatabase(at: destination)
        var src: OpaquePointer?
        var dst: OpaquePointer?
        defer {
            sqlite3_close_v2(src)
            sqlite3_close_v2(dst)
        }
        guard sqlite3_open_v2(source.path, &src, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(dst, "main", src, "main") else { return false }
        // Small steps: the source is only locked during a step, and cancellation is honoured
        // between steps. A source write between steps restarts the copy, so cap the attempts.
        var result = SQLITE_OK
        var busyRetries = 0
        for _ in 0..<200_000 {
            if cancel?.isCancelled == true { result = SQLITE_INTERRUPT; break }
            result = sqlite3_backup_step(backup, 256)
            if result == SQLITE_OK { continue }
            guard result == SQLITE_BUSY || result == SQLITE_LOCKED, busyRetries < 40 else { break }
            busyRetries += 1
            sqlite3_sleep(100)
        }
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { return false }
        // The copy inherits the source's WAL-mode header; a WAL database can't be opened
        // read-only without its -shm file. Rollback mode makes it a self-contained file.
        return sqlite3_exec(dst, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK
    }

    /// A copy killed mid-way (suspension, crash) leaves a store-sized temp file behind.
    private static func removeLeftoverTemps(in dir: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasPrefix("journal-backup-") && name.contains(".tmp") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static func lastModified(_ storeURL: URL) -> Date? {
        [storeURL.path, storeURL.path + "-wal"]
            .compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date }
            .max()
    }

    static func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        removeDatabase(sidecarsOnlyAt: url)
    }

    private static func removeDatabase(sidecarsOnlyAt url: URL) {
        for suffix in ["-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
