import Testing
import Foundation
@testable import mirror

@Suite("RunOnce")
struct RunOnceTests {
    @Test func secondCallIsIgnored() {
        let once = RunOnce()
        var count = 0
        #expect(once.run { count += 1 })
        #expect(!once.run { count += 1 })
        #expect(count == 1)
    }

    @Test func concurrentCallsRunExactlyOnce() async {
        let once = RunOnce()
        let count = LockedCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { once.run { count.increment() } }
            }
        }
        #expect(count.value == 1)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
