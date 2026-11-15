import Foundation
import SwiftData
import WidgetKit

/// The app's half of the Still Open widget: writes the snapshot it shows and applies the ticks
/// made on it. See `StillOpenWidgetData` for the shape and the privacy rules.
@MainActor
enum StillOpenWidgetSync {
    /// The journal revision and container the snapshot was last built from, so a foreground with
    /// nothing changed decrypts nothing.
    private static var builtFor: (container: ObjectIdentifier, revision: Int, subscribed: Bool)?
    /// Skips entries already read without an open item (one per store).
    private static var memo: (container: ObjectIdentifier?, memo: OpenChecklistItems.Memo) = (nil, .init())

    /// Rebuilds the snapshot when the journal changed since the last build. Reloads the widget
    /// only when what it shows changed.
    static func sync(context: ModelContext, force: Bool = false,
                     defaults: UserDefaults? = UserDefaults(suiteName: WidgetShared.appGroupID),
                     subscribed: Bool = WidgetShared.isSubscribed()) {
        // The list is Core: on Free nothing is decrypted and no item text goes to the app group.
        let key = (container: ObjectIdentifier(context.container), revision: JournalRevision.shared.value, subscribed: subscribed)
        if !force, let builtFor, builtFor.container == key.container, builtFor.revision == key.revision,
           builtFor.subscribed == key.subscribed { return }
        if memo.container != key.container { memo = (key.container, OpenChecklistItems.Memo()) }
        let snapshot = subscribed ? snapshot(from: OpenChecklistItems.groups(in: context, memo: memo.memo)) : .init(items: [], total: 0)
        builtFor = key
        if StillOpenWidgetData.write(snapshot, in: defaults) {
            WidgetCenter.shared.reloadTimelines(ofKind: StillOpenWidgetData.widgetKind)
        }
    }

    private static var pending: Task<Void, Never>?

    /// After a save: rebuilds once the journal has been quiet for a few seconds. Reading every
    /// styled entry costs about as much as the heatmaps' own fetch (~250 ms at 5,000 entries on
    /// the simulator), so it doesn't ride on every save; the widget isn't on screen while the app
    /// is, and backgrounding (`flushPending`) and app-active rebuild it straight away.
    static func scheduleSync(context: ModelContext) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            pending = nil
            PerfSignpost.interval("widget.stillOpen") { sync(context: context) }
        }
    }

    /// The app is leaving: run a waiting rebuild now.
    static func flushPending(context: ModelContext) {
        guard let task = pending else { return }
        task.cancel()
        pending = nil
        PerfSignpost.interval("widget.stillOpen") { sync(context: context) }
    }

    /// Newest entry first, its items in order, at most `maxItems`, each clipped.
    nonisolated static func snapshot(from groups: [OpenChecklistItems.Group]) -> StillOpenWidgetData.Snapshot {
        var items: [StillOpenWidgetData.Item] = []
        var total = 0
        for group in groups {
            for line in group.lines {
                total += 1
                guard items.count < StillOpenWidgetData.maxItems else { continue }
                items.append(.init(entryID: group.entryID, index: line.index,
                                   text: StillOpenWidgetData.clip(line.text),
                                   hash: StillOpenWidgetData.lineHash(line.text), day: group.createdAt))
            }
        }
        return .init(items: items, total: total)
    }

    /// Ticks made on the widget, applied to their entries. A tick whose line changed (edited on
    /// another device, or deleted) is dropped, never forced. Runs on app-active, before `sync`.
    /// Returns how many were applied.
    @discardableResult
    static func applyPendingTicks(context: ModelContext,
                                  defaults: UserDefaults? = UserDefaults(suiteName: WidgetShared.appGroupID),
                                  subscribed: Bool = WidgetShared.isSubscribed()) -> Int {
        let ticks = StillOpenWidgetData.ticks(in: defaults)
        guard !ticks.isEmpty else { return 0 }
        var applied = 0
        for tick in ticks {
            if OpenChecklistItems.setChecked(true, index: tick.index, entryID: tick.entryID, in: context,
                                             matches: { StillOpenWidgetData.lineHash($0) == tick.hash }) {
                applied += 1
            }
        }
        // Applied or not, a tick is handled once. One the app couldn't apply because the key was
        // unavailable would come back on the next foreground; only drop those it could judge.
        if MirrorEncryption.canEncrypt(creatingIfNeeded: false) {
            StillOpenWidgetData.setTicks([], in: defaults)
        }
        sync(context: context, force: true, defaults: defaults, subscribed: subscribed)
        return applied
    }
}
