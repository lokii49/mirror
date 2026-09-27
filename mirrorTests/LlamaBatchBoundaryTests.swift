import XCTest
import SwiftLlama
@testable import mirror

// Regression for the swift-llama-cpp 1.2.1 empty-final-batch bug (2026-09-27): a prompt whose
// templated token count is an exact multiple of the batch size makes Llama.processPrompt write
// logits[-1] and decode zero tokens. LocalLLMService.avoidingEmptyFinalBatch steps prompts off the
// boundary. Needs the Gemma file (GemmaModelTestSupport), skips without it. Synthetic text only.
final class LlamaBatchBoundaryTests: XCTestCase {

    /// A single user message grown word by word until the templated prompt is exactly
    /// `batch * k` tokens for the smallest k that fits.
    private func boundaryMessages(_ service: LocalLLMService) async throws -> [LlamaChatMessage] {
        let batch = Int(LocalLLMService.llamaBatchSize)
        var content = "Write one short sentence about a quiet walk by the lake after work."
        for _ in 0..<600 {
            let messages = [LlamaChatMessage(role: .user, content: content)]
            let counted = await service.promptTokenCount(for: messages)
            let count = try XCTUnwrap(counted)
            if count % batch == 0 { return messages }
            content += " calm"
        }
        throw XCTSkip("couldn't land on a batch boundary by appending single-token words")
    }

    func test_guardStepsPromptOffTheBatchBoundary() async throws {
        guard GemmaModelTestSupport.ensureModelInstalled() else { throw XCTSkip("Gemma model not available") }
        let service = LocalLLMService.shared
        let onBoundary = try await boundaryMessages(service)
        let guarded = await service.avoidingEmptyFinalBatch(onBoundary)
        let counted = await service.promptTokenCount(for: guarded)
        let count = try XCTUnwrap(counted)
        XCTAssertNotEqual(count % Int(LocalLLMService.llamaBatchSize), 0)
        XCTAssertTrue(guarded.last!.content.hasPrefix(onBoundary.last!.content), "only a suffix is added")
    }

    /// Proves the bug is real in the shipped wrapper (unguarded LlamaService fails on the boundary
    /// prompt) and that the same prompt succeeds through LocalLLMService. Real inference — opt-in.
    func test_boundaryPromptFailsUnguardedAndSucceedsThroughLocalLLMService() async throws {
        guard ProcessInfo.processInfo.environment["RUN_GROUNDING_HARNESS"] == "1" else {
            throw XCTSkip("Set RUN_GROUNDING_HARNESS=1 — real on-device generation")
        }
        guard GemmaModelTestSupport.ensureModelInstalled() else { throw XCTSkip("Gemma model not available") }
        let onBoundary = try await boundaryMessages(LocalLLMService.shared)

        let raw = LlamaService(modelUrl: try LocalLLMService.preferredModelURL(), config: LlamaConfig(batchSize: LocalLLMService.llamaBatchSize, maxTokenCount: 4096, useGPU: false))
        do {
            _ = try await raw.streamCompletion(of: onBoundary, samplingConfig: LlamaSamplingConfig(temperature: 0.2, seed: 1))
            XCTFail("expected the unguarded wrapper to fail on a batch-boundary prompt")
        } catch {
            // Expected: LlamaError.decodingError from the empty final batch.
        }
        await raw.stopCompletion()

        LocalLLMService.forceGemmaForTesting = true
        defer { LocalLLMService.forceGemmaForTesting = false }
        let result = try await LocalLLMService.shared.generate(systemPrompt: "", userMessage: onBoundary[0].content, task: .dailyNudge, gemmaPlan: .grammarConstrained(userMessage: onBoundary[0].content, grammar: #"root ::= [a-z ]{5,40} ".""#))
        XCTAssertFalse(result.text.isEmpty)
    }
}
