import SwiftData

enum MirrorModelContainer {
    /// What `open` produced. When the journal store couldn't be opened, `container` is an empty
    /// in-memory stand-in (so code that needs a `ModelContainer` still has one) and `openError`
    /// is set. Nothing may write to the stand-in, and the app shows `StoreUnavailableView`
    /// instead of its normal UI. The real store is never deleted or reset: unsynced entries may
    /// still be in it.
    struct Outcome {
        let container: ModelContainer
        let openError: Error?
    }

    static let schema = Schema([
        Entry.self,
        Insight.self,
        UserProfile.self,
        MoodCheckIn.self,
        JournalErasure.self,
    ])

    static var defaultConfiguration: ModelConfiguration {
        #if DEBUG && os(macOS)
        // Mac UI snapshot mode: throwaway in-memory store, no CloudKit.
        if CommandLine.arguments.contains("--macSnapshot") {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        #endif
        #if DEBUG
        // Performance baseline: synthetic on-disk scratch store, never the real one, no CloudKit.
        if PerfSeed.isRequested {
            return ModelConfiguration(schema: schema, url: PerfSeed.storeURL, cloudKitDatabase: .none)
        }
        #endif
        return ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
    }

    static func open(_ configuration: ModelConfiguration = defaultConfiguration) -> Outcome {
        do {
            return Outcome(container: try ModelContainer(for: schema, configurations: [configuration]), openError: nil)
        } catch {
            let standIn = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            guard let container = try? ModelContainer(for: schema, configurations: [standIn]) else {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
            return Outcome(container: container, openError: error)
        }
    }

    private static let outcome: Outcome = {
        // Count-only check (no copy) so a purge that emptied the store last session freezes
        // the device backup before anything can overwrite it. See LocalJournalBackup.
        LocalJournalBackup.evaluateBeforeOpen(storeURL: LocalJournalBackup.liveStoreURL(defaultConfiguration))
        return open()
    }()

    static var shared: ModelContainer { outcome.container }
    static var openError: Error? { outcome.openError }
    static var isStoreAvailable: Bool { outcome.openError == nil }

    /// Tries the real store once more. A success means a relaunch will open it; this process
    /// keeps its stand-in, because the app's services already hold references to it.
    static func canOpenStoreNow() -> Bool {
        open().openError == nil
    }
}
