import Foundation
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// What the Apple Watch app sends (3.1.8, item 9): a mood or a quick note. The watch never has the
/// journal key; the iPhone saves each item here, encrypted like anything written on it. A mood
/// becomes a mood check-in (and goes to Health if that's on: the watch is where it was logged, and
/// this phone is the only one that receives it); a note becomes an Unfiled entry.
@MainActor
enum WatchInbox {
    struct Item: Equatable {
        enum Kind: String { case mood, note }
        let id: String
        let kind: Kind
        let value: String
        let date: Date
    }

    static let handledKey = "mirror.watchInbox.handledIDs"
    /// Items that arrived while the journal key wasn't available (phone locked since restart):
    /// kept in memory and saved on the next try. A quit before then loses them (the watch already
    /// counted them as delivered).
    private(set) static var waiting: [Item] = []

    /// The watch's payload, or nil for anything malformed or unknown.
    nonisolated static func item(from payload: [String: Any]) -> Item? {
        guard let id = payload["id"] as? String, !id.isEmpty,
              let kind = (payload["kind"] as? String).flatMap(Item.Kind.init(rawValue:)),
              let value = (payload["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              let seconds = payload["date"] as? Double else { return nil }
        if kind == .mood, !MirrorTheme.moodOptions.contains(value) { return nil }
        // A clock far off on either device mustn't date an entry in the future.
        return Item(id: id, kind: kind, value: value, date: min(Date(timeIntervalSince1970: seconds), Date()))
    }

    /// Saves one item unless it was saved before. False when it must wait for the key.
    @discardableResult
    static func save(_ item: Item, in context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        var handled = defaults.stringArray(forKey: handledKey) ?? []
        guard !handled.contains(item.id) else { return true }
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: true) else { return false }
        switch item.kind {
        case .mood:
            context.insert(MoodCheckIn(mood: item.value, createdAt: item.date))
            HealthMoodWriter.writeCheckIn(mood: item.value, at: item.date)
        case .note:
            let entry = Entry(text: item.value, source: .typed)
            entry.createdAt = item.date
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: item.date)
            context.insert(entry)
            MoodAutoDetector.shared.detectIfNeeded(entry, context: context)
        }
        do { try context.save() } catch { return false }
        handled.append(item.id)
        defaults.set(Array(handled.suffix(500)), forKey: handledKey)
        mirrorApp.updateWidgetHeatmaps(context: context)
        return true
    }

    static func receive(_ payload: [String: Any], in context: ModelContext) {
        guard let item = item(from: payload) else { return }
        let saved = save(item, in: context)
        if !saved { waiting.append(item) }
        #if DEBUG
        // The kind only, never the text.
        NSLog("WatchInbox: %@ %@", item.kind.rawValue, saved ? "saved" : "waiting for the key")
        #endif
    }

    /// Saves what waited for the key; on every foreground.
    static func retryWaiting(in context: ModelContext) {
        waiting = waiting.filter { !save($0, in: context) }
    }

    #if os(iOS) && canImport(WatchConnectivity)
    private static let receiver = Receiver()

    /// Starts listening (app launch). Nothing happens without a paired watch with the app.
    static func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = receiver
        session.activate()
    }

    private final class Receiver: NSObject, WCSessionDelegate {
        // Called on WatchConnectivity's own queue, not the main actor.
        nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
        nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

        nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
            // userInfo is a property list: only these four plain values are read from it.
            let copy: [String: Any] = userInfo.filter { ["id", "kind", "value", "date"].contains($0.key) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard MirrorModelContainer.isStoreAvailable else { return }
                    WatchInbox.receive(copy, in: MirrorModelContainer.shared.mainContext)
                }
            }
        }
    }
    #endif
}
