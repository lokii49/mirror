import Foundation
import Observation
import SwiftData
import CoreData

/// A counter that goes up whenever the journal's stored data may have changed: a save from any
/// model context that inserted, changed or deleted something, or a finished CloudKit import.
///
/// Views key their `.task(id:)` caches on it instead of hashing every entry inside `body`. That
/// hash read ~22 stored fields of every entry on every body evaluation (67-75 ms at 5,000 entries
/// on an M-series Mac, 64% of the Entries tab's main-thread time while searching; audit
/// 2026-11-04). The counter only says *when* to look again; each cache still decides *what*
/// changed itself, so a bump that changed nothing a view shows costs one rebuild and no more.
///
/// A save on another context (Siri, the nightly task, voice transcription) or a CloudKit import
/// reaches the main context's objects a moment later (merge), so those bumps are followed by one
/// more about 400 ms later: a cache rebuilt from not-yet-merged objects is rebuilt again once they
/// are. A main-context save needs no second bump: its objects are already current, and inserts and
/// deletes also show up in the views' counts once their queries refresh. The app saves right after each edit (pin, move, mood, date),
/// and the main context autosaves anything else, so unsaved in-memory edits are covered too.
@MainActor
@Observable
final class JournalRevision {
    static let shared = JournalRevision()

    private(set) var value = 0

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var settleBump: Task<Void, Never>?
    @ObservationIgnored private weak var container: ModelContainer?

    /// Counts saves to `container` only (not the device backup copy or other stores); saves from its
    /// main context skip the settle bump.
    func start(container: ModelContainer) {
        guard observers.isEmpty else { return }
        self.container = container
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            guard Self.changedSomething(note.userInfo), let saver = note.object as? ModelContext else { return }
            MainActor.assumeIsolated {
                guard let self, let container = self.container, saver.container === container else { return }
                self.bump(settle: saver !== container.mainContext)
            }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated { self?.bump() }
        })
    }

    /// Also for changes that reach the store without a model-context save.
    func bump(settle: Bool = true) {
        value &+= 1
        guard settle else { return }
        settleBump?.cancel()
        settleBump = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.value &+= 1
            self.settleBump = nil
        }
    }

    /// An autosave that changed nothing posts didSave too; it must not rebuild every cache.
    nonisolated static func changedSomething(_ userInfo: [AnyHashable: Any]?) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        return keys.contains { key in
            (userInfo?[key.rawValue] as? [PersistentIdentifier]).map { !$0.isEmpty } ?? false
        }
    }
}

/// A `.task(id:)` key for caches built from the journal: counts catch inserts and deletes as soon
/// as a query refreshes, the revision catches in-place edits and synced changes.
struct JournalCacheKey: Hashable {
    var entries: Int
    var checkIns: Int
    var revision: Int
    var first: UUID? = nil
    var last: UUID? = nil
}
