import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Apple's on-device Foundation Models framework (iOS 26+, Apple Intelligence-capable
/// devices only). Mirrors `LocalLLMService.generate`'s signature so `LocalLLMService` can route
/// to this engine first and fall back to the bundled Gemma/llama.cpp path transparently —
/// `InsightService` never needs to know which engine actually ran.
enum FoundationModelEngine {

    enum UnavailableReason {
        case unsupportedOS
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    /// Cheap, synchronous check — safe to call from anywhere (UI, background tasks).
    /// Does not load the model or trigger any download.
    static var isAvailable: Bool {
        unavailableReason == nil
    }

    static var unavailableReason: UnavailableReason? {
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

    static func generate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw LocalLLMError.emptyResponse }
        let session = LanguageModelSession(instructions: systemPrompt)
        let options = GenerationOptions(temperature: Double(task.temperature))
        let response = try await session.respond(to: userMessage, options: options)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalLLMError.emptyResponse }
        return text
        #else
        throw LocalLLMError.emptyResponse
        #endif
    }
}
