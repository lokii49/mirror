import Foundation

actor LLMGenerationQueue {
    static let shared = LLMGenerationQueue()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Lets a low-priority, opportunistic caller (1.2's typing-triggered follow-up chip) check
    /// before joining the queue, instead of always taking a FIFO slot the way `run` does.
    /// Doesn't change `run`'s fairness for anything already queued — it's an opt-in way to skip
    /// *starting* a new low-priority request while something the user actually asked for (a
    /// save-time mood detect, an explicit Ask, a background digest) is already running, rather
    /// than stacking latency behind or ahead of it. writing-roadmap.md flagged this as an
    /// unmeasured perf/scheduling gap; this doesn't require the device measurement that item
    /// asked for — it just stops the ambient feature from ever competing in the first place.
    var isBusy: Bool { isRunning }

    func run<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isRunning = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}
