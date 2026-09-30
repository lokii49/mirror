import os

/// Runs a closure at most once, from any thread. Used so a BGTask's expiration handler and its
/// completion path can't both call `setTaskCompleted`.
final class RunOnce: Sendable {
    private let fired = OSAllocatedUnfairLock(initialState: false)

    /// Returns true if this call ran `body`; false if an earlier call already did.
    @discardableResult
    func run(_ body: () -> Void) -> Bool {
        let first = fired.withLock { state -> Bool in
            if state { return false }
            state = true
            return true
        }
        if first { body() }
        return first
    }
}
