import Foundation
import SwiftData

/// Refreshes the streak, wrote-today and heatmap widgets after any save that adds, changes or
/// deletes an entry or a mood check-in (backlog A12). They used to refresh only on app-active,
/// the Siri intent, mood check-in and Mac quick capture, so writing in the app or deleting an
/// entry left the lock screen saying "not written" until the next foreground. One observer covers
/// every save and delete path. Debounced: a save burst refreshes once.
@MainActor
final class WidgetSaveRefresher {
    static let shared = WidgetSaveRefresher()
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var container: ModelContainer?

    func start(container: ModelContainer) {
        guard observer == nil else { return }
        self.container = container
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            guard Self.touchesJournal(note.userInfo) else { return }
            MainActor.assumeIsolated { self?.schedule(container: container) }
        }
    }

    nonisolated static func touchesJournal(_ userInfo: [AnyHashable: Any]?) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        return keys.contains { key in
            (userInfo?[key.rawValue] as? [PersistentIdentifier])?.contains {
                $0.entityName == "Entry" || $0.entityName == "MoodCheckIn"
            } ?? false
        }
    }

    /// The app is backgrounding: run a pending refresh now rather than after the debounce, so
    /// saving and leaving straight away still updates the widgets.
    func flushNow() {
        guard pending != nil, let container else { return }
        pending?.cancel()
        pending = nil
        mirrorApp.updateWidgetHeatmaps(context: container.mainContext)
    }

    private func schedule(container: ModelContainer) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            pending = nil
            mirrorApp.updateWidgetHeatmaps(context: container.mainContext)
        }
    }
}
