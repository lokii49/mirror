import Foundation
import SwiftData
import WidgetKit

/// The app's half of the Still Open widget: writes the snapshot it shows and applies the ticks
/// made on it. See `StillOpenWidgetData` for the shape and the privacy rules.
@MainActor
enum StillOpenWidgetSync {
    /// The journal revision and container the snapshot was last built from, so a foreground with
    /// nothing changed decrypts nothing.
    private static var builtFor: (container: ObjectIdentifier, revision: Int)?

    /// Rebuilds the snapshot when the journal changed since the last build. Reloads the widget
    /// only when what it shows changed.
    static func sync(context: ModelContext, force: Bool = false,
                     defaults: UserDefaults? = UserDefaults(suiteName: WidgetShared.appGroupID)) {
        let key = (container: ObjectIdentifier(context.container), revision: JournalRevision.shared.value)
        if !force, let builtFor, builtFor.container == key.container, builtFor.revision == key.revision { return }
        let groups = OpenChecklistItems.groups(in: context)
        let snapshot = snapshot(from: groups)
        builtFor = key
        if StillOpenWidgetData.write(snapshot, in: defaults) {
            WidgetCenter.shared.reloadTimelines(ofKind: StillOpenWidgetData.widgetKind)
        }
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
                                  defaults: UserDefaults? = UserDefaults(suiteName: WidgetShared.appGroupID)) -> Int {
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
        sync(context: context, force: true, defaults: defaults)
        return applied
    }
}
