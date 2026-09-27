import Foundation
import SwiftLlama
import UIKit

enum LocalLLMError: LocalizedError {
    case modelMissing(URL)
    case emptyResponse
    case contextExhausted
    /// The caller said this request has no Gemma-safe form (`GemmaPlan.unsuitable`).
    case gemmaUnsuitable

    var errorDescription: String? {
        switch self {
        case .modelMissing(let url):
            return String(localized: "Local AI model not installed. Add gemma-3-1b-it-Q4_K_M.gguf to \(url.path).")
        case .emptyResponse:
            return String(localized: "Local AI returned an empty response.")
        case .contextExhausted:
            return String(localized: "Not enough device memory right now. Mirror will generate this overnight while your phone is charging.")
        case .gemmaUnsuitable:
            // Never user-facing (InsightService maps it to its own fallback), so this reuses an
            // existing localized string rather than adding an untranslated one.
            return String(localized: "Local AI returned an empty response.")
        }
    }
}

enum LocalLLMTask {
    case dailyNudge
    case weeklyDigest
    case monthlyReport
    case ask
    case emotion
    case followUp
    // Semantic grounding self-check (research: GroundingSampleHarness) — the model verifying
    // its OWN prior output against the source entries, as a candidate replacement/supplement
    // for the word-overlap guards (isUngrounded/sharesNoWordWithRecent/openingIsUngrounded),
    // which real-device measurement showed miss 53% of fabrications at realistic corpus scale
    // and can't be fixed by retuning (see GroundingSampleHarness.swift). Same shape as
    // `.emotion` — strict single-token classification output, not free-form generation — so it
    // gets the same low temperature and small output cap, for the same reason.
    case groundingVerification

    nonisolated var temperature: CFloat {
        switch self {
        case .emotion: return 0.1
        case .groundingVerification: return 0.1
        case .dailyNudge: return 0.45
        case .ask: return 0.45
        case .followUp: return 0.5
        case .weeklyDigest: return 0.55
        case .monthlyReport: return 0.55
        }
    }

    // Hard cap on accumulated output chars — prevents infinite generation when
    // Gemma's <end_of_turn> token isn't recognised as EOG by llama.cpp.
    nonisolated var maxOutputChars: Int {
        switch self {
        case .emotion: return 30
        case .groundingVerification: return 30
        case .followUp: return 140
        case .dailyNudge: return 700
        case .ask: return 1000
        case .weeklyDigest: return 2800
        case .monthlyReport: return 2800
        }
    }
}

/// Which engine actually produced a generation — diagnostic attribution only (Track A6, see
/// .claude/2.1.0-design-plan.md). `InsightService` still doesn't branch behavior on this; it
/// only threads it through to `Insight.generatedByEngine` so a quality regression report can
/// be traced back to which engine ran, instead of both engines being indistinguishable.
/// `String` rawValue is what gets persisted/synced (Insight.generatedByEngine), so treat these
/// cases as a stable wire format, not free to rename. Only `.rawValue` is ever written —
/// nothing decodes this enum back from storage, so no `Codable` conformance.
enum LLMEngine: String {
    case foundationModels
    case gemma
}

actor LocalLLMService {
    static let shared = LocalLLMService()

    static let modelFileName = "gemma-3-1b-it-Q4_K_M"
    static let modelExtension = "gguf"

    private var service: LlamaService?

    private init() {}

    #if DEBUG
    /// Test-only: skip Foundation Models so research harnesses can measure Gemma on a
    /// simulator/device where Apple Intelligence is available (it's preferred otherwise, so a
    /// harness run silently measures the wrong engine). Stripped from Release builds.
    nonisolated(unsafe) static var forceGemmaForTesting = false

    /// Test-only: when set, `generate` returns this instead of running any model — lets a
    /// harness capture the exact final system/user prompts a pipeline sends (including retry
    /// messages) without a slow real generation. Stripped from Release builds.
    nonisolated(unsafe) static var generateInterceptForTesting: ((String, String, LocalLLMTask, GemmaPlan) throws -> (text: String, engine: LLMEngine))?
    #endif

    /// How the Gemma path handles a request. Foundation Models always gets `systemPrompt`/
    /// `userMessage` as-is; this only changes what happens when generation runs on Gemma —
    /// either up front (no Foundation Models on this device) or as the fallback after a
    /// Foundation Models failure, which is why it's decided here and not by the caller.
    enum GemmaPlan: Sendable {
        /// Same prompt as Foundation Models (every task except the English daily nudge).
        case samePrompt
        /// A user-only message plus a GBNF grammar that constrains the output's shape.
        case grammarConstrained(userMessage: String, grammar: String)
        /// No Gemma-safe form of this request exists — throw `gemmaUnsuitable` rather than
        /// fall back to an unconstrained prompt that measurably fabricates.
        case unsuitable
    }

    /// True when `generate` will try Foundation Models first. Lets a caller skip building a
    /// Gemma-only failure path it knows can't be reached, or short-circuit one it knows will be.
    nonisolated static var prefersFoundationModels: Bool {
        #if DEBUG
        if forceGemmaForTesting { return false }
        #endif
        return FoundationModelEngine.isAvailable
    }

    func resetContext() async {
        if let service {
            await service.stopCompletion()
        }
        service = nil
    }

    func generate(systemPrompt: String, userMessage: String, task: LocalLLMTask, gemmaPlan: GemmaPlan = .samePrompt) async throws -> (text: String, engine: LLMEngine) {
        // Prefer Apple's on-device Foundation Models (iOS 26+, Apple Intelligence devices):
        // no bundled weights, no download, better instruction-following than Gemma 3 1B.
        // Only fall through to Gemma on failure (guardrail rejection, model not ready, etc.)
        // when a Gemma model actually exists locally — otherwise the fallback itself throws
        // LocalLLMError.modelMissing, turning one real failure into a guaranteed second one.
        #if DEBUG
        if let intercept = Self.generateInterceptForTesting {
            return try intercept(systemPrompt, userMessage, task, gemmaPlan)
        }
        #endif
        if Self.prefersFoundationModels {
            do {
                let text = try await FoundationModelEngine.generate(
                    systemPrompt: systemPrompt,
                    userMessage: userMessage,
                    task: task
                )
                return (text, .foundationModels)
            } catch {
                guard Self.isGemmaModelAvailable else { throw error }
                #if DEBUG
                // Error type only — never prompt or entry content.
                print("[llm] foundationModels failed (\(type(of: error))), falling back to gemma")
                #endif
                // Fall through to Gemma.
            }
        }

        let messages: [LlamaChatMessage]
        let grammarConfig: LlamaGrammarConfig?
        switch gemmaPlan {
        case .samePrompt:
            messages = [
                LlamaChatMessage(role: .system, content: systemPrompt),
                LlamaChatMessage(role: .user, content: userMessage)
            ]
            grammarConfig = nil
        case .grammarConstrained(let constrainedMessage, let grammar):
            messages = [LlamaChatMessage(role: .user, content: constrainedMessage)]
            grammarConfig = LlamaGrammarConfig(grammar: grammar)
        case .unsuitable:
            throw LocalLLMError.gemmaUnsuitable
        }

        await resetContext()
        let isBackground = await MainActor.run { UIApplication.shared.applicationState == .background }
        let svc = try llamaService(useGPU: !isBackground)
        defer {
            service = nil
        }
        let sampling = LlamaSamplingConfig(
            temperature: task.temperature,
            seed: UInt32.random(in: 1...UInt32.max),
            topP: 0.9,
            topK: 40,
            grammarConfig: grammarConfig
        )
        // Use streaming so we can stop immediately when Gemma emits <end_of_turn>.
        // Without this, llama.cpp doesn't recognise the token as EOG and keeps
        // generating until the full 4096-token context is exhausted (1+ hours).
        let stream: AsyncThrowingStream<String, Error>
        do {
            stream = try await svc.streamCompletion(of: messages, samplingConfig: sampling)
        } catch let error as LlamaContextError {
            await svc.stopCompletion()
            self.service = nil
            _ = error
            throw LocalLLMError.contextExhausted
        } catch {
            await svc.stopCompletion()
            self.service = nil
            throw error
        }
        var output = ""
        do {
            for try await token in stream {
                try Task.checkCancellation()
                output += token
                if output.contains("<end_of_turn>") || output.contains("<eos>")
                    || output.count > task.maxOutputChars {
                    await svc.stopCompletion()
                    break
                }
            }
        } catch let error as LlamaContextError {
            await svc.stopCompletion()
            self.service = nil
            _ = error
            throw LocalLLMError.contextExhausted
        } catch {
            await svc.stopCompletion()
            self.service = nil
            throw error
        }
        await svc.stopCompletion()
        // Guard against partial output if the stream drained normally while the task was cancelled
        // (stream producer may return nil rather than throw on cancellation).
        try Task.checkCancellation()
        let cleaned = clean(output)
        guard !cleaned.isEmpty else { throw LocalLLMError.emptyResponse }
        return (cleaned, .gemma)
    }

    /// Cheap pre-flight check: true when generation can happen right now, either via
    /// Apple's Foundation Models (no download needed) or a bundled/installed Gemma model.
    /// Callers that would otherwise silently swallow generate() errors (auto mood
    /// detection, backfill) should skip work entirely when this is false.
    nonisolated static var isModelAvailable: Bool {
        FoundationModelEngine.isAvailable || isGemmaModelAvailable
    }

    /// True when a Gemma model is bundled or already downloaded — independent of Foundation
    /// Models. Used by `generate()` to decide whether falling back to Gemma on an FM failure
    /// is worth attempting, versus surfacing the FM error directly.
    nonisolated static var isGemmaModelAvailable: Bool {
        if Bundle.main.url(forResource: modelFileName, withExtension: modelExtension) != nil {
            return true
        }
        guard let installed = try? preferredModelURL() else { return false }
        return FileManager.default.fileExists(atPath: installed.path)
    }

    static func preferredModelURL() throws -> URL {
        let directory = try modelDirectory()
        return directory
            .appendingPathComponent(modelFileName)
            .appendingPathExtension(modelExtension)
    }

    static func modelDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("Mirror", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func llamaService(useGPU: Bool = true) throws -> LlamaService {
        if let service {
            return service
        }

        let config = LlamaConfig(
            batchSize: Self.llamaBatchSize,
            maxTokenCount: 4096,
            useGPU: useGPU
        )
        // llama.cpp's default logger writes to stderr, and a grammar parse error echoes grammar
        // text — sentences from the user's journal. Silenced before every load (idempotent).
        LlamaLog.silence()
        let service = LlamaService(modelUrl: try resolvedModelURL(), config: config)
        self.service = service
        return service
    }

    /// Prompt decode batch size. A prompt that's an exact multiple of this used to hit
    /// swift-llama-cpp's empty-final-batch bug — fixed in the vendored package
    /// (Packages/SwiftLlama/PATCHES.md, #2).
    static let llamaBatchSize: UInt32 = 256

    private func resolvedModelURL() throws -> URL {
        if let bundled = Bundle.main.url(forResource: Self.modelFileName, withExtension: Self.modelExtension) {
            return bundled
        }
        let installed = try Self.preferredModelURL()
        guard FileManager.default.fileExists(atPath: installed.path) else {
            throw LocalLLMError.modelMissing(installed)
        }
        return installed
    }

    private func clean(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "<end_of_turn>", with: "")
            .replacingOccurrences(of: "<start_of_turn>model", with: "")
            .replacingOccurrences(of: "<start_of_turn>user", with: "")
            .replacingOccurrences(of: "<eos>", with: "")
            .replacingOccurrences(of: "<bos>", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripAssistantPreamble(cleaned)
    }

    private func stripAssistantPreamble(_ text: String) -> String {
        let markers = ["model\n", "model:", "<start_of_turn>model"]
        var result = text
        for marker in markers where result.lowercased().hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
