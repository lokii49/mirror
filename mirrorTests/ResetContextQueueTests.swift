import Testing
import Foundation
@testable import mirror

// Backlog A15: after `contextExhausted`, `localGenerate` called `resetContext()` outside
// `LLMGenerationQueue`, which could stop another caller's Gemma stream mid-generation. The
// retry's own `generate` already resets inside the queue. Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct ResetContextQueueTests {
        private final class Box: @unchecked Sendable {
            var calls = 0
            var resetsOutsideQueue = 0
        }

        @Test func contextExhaustedRetry_neverResetsOutsideTheQueue() async {
            let box = Box()
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in
                box.calls += 1
                if box.calls == 1 { throw LocalLLMError.contextExhausted }
                return ("What made the morning feel quiet?", .gemma)
            }
            LocalLLMService.resetContextObserverForTesting = {
                if !(await LLMGenerationQueue.shared.isBusy) { box.resetsOutsideQueue += 1 }
            }
            defer {
                LocalLLMService.generateInterceptForTesting = nil
                LocalLLMService.resetContextObserverForTesting = nil
            }
            _ = try? await InsightService.localGenerate(
                systemPrompt: "Ask one short question.",
                userMessage: "A quiet morning with tea.",
                task: .followUp,
                responseLanguageInstruction: nil
            )
            #expect(box.calls == 2, "contextExhausted still gets its one retry")
            #expect(box.resetsOutsideQueue == 0)
        }
    }
}
