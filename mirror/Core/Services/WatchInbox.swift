import Foundation
import Security
import SwiftData
#if canImport(Speech)
import Speech
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// What the Apple Watch app sends (3.1.8, item 9): a mood or a quick note. The watch never has the
/// journal key; the iPhone saves each item here, encrypted like anything written on it. A mood
/// becomes a mood check-in (and goes to Health if that's on: the watch is where it was logged, and
/// this phone is the only one that receives it); a note becomes an Unfiled entry.
@MainActor
enum WatchInbox {
    struct Item: Equatable, Codable {
        /// `voice` (3.1.8 build 43): `value` is the audio's file name in `voiceDirectory`. The
        /// pending list is Keychain JSON; an optional field and a new case decode alongside what
        /// build 42 stored (moods and notes only).
        enum Kind: String, Codable { case mood, note, voice }
        let id: String
        let kind: Kind
        let value: String
        let date: Date
        /// A voice note's length in seconds.
        var duration: Double? = nil
    }

    static let handledKey = "mirror.watchInbox.handledIDs"
    /// Items that arrived while the journal key couldn't be read. The key is readable only while
    /// the phone is unlocked, and WatchConnectivity wakes the app for a watch item with the phone
    /// in a pocket, so this is the usual case, not an edge one. They wait in a Keychain item this
    /// device can write while locked (after the first unlock since a restart), so a quit doesn't
    /// lose them: the watch already counted them as delivered.
    /// A task-local so tests use their own Keychain item, never the app's.
    @TaskLocal static var pendingAccount = "mirror.watchInbox.pending"
    /// The newest items kept when far more pile up than anyone logs between unlocks.
    nonisolated static let pendingLimit = 200

    /// Where WatchConnectivity's own queue writes each item the moment it arrives, before the
    /// delegate method returns (the watch counts it as delivered then). The main actor moves them
    /// into the waiting list (`mergeInbound`), so an app stopped in between loses nothing.
    nonisolated static let inboundAccount = "mirror.watchInbox.pending.inbound"
    nonisolated private static let inboundLock = NSLock()

    /// Writes one arriving item to `inboundAccount` (any thread). Does nothing when the Keychain
    /// can't be read (before the first unlock since a restart): rewriting then could drop items
    /// already there, and the main-actor path still queues it.
    nonisolated static func stageInbound(_ item: Item, account: String = inboundAccount) {
        inboundLock.lock()
        defer { inboundLock.unlock() }
        var items: [Item] = []
        switch KeychainManager.read(account: account) {
        case .found(let data): items = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
        case .missing: break
        case .failure: return
        }
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        guard let data = try? JSONEncoder().encode(Array(items.suffix(pendingLimit))) else { return }
        KeychainManager.save(data: data, account: account, accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    /// Moves staged items into the waiting list, oldest first; the staged copy is removed only
    /// once every one of them is in the list.
    static func mergeInbound(defaults: UserDefaults = .standard) {
        let account = pendingAccount + ".inbound"
        inboundLock.lock()
        defer { inboundLock.unlock() }
        guard let data = KeychainManager.read(account: account).data,
              let staged = try? JSONDecoder().decode([Item].self, from: data), !staged.isEmpty else { return }
        for item in staged { addPending(item) }
        let waitingIDs = Set(pending().map(\.id))
        let handled = Set(defaults.stringArray(forKey: handledKey) ?? [])
        if staged.allSatisfy({ waitingIDs.contains($0.id) || handled.contains($0.id) }) {
            KeychainManager.delete(account: account)
        }
    }

    /// The items waiting for the key, oldest first.
    static var waiting: [Item] { pending() }

    /// The watch's payload, or nil for anything malformed or unknown.
    nonisolated static func item(from payload: [String: Any]) -> Item? {
        guard let id = payload["id"] as? String, !id.isEmpty,
              let kind = (payload["kind"] as? String).flatMap(Item.Kind.init(rawValue:)),
              let value = (payload["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              let seconds = payload["date"] as? Double else { return nil }
        if kind == .mood, !MirrorTheme.moodOptions.contains(value) { return nil }
        // Voice notes arrive only as files (`receiveVoice`); a message naming one is never trusted
        // with a file name.
        if kind == .voice { return nil }
        // A clock far off on either device mustn't date an entry in the future.
        return Item(id: id, kind: kind, value: value, date: min(Date(timeIntervalSince1970: seconds), Date()))
    }

    /// Saves one item unless it was saved before. False when it must wait for the key or the save
    /// failed; nothing of it stays behind in the context then, so a retry can't save it twice.
    @discardableResult
    static func save(_ item: Item, in context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        var handled = defaults.stringArray(forKey: handledKey) ?? []
        guard !handled.contains(item.id) else {
            // A repeat delivery of a voice note leaves a second copy of the audio behind.
            if item.kind == .voice { removeVoiceFile(item.value) }
            return true
        }
        #if os(iOS)
        // A locked phone can still hold the journal key in memory, but the waiting audio
        // ("complete unless open") can't be read then: wait for the unlock instead of reading
        // the file as gone.
        guard UIApplication.shared.isProtectedDataAvailable else { return false }
        // A background wake (a watch item with the app not open) never mints a journal key: on a
        // new phone iCloud Keychain may not have delivered the existing one yet, and a new key
        // would split the key set. The foreground retry may create it, as a first Write save does.
        let mayCreateKey = UIApplication.shared.applicationState != .background || mirrorApp.isUnitTestHost
        #else
        let mayCreateKey = true
        #endif
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: mayCreateKey) else { return false }
        switch item.kind {
        case .mood:
            let checkIn = MoodCheckIn(mood: item.value, createdAt: item.date)
            context.insert(checkIn)
            do { try context.save() } catch {
                context.delete(checkIn)
                return false
            }
            // To Health only once the check-in is saved: the watch is where it was logged, and
            // this phone is the only one that receives it.
            HealthMoodWriter.writeCheckIn(mood: item.value, at: item.date)
        case .note:
            let entry = Entry(text: item.value, source: .typed)
            entry.createdAt = item.date
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: item.date)
            context.insert(entry)
            do { try context.save() } catch {
                context.delete(entry)
                return false
            }
            MoodAutoDetector.shared.detectIfNeeded(entry, context: context)
        case .voice:
            let file = voiceFileURL(named: item.value)
            let audio = file.flatMap { try? Data(contentsOf: $0) }
            // There but unreadable (protection, a passing I/O error): try again later, never drop it.
            if audio == nil, let file, FileManager.default.fileExists(atPath: file.path) { return false }
            guard let audio else {
                // The audio is gone (Delete Everything ran meanwhile): nothing left to save.
                handled.append(item.id)
                defaults.set(Array(handled.suffix(500)), forKey: handledKey)
                return true
            }
            let entry = Entry(text: "", source: .voice)
            entry.createdAt = item.date
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: item.date)
            entry.voiceNoteData = audio
            entry.voiceNoteDuration = item.duration ?? 0
            context.insert(entry)
            do { try context.save() } catch {
                context.delete(entry)
                return false
            }
            removeVoiceFile(item.value)
            transcribe(entry, audio: audio, in: context)
        }
        handled.append(item.id)
        defaults.set(Array(handled.suffix(500)), forKey: handledKey)
        mirrorApp.updateWidgetHeatmaps(context: context)
        return true
    }

    static func receive(_ payload: [String: Any], in context: ModelContext, defaults: UserDefaults = .standard) {
        guard let item = item(from: payload) else { return }
        // Anything older still waiting goes first, so items keep the order they were logged in.
        retryWaiting(in: context, defaults: defaults)
        let saved = pending().isEmpty && save(item, in: context, defaults: defaults)
        if !saved { addPending(item) }
        #if DEBUG
        // The kind only, never the text.
        NSLog("WatchInbox: %@ %@", item.kind.rawValue, saved ? "saved" : "waiting for the key")
        #endif
    }

    /// Saves what waited for the key: on every foreground, when protected data becomes available,
    /// and before each new item. Stops at the first one that still can't be saved.
    static func retryWaiting(in context: ModelContext, defaults: UserDefaults = .standard) {
        mergeInbound(defaults: defaults)
        var items = pending()
        guard !items.isEmpty else { return }
        while let first = items.first, save(first, in: context, defaults: defaults) {
            items.removeFirst()
        }
        storePending(items)
    }

    /// Clears the waiting items and their audio (Delete Everything).
    static func erasePending() {
        KeychainManager.delete(account: pendingAccount)
        KeychainManager.delete(account: pendingAccount + ".inbound")
        if let dir = voiceDirectory { try? FileManager.default.removeItem(at: dir) }
    }

    /// Keeps an item for the next retry without trying to save it (the store isn't open).
    static func queueForLater(_ item: Item) {
        addPending(item)
    }

    // MARK: - Voice notes

    /// A voice note from the watch, already copied into `voiceDirectory` as `<id>.m4a`.
    static func receiveVoice(id: String, date: Date, duration: Double, in context: ModelContext,
                             defaults: UserDefaults = .standard) {
        let item = Item(id: id, kind: .voice, value: "\(id).m4a", date: min(date, Date()), duration: max(0, duration))
        retryWaiting(in: context, defaults: defaults)
        let saved = pending().isEmpty && save(item, in: context, defaults: defaults)
        if !saved { addPending(item) }
        #if DEBUG
        NSLog("WatchInbox: voice %@", saved ? "saved" : "waiting for the key")
        #endif
    }

    /// Where watch audio waits until it's saved into an entry. On iOS the files are protected
    /// "complete unless open": they can be written while the phone is locked (a watch note arrives
    /// in a pocket) and read only once it's unlocked, which is also when the journal key is there.
    /// The audio isn't sealed with the journal key yet (the key can't be read while locked), so the
    /// folder stays out of device backups: a saved entry reaches a backup only as ciphertext.
    nonisolated static var voiceDirectory: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var dir = support.appendingPathComponent("WatchVoiceInbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            #if os(iOS)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
            #else
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            #endif
        }
        // Every time, not only on creation: the folder already exists on TestFlight builds 43-49.
        if (try? dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) != true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    /// Audio files left in `voiceDirectory` with no waiting item (the app was stopped between the
    /// copy and queueing it). Queued again so the note isn't lost (the watch has already deleted
    /// its copy), or removed if it was saved before. Runs before WatchConnectivity activates, so
    /// no transfer can be mid-copy.
    static func adoptOrphanedVoiceFiles(defaults: UserDefaults = .standard) {
        // Staged arrivals first: their audio isn't orphaned, and they keep their real date and length.
        mergeInbound(defaults: defaults)
        guard let dir = voiceDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let waitingIDs = Set(pending().map(\.id))
        let handled = Set(defaults.stringArray(forKey: handledKey) ?? [])
        for file in files where file.pathExtension == "m4a" {
            let id = file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: id) != nil, !waitingIDs.contains(id) else { continue }
            if handled.contains(id) {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            addPending(Item(id: id, kind: .voice, value: "\(id).m4a", date: min(created, Date()), duration: nil))
        }
    }

    /// The audio file for an id: only a UUID becomes a file name, so a message can't point
    /// anywhere else.
    nonisolated static func voiceFileURL(id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return voiceDirectory?.appendingPathComponent("\(id).m4a")
    }

    private static func voiceFileURL(named name: String) -> URL? {
        guard name.hasSuffix(".m4a") else { return nil }
        return voiceFileURL(id: String(name.dropLast(4)))
    }

    private static func removeVoiceFile(_ name: String) {
        if let url = voiceFileURL(named: name) { try? FileManager.default.removeItem(at: url) }
    }

    /// The transcript, as the iPhone's own recorder makes it, once speech recognition is already
    /// allowed (a background wake can't ask). Otherwise, or if it fails, the entry is marked so
    /// the entry's Retry button offers it again; the audio is saved either way.
    private static func transcribe(_ entry: Entry, audio: Data, in context: ModelContext) {
        #if os(iOS) && canImport(Speech)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            entry.voiceNoteTranscriptionFailed = true
            try? context.save()
            return
        }
        // The language picked in Settings, as Write's own voice notes use it.
        let preferred = UserDefaults.standard.string(forKey: "transcriptionLanguage").flatMap { $0.isEmpty ? nil : $0 }
        // A watch item usually wakes the app in the background, with seconds to run: ask for time,
        // and if it runs out first, mark the entry so its Retry button offers the transcript.
        let backgroundTask = TranscriptBackgroundTask()
        backgroundTask.id = UIApplication.shared.beginBackgroundTask(withName: "mirror.watchVoiceTranscript") {
            Task { @MainActor in
                if !entry.isDeleted, (entry.voiceNoteTranscript ?? "").isEmpty {
                    entry.voiceNoteTranscriptionFailed = true
                    try? context.save()
                }
                backgroundTask.end()
            }
        }
        Task { @MainActor in
            defer { backgroundTask.end() }
            do {
                let result = try await VoiceTranscriptionService.transcribe(audioData: audio, preferredLocaleId: preferred)
                guard !entry.isDeleted else { return }
                WriteView.applyTranscription(result, to: entry, atIndex: 0)
                entry.voiceNoteTranscriptionFailed = (entry.voiceNoteTranscript ?? "").isEmpty
            } catch {
                guard !entry.isDeleted else { return }
                entry.voiceNoteTranscriptionFailed = true
            }
            try? context.save()
            MoodAutoDetector.shared.detectIfNeeded(entry, context: context)
            mirrorApp.updateWidgetHeatmaps(context: context)
        }
        #endif
    }

    // MARK: - Pending store

    private static func pending() -> [Item] {
        guard let data = KeychainManager.read(account: pendingAccount).data else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private static func addPending(_ item: Item) {
        var items = pending()
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        storePending(items)
    }

    private static func storePending(_ items: [Item]) {
        guard !items.isEmpty else {
            KeychainManager.delete(account: pendingAccount)
            return
        }
        // Items past the limit are dropped for good, so their audio goes with them.
        for dropped in items.dropLast(pendingLimit) where dropped.kind == .voice { removeVoiceFile(dropped.value) }
        guard let data = try? JSONEncoder().encode(Array(items.suffix(pendingLimit))) else { return }
        KeychainManager.save(data: data, account: pendingAccount,
                             accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    #if os(iOS) && canImport(WatchConnectivity)
    private static let receiver = Receiver()

    /// Starts listening (app launch). Nothing happens without a paired watch with the app.
    static func start() {
        guard WCSession.isSupported() else { return }
        adoptOrphanedVoiceFiles()
        let session = WCSession.default
        session.delegate = receiver
        session.activate()
        // The key becomes readable when the phone unlocks, which can happen with the app in
        // the background (no foreground to retry on).
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard MirrorModelContainer.isStoreAvailable else { return }
                retryWaiting(in: MirrorModelContainer.shared.mainContext)
            }
        }
    }

    private final class Receiver: NSObject, WCSessionDelegate {
        // Called on WatchConnectivity's own queue, not the main actor.
        nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
        nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

        /// A voice note. The file is gone when this returns, so it's copied here, on WatchConnectivity's
        /// queue, before anything else.
        nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
            let meta = file.metadata ?? [:]
            guard (meta["kind"] as? String) == "voice", let id = meta["id"] as? String,
                  let seconds = meta["date"] as? Double,
                  let destination = WatchInbox.voiceFileURL(id: id) else { return }
            let duration = meta["duration"] as? Double ?? 0
            // Five minutes of AAC is about 3 MB; anything far larger isn't a watch note.
            let size = (try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size < 50_000_000 else { return }
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.copyItem(at: file.fileURL, to: destination)) != nil else { return }
            // A copy can keep the source file's protection class instead of the folder's.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen],
                                                   ofItemAtPath: destination.path)
            // Recorded before returning: once this returns the watch has deleted its copy.
            WatchInbox.stageInbound(.init(id: id, kind: .voice, value: "\(id).m4a",
                                          date: min(Date(timeIntervalSince1970: seconds), Date()), duration: duration))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let date = Date(timeIntervalSince1970: seconds)
                    guard MirrorModelContainer.isStoreAvailable else {
                        WatchInbox.queueForLater(.init(id: id, kind: .voice, value: "\(id).m4a", date: min(date, Date()), duration: duration))
                        return
                    }
                    WatchInbox.receiveVoice(id: id, date: date, duration: duration, in: MirrorModelContainer.shared.mainContext)
                }
            }
        }

        nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
            // userInfo is a property list: only these four plain values are read from it.
            let copy: [String: Any] = userInfo.filter { ["id", "kind", "value", "date"].contains($0.key) }
            // Recorded before returning: the watch counts it as delivered once this returns.
            if let item = WatchInbox.item(from: copy) { WatchInbox.stageInbound(item) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard MirrorModelContainer.isStoreAvailable else {
                        // The journal can't open yet: keep the item for the next retry.
                        if let item = WatchInbox.item(from: copy) { WatchInbox.queueForLater(item) }
                        return
                    }
                    WatchInbox.receive(copy, in: MirrorModelContainer.shared.mainContext)
                }
            }
        }
    }
    #endif
}

#if os(iOS)
/// One background task for a watch voice note's transcript, ended once (by the finished pass or
/// by its expiration handler, whichever comes first). Main actor only.
@MainActor
private final class TranscriptBackgroundTask {
    var id: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
