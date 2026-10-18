import Testing
import Foundation
@testable import mirror

// A cancelled pass (app backgrounded, refresh task expired) must not come back as the fallback,
// which the caller would save and the 24h cache would then show (backlog A4). Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct CancelledGenerationTests {
        private final class Box: @unchecked Sendable {
            var task: Task<String, Error>?
            var calls = 0
        }

        private func week() -> [Entry] {
            let hard = Entry(text: "Client presentation got pushed to Thursday again. Feel behind on everything and the review is due Monday.", mood: "Overwhelmed")
            let good = Entry(text: "Walked by the lake after work with the dog. Felt light for the first time this week.", mood: "Peaceful")
            good.createdAt = hard.createdAt.addingTimeInterval(-86_400)
            return [hard, good]
        }

        /// Well-formed, but nothing in it comes from the entries above.
        private let inventedDigest = """
            THIS WEEK'S THEME: Quiet mornings spent repotting succulents on a sunny windowsill.
            YOUR ENERGY: Gardening seemed to restore patience after long phone calls with cousins.
            WHAT'S BUILDING: A steady habit of sketching birds every Saturday at the harbour.
            WATCH OUT FOR: Skipping breakfast before choir rehearsals.
            MOOD BOOST: Bake that lemon bread recipe from grandma.
            NEXT WEEK: Plan a picnic near the old lighthouse.
            """

        @Test func cancelledDigestRetryThrowsInsteadOfReturningTheFallback() async {
            let box = Box()
            let invented = inventedDigest
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in
                box.calls += 1
                if box.calls == 1 { return (invented, .foundationModels) }
                box.task?.cancel()
                throw CancellationError()
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let entries = week()
            let task = Task { @MainActor in
                try await InsightService.generateWeeklyDigest(weekEntries: entries, allEntries: entries).text
            }
            box.task = task
            let result = await task.result

            // Attempt 1 failed grounding, so the loop reached attempt 2 (where the cancel happened).
            #expect(box.calls == 2)
            switch result {
            case .success(let text):
                Issue.record("expected a throw, got \(text == InsightService.weeklyDigestUngroundedFallback ? "the fallback" : "text")")
            case .failure:
                break
            }
        }

        @Test func uncancelledFailureStillReturnsTheFallback() async throws {
            let box = Box()
            let invented = inventedDigest
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in
                box.calls += 1
                if box.calls == 1 { return (invented, .foundationModels) }
                throw LocalLLMError.contextExhausted
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let entries = week()
            let (text, _) = try await InsightService.generateWeeklyDigest(weekEntries: entries, allEntries: entries)
            #expect(text == InsightService.weeklyDigestUngroundedFallback)
        }
    }
}
