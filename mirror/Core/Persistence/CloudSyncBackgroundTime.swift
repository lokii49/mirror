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

/// Background time for the length of every Core Data save, begun on the saving thread the moment
/// the save starts (`willSaveObjectsNotification`) and ended when it's done.
///
/// Why, beyond `CloudSyncBackgroundTime`: TestFlight 3.1.8 (47), iPhone 13, 2026-11-08: CloudKit's
/// own scheduler woke the app in the background, NSPersistentCloudKitContainer began an export, and
/// its first write (the event record, `NSCKEvent beginEventForRequest`) was mid-commit when iOS
/// suspended the app: `RUNNINGBOARD 0xdead10cc`. That write comes before the sync event is posted,
/// so the event-based guard above starts too late for it. This one covers every save, ours and the
/// mirroring delegate's, from its first byte.
///
/// Each task is ended by the matching did-save, by a 20-second limit (a failed save posts no
/// did-save), or by iOS's expiration handler, so it can't keep the app awake. Thread-safe:
/// `beginBackgroundTask`/`endBackgroundTask` may be called from any thread (UIKit docs).
nonisolated final class StoreSaveBackgroundTime: @unchecked Sendable {
    static let shared = StoreSaveBackgroundTime(
        begin: { name, expired in application?.beginBackgroundTask(withName: name, expirationHandler: expired) ?? .invalid },
        end: { application?.endBackgroundTask($0) }
    )

    private static let applicationLock = NSLock()
    nonisolated(unsafe) private static var capturedApplication: UIApplication?
    nonisolated(unsafe) private static var launchObserver: NSObjectProtocol?

    /// The app's instance once UIKit has made it; saving threads read it here and never ask UIKit.
    private static var application: UIApplication? {
        applicationLock.lock(); defer { applicationLock.unlock() }
        return capturedApplication
    }

    /// False until the application has been captured: saves before that get no background time.
    static var hasApplication: Bool { application != nil }

    /// Call from the main thread at launch.
    ///
    /// `mirrorApp.init` runs before `UIApplicationMain` has created the application, so
    /// `UIApplication.shared` is still nil there. Builds 49 and 50 read it once at that point, kept
    /// nil, and never began a task (found from a 0xdead10cc on TestFlight 3.1.8 (50), 2026-11-11).
    /// So: take it now if it exists, else from the did-finish-launching notification (whose object
    /// is the application) or the first main-queue turn, whichever comes first.
    @MainActor func startForApp() {
        start()
        guard !Self.captureApplication(Self.applicationIfCreated) else { return }
        Self.launchObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: nil
        ) { note in
            StoreSaveBackgroundTime.captureApplication(note.object as? UIApplication)
        }
        Self.retryCapture(attemptsLeft: 20)
    }

    /// `UIApplication.shared` is typed non-optional but is nil before `UIApplicationMain`; asking
    /// through key-value coding gives an honest optional.
    @MainActor private static var applicationIfCreated: UIApplication? {
        UIApplication.value(forKey: "sharedApplication") as? UIApplication
    }

    /// The main queue first runs inside UIKit's run loop, where the application exists; the later
    /// attempts (half a second apart) are only there so a nil never becomes permanent again.
    @MainActor private static func retryCapture(attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attemptsLeft == 20 ? 0 : 0.5)) {
            MainActor.assumeIsolated {
                if !captureApplication(applicationIfCreated) { retryCapture(attemptsLeft: attemptsLeft - 1) }
            }
        }
    }

    /// True once an application is held (this one or one captured earlier).
    @discardableResult
    private static func captureApplication(_ candidate: UIApplication?) -> Bool {
        applicationLock.lock(); defer { applicationLock.unlock() }
        if capturedApplication == nil, let candidate { capturedApplication = candidate }
        guard capturedApplication != nil else { return false }
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        return true
    }

    static let limit: TimeInterval = 20

    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: UIBackgroundTaskIdentifier] = [:]
    private var begun = 0
    private var observers: [NSObjectProtocol] = []
    private let beginTask: (String, @escaping () -> Void) -> UIBackgroundTaskIdentifier
    private let endTask: (UIBackgroundTaskIdentifier) -> Void

    init(begin: @escaping (String, @escaping () -> Void) -> UIBackgroundTaskIdentifier,
         end: @escaping (UIBackgroundTaskIdentifier) -> Void) {
        beginTask = begin
        endTask = end
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // queue: nil, so the handler runs on the saving thread before the save writes anything.
        observers.append(center.addObserver(forName: NSManagedObjectContext.willSaveObjectsNotification, object: nil, queue: nil) { [weak self] note in
            guard let context = note.object as AnyObject? else { return }
            self?.saveWillBegin(ObjectIdentifier(context))
        })
        observers.append(center.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification, object: nil, queue: nil) { [weak self] note in
            guard let context = note.object as AnyObject? else { return }
            self?.saveDidEnd(ObjectIdentifier(context))
        })
    }

    func saveWillBegin(_ context: ObjectIdentifier) {
        lock.lock()
        guard tasks[context] == nil else { lock.unlock(); return }
        lock.unlock()
        let task = beginTask("mirror.storeSave") { [weak self] in self?.saveDidEnd(context) }
        guard task != .invalid else { return }
        lock.lock()
        if tasks[context] == nil {
            tasks[context] = task
            begun += 1
            lock.unlock()
        } else {
            lock.unlock()
            endTask(task)   // another thread got there first
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.limit) { [weak self] in
            self?.end(context, only: task)
        }
    }

    func saveDidEnd(_ context: ObjectIdentifier) {
        lock.lock()
        let task = tasks.removeValue(forKey: context)
        lock.unlock()
        if let task { endTask(task) }
    }

    /// The time limit: ends `task` if it's still the one held for this context.
    func end(_ context: ObjectIdentifier, only task: UIBackgroundTaskIdentifier) {
        lock.lock()
        guard tasks[context] == task else { lock.unlock(); return }
        tasks.removeValue(forKey: context)
        lock.unlock()
        endTask(task)
    }

    var heldCount: Int {
        lock.lock(); defer { lock.unlock() }
        return tasks.count
    }

    /// Tasks UIKit actually gave, ever. Lets a test in the running app tell a working guard from
    /// one that is installed but never gets a task.
    var begunCount: Int {
        lock.lock(); defer { lock.unlock() }
        return begun
    }
}
#endif
