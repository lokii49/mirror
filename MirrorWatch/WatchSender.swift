import Foundation
import WatchConnectivity

/// Sends what's logged on the watch to the iPhone. `transferUserInfo` queues each item and delivers
/// it when the phone can take it, even if the watch app has closed meanwhile; the phone saves it.
/// The keys match `WatchInbox` in the iPhone app.
@MainActor
@Observable
final class WatchSender: NSObject {
    static let shared = WatchSender()

    enum Kind: String { case mood, note }

    /// Items handed to the system but not yet delivered to the iPhone.
    private(set) var waiting = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
        refreshWaiting()
    }

    /// Queues one item for the iPhone. The id lets the phone ignore a repeat delivery.
    func send(_ kind: Kind, value: String, at date: Date = Date()) {
        guard WCSession.isSupported() else { return }
        activate()
        WCSession.default.transferUserInfo([
            "kind": kind.rawValue,
            "value": value,
            "date": date.timeIntervalSince1970,
            "id": UUID().uuidString,
        ])
        refreshWaiting()
    }

    func refreshWaiting() {
        guard WCSession.isSupported() else { return }
        waiting = WCSession.default.outstandingUserInfoTransfers.count
    }
}

extension WatchSender: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refreshWaiting() }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in self.refreshWaiting() }
    }
}
