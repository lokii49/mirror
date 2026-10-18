import Testing
import Foundation
@testable import mirror

// Backlog A15: `localGenerate` rethrew a cancelled generation as
// `InsightError.serviceUnavailable`, so callers that tell cancellation apart by its error type
// saw a model failure ("will try again tonight") instead. Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct LocalGenerateCancellationTests {
        @Test func cancellationIsRethrownAsCancellation() async {
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in throw CancellationError() }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            var thrown: Error?
            do {
                _ = try await InsightService.localGenerate(
                    systemPrompt: "Ask one short question.",
                    userMessage: "A quiet morning with tea.",
                    task: .followUp,
                    responseLanguageInstruction: nil
                )
            } catch {
                thrown = error
            }
            #expect(thrown is CancellationError)
        }

        /// Not over-corrected: other model errors still become `serviceUnavailable`.
        @Test func otherErrorsStillBecomeServiceUnavailable() async {
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in throw LocalLLMError.modelMissing(URL(fileURLWithPath: "/tmp/none.gguf")) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            var thrown: Error?
            do {
                _ = try await InsightService.localGenerate(
                    systemPrompt: "Ask one short question.",
                    userMessage: "A quiet morning with tea.",
                    task: .followUp,
                    responseLanguageInstruction: nil
                )
            } catch {
                thrown = error
            }
            guard case .serviceUnavailable = thrown as? InsightError else {
                Issue.record("expected serviceUnavailable, got \(String(describing: thrown))")
                return
            }
        }
    }
}
