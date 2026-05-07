import Foundation

actor LLMGenerationQueue {
    static let shared = LLMGenerationQueue()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

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
