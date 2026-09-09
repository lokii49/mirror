import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Apple's on-device Foundation Models framework (iOS 26+, Apple Intelligence-capable
/// devices only). Mirrors `LocalLLMService.generate`'s signature so `LocalLLMService` can route
/// to this engine first and fall back to the bundled Gemma/llama.cpp path transparently —
/// callers don't have to branch on which engine ran. `LocalLLMService.generate` does report
/// which one actually served the request (see `LLMEngine`), but purely for diagnostic
/// attribution on the saved `Insight` — nothing in the generation/validation pipeline branches
/// on it.
enum FoundationModelEngine {

    nonisolated enum UnavailableReason {
        case unsupportedOS
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    /// Cheap, synchronous check — safe to call from anywhere (UI, background tasks).
    /// Does not load the model or trigger any download.
    /// `nonisolated` is required: the mirror target builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise pin this to the
    /// main actor and make it unusable from `LocalLLMService`'s actor context or from
    /// synchronous background-task gates like `isModelAvailable`. `SystemLanguageModel` is
    /// itself `Sendable` with no actor affinity, so this is safe.
    nonisolated static var isAvailable: Bool {
        unavailableReason == nil
    }

    nonisolated static var unavailableReason: UnavailableReason? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .modelNotReady
        }
        #else
        return .unsupportedOS
        #endif
    }

    nonisolated static func generate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw LocalLLMError.emptyResponse }
        let session = LanguageModelSession(instructions: systemPrompt)
        let options = GenerationOptions(
            temperature: Double(task.temperature),
            maximumResponseTokens: approximateMaxTokens(for: task)
        )
        let response = try await session.respond(to: userMessage, options: options)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalLLMError.emptyResponse }
        return text
        #else
        throw LocalLLMError.emptyResponse
        #endif
    }

    // LocalLLMTask.maxOutputChars was tuned as a hard character cutoff for Gemma's
    // streaming loop. GenerationOptions wants a token budget instead, and FM's stricter
    // instruction-following tends to run more verbose than Gemma at the same task — so this
    // errs high (~3 chars/token, well under English's ~4) rather than truncating output
    // mid-sentence and tripping InsightService's terminal-punctuation validators.
    nonisolated private static func approximateMaxTokens(for task: LocalLLMTask) -> Int {
        max(64, task.maxOutputChars / 3)
    }
}
