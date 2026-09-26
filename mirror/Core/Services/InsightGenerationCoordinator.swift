import Foundation
import Observation

/// Prevents simultaneous generation of the same insight type+period from multiple callers
/// (e.g. scenePhase.active pre-gen racing with InsightView.task).
///
/// `@Observable` so views can react to a key being released — a generation that throws
/// inserts no row, so `onChange(of: insights.count)` alone never fires and a `.loading`
/// card derived from `isInFlight` would otherwise never re-resolve.
@MainActor
@Observable
final class InsightGenerationCoordinator {
    static let shared = InsightGenerationCoordinator()
    private var inFlight: Set<String> = []
    @ObservationIgnored private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    var isAnyGenerating: Bool { !inFlight.isEmpty }

    /// Returns true and marks the key in-flight if no generation is running for it.
    /// Returns false if already in-flight — caller should skip or wait.
    func claim(key: String) -> Bool {
        guard !inFlight.contains(key) else { return false }
        inFlight.insert(key)
        return true
    }

    func isInFlight(_ key: String) -> Bool {
        inFlight.contains(key)
    }

    func release(key: String) {
        inFlight.remove(key)
        let pending = waiters.removeValue(forKey: key) ?? []
        pending.forEach { $0.resume() }
    }

    /// Suspends until `key` is no longer in flight (returns immediately if it isn't).
    /// Every claim is paired with a `defer { release }` at its call site, so this can't hang
    /// on a generation that throws.
    func waitUntilReleased(_ key: String) async {
        guard inFlight.contains(key) else { return }
        await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }
}
