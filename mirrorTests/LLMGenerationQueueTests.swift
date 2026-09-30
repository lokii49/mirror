import Testing
import Foundation
@testable import mirror

@Suite("LLMGenerationQueue cancellation")
struct LLMGenerationQueueTests {
    @Test func cancelledWaiterSkipsOperationAndReleasesQueue() async throws {
        let queue = LLMGenerationQueue.shared
        let gate = AsyncStream<Void>.makeStream()
        let ran = RanFlag()

        let holder = Task {
            try await queue.run { for await _ in gate.stream { break } }
        }
        while !(await queue.isBusy) { await Task.yield() }

        let waiter = Task {
            try await queue.run { ran.set() }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        waiter.cancel()
        gate.continuation.yield()
        try await holder.value

        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(!ran.value)

        // Queue was released: a fresh run goes through.
        let after = try await queue.run { 42 }
        #expect(after == 42)
        #expect(!(await queue.isBusy))
    }
}

private final class RanFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
