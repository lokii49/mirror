#if os(iOS)
import CoreData
import UIKit

/// Keeps the app running, through a background task, while an iCloud import or export is in progress,
/// so iOS doesn't suspend it in the middle of a SQLite write.
///
/// The SwiftData store lives in the App Group container (`group.com.lokesh.mirror`, chosen by
/// `ModelConfiguration`'s default `groupContainer: .automatic`), and iOS kills an app that is suspended
/// while it holds a file lock in a shared container (`RUNNINGBOARD 0xdead10cc`). App Store 2.0.9,
/// 3.0.9 and 3.1.3 were killed that way with NSPersistentCloudKitContainer's importer mid-save
/// (Xcode Organizer, 2026-10-25). The store isn't moved out of the group container: existing stores
/// would be left behind.
///
/// Events come from NSPersistentCloudKitContainer's event stream, which SwiftData posts too (as
/// `JournalSafety` reads it). A task begins when the first event starts and ends when the last one
/// ends; if iOS's background time runs out first, the expiration handler ends it.
@MainActor
final class CloudSyncBackgroundTime {
    static let shared = CloudSyncBackgroundTime()

    private var inProgress = Set<UUID>()
    private var task = UIBackgroundTaskIdentifier.invalid
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import || event.type == .export else { return }
            let id = event.identifier, ended = event.endDate != nil
            MainActor.assumeIsolated { CloudSyncBackgroundTime.shared.record(id, ended: ended) }
        }
    }

    func record(_ id: UUID, ended: Bool) {
        if ended { inProgress.remove(id) } else { inProgress.insert(id) }
        if inProgress.isEmpty {
            endTask()
        } else if task == .invalid {
            task = UIApplication.shared.beginBackgroundTask(withName: "mirror.cloudSync") {
                MainActor.assumeIsolated {
                    // Out of background time with a sync still running: let iOS suspend the app rather
                    // than kill it for overstaying, and start fresh for the next sync.
                    CloudSyncBackgroundTime.shared.inProgress.removeAll()
                    CloudSyncBackgroundTime.shared.endTask()
                }
            }
        }
    }

    var isHoldingBackgroundTime: Bool { task != .invalid }

    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
#endif
