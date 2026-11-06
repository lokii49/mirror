import Foundation
import WatchConnectivity

/// Sends what's logged on the watch to the iPhone. `transferUserInfo` queues each item and delivers
/// it when the phone can take it, even if the watch app has closed meanwhile; the phone saves it.
/// The keys match `WatchInbox` in the iPhone app.
///
/// Items logged before the session is activated (a cold launch) are held until it is, and a
/// transfer that fails is handed to the system again with the same id, so the phone saves it once.
/// Those held items live in memory only: the watch never stores journal text itself.
@MainActor
@Observable
final class WatchSender: NSObject {
    static let shared = WatchSender()

    enum Kind: String { case mood, note }

    /// Items handed to the system but not yet delivered, plus those held here.
    private(set) var waiting = 0
    /// Logged before activation, or failed and waiting to be sent again.
    private var held: [[String: Any]] = []
    /// Times one item may fail and be re-sent before it waits for the next app open.
    private static let maxAttempts = 3

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

    /// Hands held items to the system once the session can take them.
    private func flush() {
        let session = WCSession.default
        guard session.activationState == .activated, !held.isEmpty else { return }
        let items = held
        held.removeAll()
        for item in items { session.transferUserInfo(item) }
        refreshWaiting()
    }

    func refreshWaiting() {
        guard WCSession.isSupported() else { return }
        waiting = WCSession.default.outstandingUserInfoTransfers.count + held.count
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
}
