import Testing
import Foundation
@testable import mirror

/// Backlog A14: a new pre-generation pass started while a cancelled one still held its claim
/// found the key taken and gave up.
@Suite(.serialized)
@MainActor
struct ActivationGenerationTests {
    private static let key = "activation_test_key"

    /// A pass that holds the claim until cancelled, then unwinds after a short delay (as a
    /// generation stops at its next cancellation check).
    private func longPass() -> Task<Void, Never> {
        Task { @MainActor in
            guard InsightGenerationCoordinator.shared.claim(key: Self.key) else { return }
            defer { InsightGenerationCoordinator.shared.release(key: Self.key) }
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func theNextPassWaitsForTheCancelledOneAndGetsTheClaim() async {
        let previous = longPass()
        try? await Task.sleep(for: .milliseconds(30))  // it holds the claim now
        previous.cancel()
        var claimed = false
        let next = mirrorApp.afterCancelling(previous, priority: .userInitiated) { @MainActor in
            claimed = InsightGenerationCoordinator.shared.claim(key: Self.key)
            if claimed { InsightGenerationCoordinator.shared.release(key: Self.key) }
        }
        await next.value
        #expect(claimed, "the new pass ran after the cancelled one released its claim")
    }

}
