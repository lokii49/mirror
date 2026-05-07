import Foundation
import SwiftLlama

enum LocalLLMError: LocalizedError {
    case modelMissing(URL)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelMissing(let url):
            return "Local AI model not installed. Add Qwen2.5-1.5B-Instruct-Q4_K_M.gguf to \(url.path)."
        case .emptyResponse:
            return "Local AI returned an empty response."
        }
    }
}

enum LocalLLMTask {
    case dailyNudge
    case weeklyDigest
    case ask
    case emotion

    nonisolated var temperature: CFloat {
        switch self {
        case .emotion: return 0.1
        case .dailyNudge: return 0.45
        case .ask: return 0.45
        case .weeklyDigest: return 0.55
        }
    }
}

actor LocalLLMService {
    static let shared = LocalLLMService()

    static let modelFileName = "Qwen2.5-1.5B-Instruct-Q4_K_M"
    static let modelExtension = "gguf"

    private var service: LlamaService?

    private init() {}

    func generate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        let service = try llamaService()
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
        let response: String
        do {
            response = try await service.respond(to: messages, samplingConfig: sampling)
        } catch {
            self.service = nil
            throw error
        }
        let cleaned = clean(response)
        guard !cleaned.isEmpty else { throw LocalLLMError.emptyResponse }
        return cleaned
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

    private func llamaService() throws -> LlamaService {
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
            useGPU: true
        )
        let service = LlamaService(modelUrl: modelURL, config: config)
        self.service = service
        return service
    }

    private func clean(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|endoftext|>", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripAssistantPreamble(cleaned)
    }

    private func stripAssistantPreamble(_ text: String) -> String {
        let markers = ["assistant\n", "assistant:", "<|assistant|>", "<|im_start|>assistant"]
        var result = text
        for marker in markers where result.lowercased().hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
