#if os(iOS)
import Foundation
import Testing
import UIKit
import CoreData
@testable import mirror

/// Background time held for each Core Data save, from will-save to did-save (0xdead10cc on
/// TestFlight 3.1.8 (47), 2026-11-08). The UIKit calls are replaced by counters here.
@Suite("Store save background time")
struct StoreSaveBackgroundTimeTests {
    final class Fake: @unchecked Sendable {
        let lock = NSLock()
        var next = 1
        var begun: [Int] = []
        var ended: [Int] = []
        var expirations: [() -> Void] = []
        func begin(_ name: String, _ expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
            lock.lock(); defer { lock.unlock() }
            let id = next; next += 1; begun.append(id); expirations.append(expired)
            return UIBackgroundTaskIdentifier(rawValue: id)
        }
        func end(_ task: UIBackgroundTaskIdentifier) {
            lock.lock(); defer { lock.unlock() }
            ended.append(task.rawValue)
        }
    }

    private func make(_ fake: Fake) -> StoreSaveBackgroundTime {
        StoreSaveBackgroundTime(begin: fake.begin, end: fake.end)
    }

    @Test func eachSaveHoldsOneTaskUntilItEnds() {
        let fake = Fake(), time = make(fake)
        // Kept alive: two freed objects can share an address, and so an ObjectIdentifier.
        let objA = NSObject(), objB = NSObject()
        let a = ObjectIdentifier(objA), b = ObjectIdentifier(objB)
        defer { withExtendedLifetime((objA, objB)) {} }
        time.saveWillBegin(a)
        time.saveWillBegin(a)          // nested will-save on the same context: still one task
        time.saveWillBegin(b)
        #expect(fake.begun == [1, 2] && time.heldCount == 2)
        time.saveDidEnd(a)
        #expect(fake.ended == [1] && time.heldCount == 1)
        time.saveDidEnd(b)
        time.saveDidEnd(b)             // a stray did-save ends nothing twice
        #expect(fake.ended == [1, 2] && time.heldCount == 0)
    }

    @Test func expirationEndsTheTask() {
        let fake = Fake(), time = make(fake)
        let a = ObjectIdentifier(NSObject())
        time.saveWillBegin(a)
        fake.expirations[0]()
        #expect(fake.ended == [1] && time.heldCount == 0)
    }

    @Test func theTimeLimitEndsOnlyTheTaskItWasSetFor() {
        let fake = Fake(), time = make(fake)
        let a = ObjectIdentifier(NSObject())
        time.saveWillBegin(a)
        time.saveDidEnd(a)
        time.saveWillBegin(a)          // a second save on the same context: task 2
        time.end(a, only: UIBackgroundTaskIdentifier(rawValue: 1))   // the first save's limit fires late
        #expect(time.heldCount == 1 && fake.ended == [1])
        time.end(a, only: UIBackgroundTaskIdentifier(rawValue: 2))
        #expect(time.heldCount == 0 && fake.ended == [1, 2])
    }

    @Test func noTaskWhenUIKitGivesNone() {
        let time = StoreSaveBackgroundTime(begin: { _, _ in .invalid }, end: { _ in Issue.record("nothing to end") })
        let a = ObjectIdentifier(NSObject())
        time.saveWillBegin(a)
        time.saveDidEnd(a)
        #expect(time.heldCount == 0)
    }

    @Test func aRealContextSaveBeginsAndEndsATask() throws {
        let fake = Fake(), time = make(fake)
        time.start()
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "Thing"
        let attribute = NSAttributeDescription()
        attribute.name = "n"
        attribute.attributeType = .integer64AttributeType
        entity.properties = [attribute]
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let thing = NSManagedObject(entity: entity, insertInto: context)
            thing.setValue(1, forKey: "n")
            try context.save()
        }
        // Other tests' saves may also pass through this observer; this context's task is the
        // one that matters: begun and ended.
        #expect(!fake.begun.isEmpty)
        #expect(Set(fake.ended).isSuperset(of: [1]))
    }

    /// The app's own instance with the real UIKit calls, in the running app (the test host starts
    /// it in `mirrorApp.init`, as a normal launch does). Builds 49 and 50 passed every test above
    /// while this guard never got a task: the application was read before UIKit had made it.
    @Test @MainActor func theAppsGuardGetsARealTaskForASave() throws {
        try #require(MirrorModelContainer.isStoreAvailable)
        #expect(StoreSaveBackgroundTime.hasApplication)
        let shared = StoreSaveBackgroundTime.shared
        let before = shared.begunCount
        let object = NSObject()
        let context = ObjectIdentifier(object)
        shared.saveWillBegin(context)
        #expect(shared.begunCount == before + 1)
        shared.saveDidEnd(context)
        withExtendedLifetime(object) {}
    }
}
#endif
