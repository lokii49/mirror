import XCTest
import SwiftLlama
@testable import mirror

// Regression for swift-llama-cpp's empty-final-batch bug, fixed in the vendored package
// (Packages/SwiftLlama/PATCHES.md #2): a prompt whose templated token count is an exact multiple
// of the batch size used to write logits[-1] and fail llama_decode on zero tokens, every time.
// Needs the Gemma file (GemmaModelTestSupport); skips without it. Synthetic text only.
final class LlamaBatchBoundaryTests: XCTestCase {

    /// A single user message grown word by word until the templated prompt — built exactly as
    /// Llama.initializeCompletion builds it — is a multiple of the batch size.
    private func boundaryMessages(model: LlamaModel) throws -> [LlamaChatMessage] {
        let batch = Int(LocalLLMService.llamaBatchSize)
        var content = "Write one short sentence about a quiet walk by the lake after work."
        for _ in 0..<600 {
            let messages = [LlamaChatMessage(role: .user, content: content)]
            let prompt = model.applyChatTemplate(to: messages)
            if model.tokenize(text: prompt, addBos: model.shouldAddBos(), special: true).count % batch == 0 {
                return messages
            }
            content += " calm"
        }
        throw XCTSkip("couldn't land on a batch boundary by appending single-token words")
    }

    /// Real inference — opt-in like the grounding harness.
    func test_patchedWrapperGeneratesFromABatchBoundaryPrompt() async throws {
        guard ProcessInfo.processInfo.environment["RUN_GROUNDING_HARNESS"] == "1" else {
            throw XCTSkip("Set RUN_GROUNDING_HARNESS=1 — real on-device generation")
        }
        guard GemmaModelTestSupport.ensureModelInstalled() else { throw XCTSkip("Gemma model not available") }
        let url = try LocalLLMService.preferredModelURL()
        let model = try XCTUnwrap(LlamaModel.vocabularyOnly(path: url.path(percentEncoded: false)))
        let onBoundary = try boundaryMessages(model: model)

        let service = LlamaService(modelUrl: url, config: LlamaConfig(batchSize: LocalLLMService.llamaBatchSize, maxTokenCount: 4096, useGPU: false))
        let stream = try await service.streamCompletion(of: onBoundary, samplingConfig: LlamaSamplingConfig(temperature: 0.2, seed: 1))
        var output = ""
        for try await piece in stream {
            output += piece
            if output.count > 20 { break }
        }
        await service.stopCompletion()
        XCTAssertFalse(output.isEmpty, "the patched wrapper must decode a batch-boundary prompt")
    }
}
