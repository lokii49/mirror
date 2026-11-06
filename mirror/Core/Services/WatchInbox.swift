import Foundation
import Security
import SwiftData
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
        enum Kind: String, Codable { case mood, note }
        let id: String
        let kind: Kind
        let value: String
        let date: Date
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
    static let pendingLimit = 200

    /// The items waiting for the key, oldest first.
    static var waiting: [Item] { pending() }

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

    /// Saves one item unless it was saved before. False when it must wait for the key or the save
    /// failed; nothing of it stays behind in the context then, so a retry can't save it twice.
    @discardableResult
    static func save(_ item: Item, in context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        var handled = defaults.stringArray(forKey: handledKey) ?? []
        guard !handled.contains(item.id) else { return true }
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: true) else { return false }
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
        var items = pending()
        guard !items.isEmpty else { return }
        while let first = items.first, save(first, in: context, defaults: defaults) {
            items.removeFirst()
        }
        storePending(items)
    }

    /// Clears the waiting items (Delete Everything).
    static func erasePending() {
        KeychainManager.delete(account: pendingAccount)
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
        guard let data = try? JSONEncoder().encode(Array(items.suffix(pendingLimit))) else { return }
        KeychainManager.save(data: data, account: pendingAccount,
                             accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    #if os(iOS) && canImport(WatchConnectivity)
    private static let receiver = Receiver()

    /// Starts listening (app launch). Nothing happens without a paired watch with the app.
    static func start() {
        guard WCSession.isSupported() else { return }
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
