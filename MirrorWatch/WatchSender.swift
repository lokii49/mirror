import Foundation
import WatchConnectivity

/// Sends what's logged on the watch to the iPhone. `transferUserInfo` queues moods and typed notes
/// and `transferFile` queues voice notes; the system delivers them when the phone can take them,
/// even if the watch app has closed meanwhile, and the phone saves them. The keys match
/// `WatchInbox` in the iPhone app.
///
/// Items logged before the session is activated (a cold launch) are held until it is, and a
/// transfer that fails is handed to the system again with the same id, so the phone saves it once.
/// Typed text is held in memory only. A voice note's audio waits in the watch's outbox folder
/// until its transfer finishes (`transferFile` reads the file while it sends), then it's deleted.
@MainActor
@Observable
final class WatchSender: NSObject {
    static let shared = WatchSender()

    enum Kind: String { case mood, note }

    /// Items handed to the system but not yet delivered, plus those held here.
    private(set) var waiting = 0
    /// Logged before activation, or failed and waiting to be sent again.
    private var held: [[String: Any]] = []
    /// Voice notes in the outbox that aren't with the system yet (by file name).
    private var heldVoice: Set<String> = []
    /// Times one item may fail and be re-sent before it waits for the next app open.
    private static let maxAttempts = 3
    /// Voice notes kept at most; a phone that's away for days mustn't fill the watch.
    static let outboxLimit = 20

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState == .activated {
            flush()
        } else {
            session.activate()
        }
        refreshWaiting()
    }

    /// The app opened: everything still waiting is tried again, including voice notes that hit the
    /// retry limit earlier.
    func resumeOnOpen() {
        heldVoice.formUnion(Self.outboxFiles().map(\.lastPathComponent))
        activate()
    }

    /// Queues one item for the iPhone. The id lets the phone ignore a repeat delivery.
    func send(_ kind: Kind, value: String, at date: Date = Date()) {
        guard WCSession.isSupported() else { return }
        held.append([
            "kind": kind.rawValue,
            "value": value,
            "date": date.timeIntervalSince1970,
            "id": UUID().uuidString,
        ])
        activate()
    }

    /// Moves a finished recording into the outbox and queues it. False when the outbox is full
    /// (the recording is deleted then; the screen says so).
    @discardableResult
    func sendVoice(from url: URL, duration: TimeInterval, at date: Date = Date()) -> Bool {
        guard WCSession.isSupported(), let outbox = Self.outbox else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        guard Self.outboxFiles().count < Self.outboxLimit else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        let id = UUID().uuidString
        let audio = outbox.appendingPathComponent(id).appendingPathExtension("m4a")
        let meta: [String: Any] = ["kind": "voice", "id": id, "date": date.timeIntervalSince1970, "duration": duration]
        do {
            try FileManager.default.moveItem(at: url, to: audio)
            let data = try PropertyListSerialization.data(fromPropertyList: meta, format: .binary, options: 0)
            try data.write(to: Self.sidecar(for: audio), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: audio)
            return false
        }
        heldVoice.insert(audio.lastPathComponent)
        activate()
        return true
    }

    /// Hands held items to the system once the session can take them.
    private func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let items = held
        held.removeAll()
        for item in items { session.transferUserInfo(item) }
        // Voice notes: everything in the outbox that the system isn't already sending (after a
        // relaunch only the outbox remembers them).
        let sending = Set(session.outstandingFileTransfers.map(\.file.fileURL.lastPathComponent))
        for audio in Self.outboxFiles() where !sending.contains(audio.lastPathComponent) {
            guard let meta = Self.metadata(for: audio) else {
                try? FileManager.default.removeItem(at: audio)
                continue
            }
            let attempts = meta["attempt"] as? Int ?? 0
            // Past the retry limit, only an app open (activate()) sends it again.
            if attempts >= Self.maxAttempts, !heldVoice.contains(audio.lastPathComponent) { continue }
            session.transferFile(audio, metadata: meta)
        }
        heldVoice.removeAll()
        refreshWaiting()
    }

    func refreshWaiting() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let sending = Set(session.outstandingFileTransfers.map(\.file.fileURL.lastPathComponent))
        let unsentVoice = Self.outboxFiles().filter { !sending.contains($0.lastPathComponent) }.count
        waiting = session.outstandingUserInfoTransfers.count + held.count + sending.count + unsentVoice
    }

    fileprivate func transferFailed(_ userInfo: [String: Any], error: Error) {
        var item = userInfo
        let attempts = (item["attempt"] as? Int ?? 0) + 1
        item["attempt"] = attempts
        held.append(item)
        // A lasting problem (iPhone app not installed, watch unpaired) mustn't loop: after a few
        // tries the item waits for the next time the app opens (`activate()` sends it again).
        if attempts < Self.maxAttempts { flush() } else { refreshWaiting() }
    }

    fileprivate func voiceFinished(_ audio: URL, error: Error?) {
        if error == nil {
            try? FileManager.default.removeItem(at: audio)
            try? FileManager.default.removeItem(at: Self.sidecar(for: audio))
        } else if var meta = Self.metadata(for: audio) {
            let attempts = (meta["attempt"] as? Int ?? 0) + 1
            meta["attempt"] = attempts
            if let data = try? PropertyListSerialization.data(fromPropertyList: meta, format: .binary, options: 0) {
                try? data.write(to: Self.sidecar(for: audio), options: .atomic)
            }
            if attempts < Self.maxAttempts { heldVoice.insert(audio.lastPathComponent); flush() }
        }
        refreshWaiting()
    }

    // MARK: - Outbox

    private static var outbox: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("VoiceOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func outboxFiles() -> [URL] {
        guard let outbox else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "m4a" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
    }

    private static func sidecar(for audio: URL) -> URL {
        audio.deletingPathExtension().appendingPathExtension("plist")
    }

    private static func metadata(for audio: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: sidecar(for: audio)) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}

extension WatchSender: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.flush()
            self.refreshWaiting()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        // userInfo is a property list of plain values; copied before leaving this queue.
        let userInfo = userInfoTransfer.userInfo
        let failure = error.map { $0 as NSError }
        Task { @MainActor in
            if let failure { self.transferFailed(userInfo, error: failure) }
            self.refreshWaiting()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let audio = fileTransfer.file.fileURL
        let failure = error.map { $0 as NSError }
        Task { @MainActor in self.voiceFinished(audio, error: failure) }
    }
}
