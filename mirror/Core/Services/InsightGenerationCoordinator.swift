import Foundation

/// Prevents simultaneous generation of the same insight type+period from multiple callers
/// (e.g. scenePhase.active pre-gen racing with InsightView.task).
@MainActor
final class InsightGenerationCoordinator {
    static let shared = InsightGenerationCoordinator()
    private var inFlight: Set<String> = []

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
    }
}
