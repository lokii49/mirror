import XCTest
import SwiftLlama

// SwiftLlama patch 7 (LlamaEmbedder) on the app's own llama.cpp build. Needs an EmbeddingGemma
// GGUF (ggml-org/embeddinggemma-300M-GGUF, Q8_0) at EMBEDDING_MODEL_PATH; skips without it.
// Synthetic text only.
final class LlamaEmbedderTests: XCTestCase {

    private static let query = "task: search result | query: "
    private static let document = "title: none | text: "

    private func embedder() throws -> LlamaEmbedder {
        guard let path = ProcessInfo.processInfo.environment["EMBEDDING_MODEL_PATH"],
              FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Set EMBEDDING_MODEL_PATH to an EmbeddingGemma GGUF")
        }
        return try LlamaEmbedder(path: path)
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    func test_vectorsAreNormalizedAndModelSized() throws {
        let embedder = try embedder()
        XCTAssertEqual(embedder.dimension, 768)
        let vector = try embedder.embed(Self.document + "Went to the gym before work.")
        XCTAssertEqual(vector.count, 768)
        XCTAssertEqual(vector.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 1e-3)
        XCTAssertEqual(try embedder.embed(Self.document + "Went to the gym before work."), vector, "deterministic")
    }

    /// The rig's paraphrase case: no shared keyword between question and answer.
    func test_paraphrasedQuestionFindsTheRightEntry() throws {
        let embedder = try embedder()
        let entries = [
            "Jogged a slow 5k along the river this morning.",
            "Rent went up by 120 a month, sat with the spreadsheet for an hour.",
            "The bus didn't move for ten minutes at the roundabout.",
        ]
        let vectors = try entries.map { try embedder.embed(Self.document + $0) }
        let question = try embedder.embed(Self.query + "Have I been working out?")
        let best = vectors.indices.max { cosine(question, vectors[$0]) < cosine(question, vectors[$1]) }
        XCTAssertEqual(best, 0)
        let money = try embedder.embed(Self.query + "How are my finances?")
        XCTAssertEqual(vectors.indices.max { cosine(money, vectors[$0]) < cosine(money, vectors[$1]) }, 1)
    }

    func test_textOverTheTokenLimitThrowsInsteadOfTruncating() throws {
        guard let path = ProcessInfo.processInfo.environment["EMBEDDING_MODEL_PATH"],
              FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Set EMBEDDING_MODEL_PATH to an EmbeddingGemma GGUF")
        }
        let small = try LlamaEmbedder(path: path, maxTokens: 16)
        XCTAssertThrowsError(try small.embed(String(repeating: "walk by the lake ", count: 40)))
    }
}
