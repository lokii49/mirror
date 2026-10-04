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
        guard #available(iOS 26.0, macOS 26.0, *) else { return .unsupportedOS }
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

    /// Whether Foundation Models can work in this language ("de", "pt", "zh", ...). Russian is not on
    /// Apple's list; asked on a Mac with Apple Intelligence: de, es, fr, it, pt, ja, ko, zh yes, ru no.
    nonisolated static func supports(languageCode: String) -> Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }
        return SystemLanguageModel.default.supportsLocale(Locale(identifier: languageCode))
        #else
        return false
        #endif
    }

    /// True when Foundation Models turned the request down only because it cannot work in the text's
    /// language (Russian today; `supportsLocale` is the API's own list). On a device that has Apple
    /// Intelligence this is the one failure where Gemma is still the right engine.
    nonisolated static func isUnsupportedLanguageError(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *),
           let failure = error as? LanguageModelSession.GenerationError,
           case .unsupportedLanguageOrLocale = failure {
            return true
        }
        #endif
        return false
    }

    nonisolated static func generate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { throw LocalLLMError.emptyResponse }
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

    /// The two fields Foundation Models fills for the English daily reflection. The app does not
    /// show them as written: `FMDailyGuard` finds the quote in today's entries and checks the insight.
    /// Field descriptions are part of the prompt the rig measured (tools/llmrig/fm/fmrig.swift,
    /// DailyV1bEasy); change them there too.
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    nonisolated struct DailyReflectionDraft {
        @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
        var quote: String
        @Guide(description: "One or two sentences speaking to the person as 'you': what this seems to mean for them, using only feelings they wrote or plainly showed. If the day was ordinary, say so. Plain everyday words. Say nothing about anything they did not write")
        var insight: String
    }
    #endif

    /// One structured draft. Temperature only, as measured: a token cap can cut a structured
    /// response off. Throws on a guardrail refusal or any model error; the caller counts that as a
    /// failed attempt.
    nonisolated static func generateDailyReflection(systemPrompt: String, userMessage: String) async throws -> (quote: String, insight: String) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { throw LocalLLMError.emptyResponse }
        let session = LanguageModelSession(instructions: systemPrompt)
        let options = GenerationOptions(temperature: Double(LocalLLMTask.dailyNudge.temperature))
        let draft = try await session.respond(to: userMessage, generating: DailyReflectionDraft.self, options: options).content
        return (draft.quote, draft.insight)
        #else
        throw LocalLLMError.emptyResponse
        #endif
    }

    /// Marks a test error as a guardrail refusal (a real `GenerationError` can't be built in tests).
    protocol GuardrailRefusalForTesting: Error {}

    /// True when Foundation Models declined for safety: a guardrail violation, or a refusal ("May
    /// contain sensitive content", `LanguageModelError` code 3 on iOS 27). It declines ordinary
    /// journal days set at a hospital, clinic, ICU, funeral home, therapist, court or police station
    /// (tools/llmrig round 11); `permissiveContentTransformations` does not lift it for guided generation.
    nonisolated static func isSafetyRefusal(_ error: Error) -> Bool {
        if error is GuardrailRefusalForTesting { return true }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .guardrailViolation, .refusal: return true
            default: break
            }
        }
        if #available(iOS 27.0, macOS 27.0, *), let modelError = error as? LanguageModelError {
            switch modelError {
            case .guardrailViolation, .refusal: return true
            default: break
            }
        }
        #endif
        return false
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
