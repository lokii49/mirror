import Foundation
import SwiftLlama
import UIKit

enum LocalLLMError: LocalizedError {
    case modelMissing(URL)
    case emptyResponse
    case contextExhausted

    var errorDescription: String? {
        switch self {
        case .modelMissing(let url):
            return String(localized: "Local AI model not installed. Add gemma-3-1b-it-Q4_K_M.gguf to \(url.path).")
        case .emptyResponse:
            return String(localized: "Local AI returned an empty response.")
        case .contextExhausted:
            return String(localized: "Not enough device memory right now. Mirror will generate this overnight while your phone is charging.")
        }
    }
}

enum LocalLLMTask {
    case dailyNudge
    case weeklyDigest
    case monthlyReport
    case ask
    case emotion

    nonisolated var temperature: CFloat {
        switch self {
        case .emotion: return 0.1
        case .dailyNudge: return 0.45
        case .ask: return 0.45
        case .weeklyDigest: return 0.55
        case .monthlyReport: return 0.55
        }
    }

    // Hard cap on accumulated output chars — prevents infinite generation when
    // Gemma's <end_of_turn> token isn't recognised as EOG by llama.cpp.
    nonisolated var maxOutputChars: Int {
        switch self {
        case .emotion: return 30
        case .dailyNudge: return 700
        case .ask: return 1000
        case .weeklyDigest: return 2800
        case .monthlyReport: return 2800
        }
    }
}

actor LocalLLMService {
    static let shared = LocalLLMService()

    static let modelFileName = "gemma-3-1b-it-Q4_K_M"
    static let modelExtension = "gguf"

    private var service: LlamaService?

    private init() {}

    func resetContext() async {
        if let service {
            await service.stopCompletion()
        }
        service = nil
    }

    func generate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        await resetContext()
        let isBackground = await MainActor.run { UIApplication.shared.applicationState == .background }
        let svc = try llamaService(useGPU: !isBackground)
        defer {
            service = nil
        }
        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: userMessage)
        ]
        let sampling = LlamaSamplingConfig(
            temperature: task.temperature,
            seed: UInt32.random(in: 1...UInt32.max),
            topP: 0.9,
            topK: 40
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
        return cleaned
    }

    /// Cheap pre-flight check: true when the model is bundled or already installed.
    /// Callers that would otherwise silently swallow generate() errors (auto mood
    /// detection, backfill) should skip work entirely when this is false.
    nonisolated static var isModelAvailable: Bool {
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

        let modelURL: URL
        if let bundled = Bundle.main.url(
            forResource: Self.modelFileName,
            withExtension: Self.modelExtension
        ) {
            modelURL = bundled
        } else {
            let installed = try Self.preferredModelURL()
            guard FileManager.default.fileExists(atPath: installed.path) else {
                throw LocalLLMError.modelMissing(installed)
            }
            modelURL = installed
        }

        let config = LlamaConfig(
            batchSize: 256,
            maxTokenCount: 4096,
            useGPU: useGPU
        )
        let service = LlamaService(modelUrl: modelURL, config: config)
        self.service = service
        return service
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
