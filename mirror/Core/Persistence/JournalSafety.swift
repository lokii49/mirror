import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData
#if os(iOS)
import UIKit
#endif

/// iCloud upload status plus the restore-from-device flow, for the entry list's banners.
///
/// **Upload status.** iOS never tells the app before the user turns iCloud off for it, so the
/// best warning is a standing one: "your latest changes haven't reached iCloud yet." That's
/// derived from NSPersistentCloudKitContainer's event stream (posted under SwiftData too):
/// changes are pending when the last `ModelContext` save is newer than the start of the last
/// export that succeeded.
///
/// **Restore.** When `LocalJournalBackup` has frozen a backup (the store collapsed), this
/// offers to put back the entries and mood check-ins the backup has and the journal doesn't.
/// While iCloud is available the offer waits for a successful import (or 3 minutes), so
/// "missing" means "not in iCloud either" and re-downloads rarely collide with restores.
/// Rows it inserts are remembered; if CloudKit later delivers an original with the same `id`,
/// only this device removes only its own copy (`reconcileRestoredCopies`). Removing
/// duplicates on every device could delete both copies. Entries listed in a synced
/// `JournalErasure` ("Delete Everything" on any device) are never offered or restored.
@MainActor @Observable
final class JournalSafety {
    static let shared = JournalSafety()

    struct RestoreOffer: Equatable {
        let entries: Int
        let checkIns: Int
    }

    private(set) var accountAvailable: Bool? = nil
    private(set) var lastLocalSave: Date? = UserDefaults.standard.object(forKey: JournalSafety.lastLocalSaveKey) as? Date
    private(set) var lastExportSucceededStart: Date? = UserDefaults.standard.object(forKey: JournalSafety.lastExportKey) as? Date
    private(set) var lastExportFailed = false
    private(set) var importSucceededThisLaunch = false
    private(set) var restoreOffer: RestoreOffer? = nil
    private(set) var isRestoring = false

    private static let lastLocalSaveKey = "mirror.journalSafety.lastLocalSave"
    private static let lastExportKey = "mirror.journalSafety.lastExportSucceededStart"
    /// Restore waits this long for a successful import before offering anyway (an import
    /// that never succeeds — offline, quota, schema — must not hide the offer forever).
    private static let importGrace: TimeInterval = 180
    /// Restored-row bookkeeping is kept this long; past it, originals aren't coming.
    private static let restoredBookkeepingLifetime: TimeInterval = 30 * 24 * 3600

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private let launchedAt = Date()

    private init() {}

    // MARK: - Derived

    var hasPendingChanges: Bool {
        guard let lastLocalSave else { return false }
        return lastLocalSave > (lastExportSucceededStart ?? .distantPast)
    }

    /// The "not backed up yet" banner: iCloud is on, there are changes it doesn't have, and
    /// either the last upload failed or they've waited long enough not to be a normal
    /// in-flight upload. `now` comes from the view's TimelineView.
    func showsNotBackedUp(now: Date) -> Bool {
        guard accountAvailable == true, hasPendingChanges, let lastLocalSave else { return false }
        return lastExportFailed || now.timeIntervalSince(lastLocalSave) > 120
    }

    // MARK: - Lifecycle

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let type = event.type, succeeded = event.succeeded, started = event.startDate, ended = event.endDate != nil
            #if DEBUG
            // Event metadata only — never record or entry content.
            let code = (event.error as NSError?).map { " error \($0.domain) \($0.code)" } ?? ""
            print("[JournalSafety] cloudkit \(type.rawValue) ended=\(ended) ok=\(succeeded)\(code)")
            #endif
            MainActor.assumeIsolated {
                self?.handleEvent(type: type, succeeded: succeeded, startDate: started, ended: ended)
            }
        })
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            // An autosave that changed nothing triggers no upload; counting it would leave a
            // "not backed up" banner waiting for an export that never comes.
            let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
            let changed = keys.contains { key in
                (note.userInfo?[key.rawValue] as? [PersistentIdentifier]).map { !$0.isEmpty } ?? false
            }
            guard changed else { return }
            MainActor.assumeIsolated { self?.recordLocalSave() }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccountStatus() }
        })
        refreshAccountStatus()
    }

    /// Foreground hook: account may have changed in Settings while we were away.
    func appDidBecomeActive() {
        refreshAccountStatus()
        reconcileRestoredCopies()
        refreshRestoreOffer()
    }

    /// Background hook: refresh the device backup off the main thread.
    func appDidEnterBackground() {
        guard let storeURL = LocalJournalBackup.liveStoreURL() else { return }
        #if os(iOS)
        let cancel = LocalJournalBackup.CancelFlag()
        let finished = DispatchSemaphore(value: 0)
        let task = BackgroundTaskOnce()
        task.begin {
            // Out of time: stop the copy and wait (briefly) for it to close its SQLite
            // connections, so no lock on the app-group store is held across suspension.
            cancel.cancel()
            _ = finished.wait(timeout: .now() + 2)
        }
        Task.detached(priority: .utility) {
            LocalJournalBackup.snapshotIfNeeded(storeURL: storeURL, cancel: cancel)
            finished.signal()
            task.end()
        }
        #else
        Task.detached(priority: .utility) {
            LocalJournalBackup.snapshotIfNeeded(storeURL: storeURL)
        }
        #endif
    }

    private func refreshAccountStatus() {
        #if DEBUG
        // Unsigned screenshot builds have no iCloud container; CKContainer.default() throws an ObjC exception.
        if ProcessInfo.processInfo.arguments.contains("--macSnapshot") { return }
        #endif
        Task {
            let status = try? await CKContainer.default().accountStatus()
            accountAvailable = status.map { $0 == .available }
            refreshRestoreOffer()
        }
    }

    private func recordLocalSave() {
        let now = Date()
        lastLocalSave = now
        UserDefaults.standard.set(now, forKey: Self.lastLocalSaveKey)
    }

    private func handleEvent(type: NSPersistentCloudKitContainer.EventType, succeeded: Bool, startDate: Date, ended: Bool) {
        guard ended else { return }
        switch type {
        case .export:
            if succeeded {
                lastExportFailed = false
                if startDate > (lastExportSucceededStart ?? .distantPast) {
                    lastExportSucceededStart = startDate
                    UserDefaults.standard.set(startDate, forKey: Self.lastExportKey)
                }
            } else {
                lastExportFailed = true
            }
        case .import:
            if succeeded {
                importSucceededThisLaunch = true
                reconcileRestoredCopies()
                refreshRestoreOffer()
            }
        default:
            break
        }
    }

    // MARK: - Restore

    private var offerTask: Task<Void, Never>?

    /// Recomputes `restoreOffer`, debounced: imports arrive in bursts during a re-download,
    /// and each recompute copies and opens the backup (off the main thread).
    func refreshRestoreOffer() {
        offerTask?.cancel()
        offerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.computeRestoreOffer()
        }
    }

    private func computeRestoreOffer() async {
        guard let container, !isRestoring else { return }
        guard LocalJournalBackup.loadState().frozen else {
            restoreOffer = nil
            return
        }
        // Account status unknown yet: wait. iCloud on: wait for an import (or the grace).
        guard let accountAvailable else { return }
        if accountAvailable, !importSucceededThisLaunch, Date().timeIntervalSince(launchedAt) < Self.importGrace {
            scheduleGraceRecheck()
            return
        }
        guard let backupIDs = await Task.detached(priority: .utility, operation: { try? Self.backupIDs() }).value,
              let journalEntryIDs = try? Self.ids(of: Entry.self, \.id, in: container.mainContext),
              let journalCheckInIDs = try? Self.ids(of: MoodCheckIn.self, \.id, in: container.mainContext)
        else { return }
        // Entries a "Delete Everything" (on any device) erased are never offered back.
        let erased = JournalErasure.allErasedEntryIDs(in: container.mainContext)
        let entries = backupIDs.entries.subtracting(journalEntryIDs).subtracting(erased).count
        let checkIns = backupIDs.checkIns.subtracting(journalCheckInIDs).count
        if entries == 0 && checkIns == 0 {
            // Everything came back (re-download finished): nothing to offer, resume snapshots.
            LocalJournalBackup.unfreeze()
            restoreOffer = nil
        } else {
            restoreOffer = RestoreOffer(entries: entries, checkIns: checkIns)
        }
    }

    /// IDs only — a full fetch would fault in every entry's photo and voice blobs.
    private static func ids<Model: PersistentModel>(of _: Model.Type, _ id: KeyPath<Model, UUID>, in context: ModelContext) throws -> Set<UUID> {
        var descriptor = FetchDescriptor<Model>()
        descriptor.propertiesToFetch = [id]
        return Set(try context.fetch(descriptor).map { $0[keyPath: id] })
    }

    nonisolated private static func backupIDs() throws -> (entries: Set<UUID>, checkIns: Set<UUID>) {
        let backup = try openBackupCopy()
        defer { backup.cleanup() }
        var entries = FetchDescriptor<Entry>()
        entries.propertiesToFetch = [\.id]
        var checkIns = FetchDescriptor<MoodCheckIn>()
        checkIns.propertiesToFetch = [\.id]
        return (Set(try backup.context.fetch(entries).map(\.id)), Set(try backup.context.fetch(checkIns).map(\.id)))
    }

    private var graceRecheckScheduled = false
    private func scheduleGraceRecheck() {
        guard !graceRecheckScheduled else { return }
        graceRecheckScheduled = true
        let remaining = max(1, Self.importGrace - Date().timeIntervalSince(launchedAt))
        Task {
            try? await Task.sleep(for: .seconds(remaining))
            graceRecheckScheduled = false
            refreshRestoreOffer()
        }
    }

    func restore() {
        guard let container, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        let context = container.mainContext
        guard let backup = try? Self.openBackupCopy() else { return }
        defer { backup.cleanup() }
        guard let missing = try? missingFromJournal(context: context, backup: backup.context) else { return }

        let entries = missing.entries.map { Entry.restoredCopy(of: $0) }
        let checkIns = missing.checkIns.map { MoodCheckIn.restoredCopy(of: $0) }
        entries.forEach(context.insert)
        checkIns.forEach(context.insert)
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        LocalJournalBackup.updateState { state in
            state.restoredEntryIDs += entries.map(\.persistentModelID)
            state.restoredCheckInIDs += checkIns.map(\.persistentModelID)
            state.restoredAt = Date()
            state.frozen = false
        }
        restoreOffer = nil
    }

    /// User declined the offer: drop the frozen backup so the next background snapshot starts
    /// over from the journal as it is now.
    func discardRestoreOffer() {
        let restored = LocalJournalBackup.loadState()
        LocalJournalBackup.deleteBackup()
        LocalJournalBackup.updateState { state in
            state.restoredEntryIDs = restored.restoredEntryIDs
            state.restoredCheckInIDs = restored.restoredCheckInIDs
            state.restoredAt = restored.restoredAt
        }
        restoreOffer = nil
    }

    /// "Delete Everything" on this device: drop the local backup. Other devices are covered
    /// by the synced `JournalErasure` the caller inserted.
    func journalWasErased() {
        LocalJournalBackup.deleteBackup()
        restoreOffer = nil
    }

    /// Removes this device's restored copy of any entry/check-in whose original CloudKit has
    /// since delivered. Never touches rows this device didn't restore.
    func reconcileRestoredCopies() {
        guard let container else { return }
        let state = LocalJournalBackup.loadState()
        guard !state.restoredEntryIDs.isEmpty || !state.restoredCheckInIDs.isEmpty else { return }
        if let at = state.restoredAt, Date().timeIntervalSince(at) > Self.restoredBookkeepingLifetime {
            LocalJournalBackup.updateState { $0.restoredEntryIDs = []; $0.restoredCheckInIDs = []; $0.restoredAt = nil }
            return
        }
        let context = container.mainContext
        let keptEntries = reconcile(state.restoredEntryIDs, of: Entry.self, uuid: \.id, context: context)
        let keptCheckIns = reconcile(state.restoredCheckInIDs, of: MoodCheckIn.self, uuid: \.id, context: context)
        guard keptEntries != state.restoredEntryIDs || keptCheckIns != state.restoredCheckInIDs else { return }
        do {
            try context.save()
            LocalJournalBackup.updateState {
                $0.restoredEntryIDs = keptEntries
                $0.restoredCheckInIDs = keptCheckIns
            }
        } catch {
            context.rollback()
        }
    }

    /// Returns the restored IDs still worth tracking; deletes restored copies that now have
    /// an original beside them.
    private func reconcile<Model: PersistentModel>(
        _ restored: [PersistentIdentifier],
        of _: Model.Type,
        uuid: KeyPath<Model, UUID>,
        context: ModelContext
    ) -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<Model>()
        descriptor.propertiesToFetch = [uuid]
        guard !restored.isEmpty, let all = try? context.fetch(descriptor) else { return restored }
        let restoredSet = Set(restored)
        var originalsByUUID: [UUID: Int] = [:]
        for model in all where !restoredSet.contains(model.persistentModelID) {
            originalsByUUID[model[keyPath: uuid], default: 0] += 1
        }
        let present = Dictionary(all.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [PersistentIdentifier] = []
        for id in restored {
            guard let copy = present[id] else { continue }  // user deleted it — stop tracking
            if originalsByUUID[copy[keyPath: uuid], default: 0] > 0 {
                context.delete(copy)
            } else {
                kept.append(id)
            }
        }
        return kept
    }

    // MARK: - Reading the backup

    private struct BackupCopy {
        let context: ModelContext
        let url: URL
        func cleanup() { LocalJournalBackup.removeDatabase(at: url) }
    }

    /// Opens a temp copy, never the backup itself: a newer schema would migrate the file in place.
    nonisolated private static func openBackupCopy() throws -> BackupCopy {
        let source = LocalJournalBackup.backupURL
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("journal-restore-\(UUID().uuidString).store")
        try FileManager.default.copyItem(at: source, to: temp)
        let configuration = ModelConfiguration("JournalRestore", schema: MirrorModelContainer.schema, url: temp, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [configuration])
            return BackupCopy(context: ModelContext(container), url: temp)
        } catch {
            LocalJournalBackup.removeDatabase(at: temp)
            throw error
        }
    }

    private func missingFromJournal(context: ModelContext, backup: ModelContext) throws -> (entries: [Entry], checkIns: [MoodCheckIn]) {
        let entryIDs = try Self.ids(of: Entry.self, \.id, in: context)
            .union(JournalErasure.allErasedEntryIDs(in: context))
        let checkInIDs = try Self.ids(of: MoodCheckIn.self, \.id, in: context)
        let entries = try backup.fetch(FetchDescriptor<Entry>()).filter { !entryIDs.contains($0.id) }
        let checkIns = try backup.fetch(FetchDescriptor<MoodCheckIn>()).filter { !checkInIDs.contains($0.id) }
        return (entries, checkIns)
    }
}

#if os(iOS)
/// A UIKit background task that is ended exactly once, from whichever side gets there first
/// (the work finishing, or the expiration handler).
private final class BackgroundTaskOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var id = UIBackgroundTaskIdentifier.invalid

    @MainActor
    func begin(onExpiration: @escaping @Sendable () -> Void) {
        let started = UIApplication.shared.beginBackgroundTask(withName: "LocalJournalBackup") { [self] in
            onExpiration()
            end()
        }
        lock.withLock { id = started }
    }

    func end() {
        let ending: UIBackgroundTaskIdentifier = lock.withLock {
            defer { id = .invalid }
            return id
        }
        guard ending != .invalid else { return }
        // The expiration handler runs on main and must end the task before it returns.
        if Thread.isMainThread {
            MainActor.assumeIsolated { UIApplication.shared.endBackgroundTask(ending) }
        } else {
            DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(ending) }
        }
    }
}
#endif
