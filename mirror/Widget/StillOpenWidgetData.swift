import Foundation
import CryptoKit

/// The Still Open widget's data in the app group. Built into the app and the widget extension.
///
/// The app writes a short snapshot of unticked checklist items (`WidgetBridge.syncStillOpen`);
/// the widget never opens the journal store or the journal key. A tick made on the widget is
/// queued here, shown ticked at once, and applied to its entry the next time the app is active
/// (`StillOpenWidgetTicks.applyPending`), only if that line is still the same checklist item.
/// A tick carries a hash of the line's words, not the words.
nonisolated enum StillOpenWidgetData {
    static let snapshotKey = "widget.stillOpen.snapshot"
    static let ticksKey = "widget.stillOpen.ticks"
    static let widgetKind = "MirrorStillOpenWidget"

    /// Items kept in the snapshot (the large widget shows 6 and "+N more").
    static let maxItems = 8
    /// Characters of each item kept for display.
    static let maxChars = 80

    struct Item: Codable, Hashable, Identifiable, Sendable {
        let entryID: UUID
        /// Paragraph index in the entry (its style index).
        let index: Int
        /// Clipped to `maxChars` for display.
        let text: String
        /// `lineHash` of the full line, so a tick can be checked against the entry later.
        let hash: String
        /// The entry's day.
        let day: Date
        var id: String { StillOpenWidgetData.itemID(entryID: entryID, index: index) }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        var items: [Item]
        /// Every open item in the journal, not only the ones kept here.
        var total: Int
    }

    struct Tick: Codable, Hashable, Sendable {
        let entryID: UUID
        let index: Int
        let hash: String
        var id: String { StillOpenWidgetData.itemID(entryID: entryID, index: index) }
    }

    static func itemID(entryID: UUID, index: Int) -> String { "\(entryID.uuidString)#\(index)" }

    /// SHA-256 of the line's shown words, hex. Same input as `OpenChecklistItems.Line.text`.
    static func lineHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func clip(_ text: String) -> String {
        guard text.count > maxChars else { return text }
        let cut = text.prefix(maxChars)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxChars / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetShared.appGroupID) }

    static func snapshot(in defaults: UserDefaults? = defaults) -> Snapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// True when the stored snapshot changed.
    @discardableResult
    static func write(_ snapshot: Snapshot, in defaults: UserDefaults? = defaults) -> Bool {
        guard snapshot != self.snapshot(in: defaults), let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults?.set(data, forKey: snapshotKey)
        return true
    }

    static func ticks(in defaults: UserDefaults? = defaults) -> [Tick] {
        guard let data = defaults?.data(forKey: ticksKey) else { return [] }
        return (try? JSONDecoder().decode([Tick].self, from: data)) ?? []
    }

    static func setTicks(_ ticks: [Tick], in defaults: UserDefaults? = defaults) {
        if ticks.isEmpty {
            defaults?.removeObject(forKey: ticksKey)
        } else if let data = try? JSONEncoder().encode(ticks) {
            defaults?.set(data, forKey: ticksKey)
        }
    }

    /// The widget's tap: tick an item, or untick one it ticked before the app applied it.
    static func toggle(_ tick: Tick, in defaults: UserDefaults? = defaults) {
        var current = ticks(in: defaults)
        if let found = current.firstIndex(where: { $0.id == tick.id }) {
            current.remove(at: found)
        } else {
            current.append(tick)
        }
        setTicks(current, in: defaults)
    }
}
