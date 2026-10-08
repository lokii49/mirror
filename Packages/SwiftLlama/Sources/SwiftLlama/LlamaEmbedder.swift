//
//  LlamaEmbedder.swift
//  mirror patch 7: sentence embeddings (EmbeddingGemma) through llama.cpp's embedding API.
//

import Foundation
import llama

/// One embedding model in its own context: non-causal, the whole text in one ubatch, mean-pooled
/// by the model's own pooling layers. Built for EmbeddingGemma (`gemma-embedding`, llama.cpp
/// b6750+), verified against llama-server at mean cosine 1.00000 (tools/llmrig/retrieval).
///
/// Nothing here logs the text, tokens or vectors: the input is journal text.
public final class LlamaEmbedder {

    public enum EmbedderError: Error {
        case modelLoad
        case contextInit
        case tooLong(tokens: Int, limit: Int)
        case decode(Int32)
        case noPooledOutput
    }

    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let context: OpaquePointer
    /// Tokens per text, special tokens included. Longer text throws `tooLong`; callers truncate.
    public let maxTokens: Int
    public let dimension: Int

    public init(path: String, maxTokens: Int = 2_048) throws {
        var modelParameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #endif
        guard let model = llama_model_load_from_file(path, modelParameters) else { throw EmbedderError.modelLoad }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_model_free(model)
            throw EmbedderError.modelLoad
        }
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(maxTokens)
        contextParameters.n_batch = UInt32(maxTokens)
        contextParameters.n_ubatch = UInt32(maxTokens)   // non-causal: a text can't span ubatches
        contextParameters.embeddings = true
        guard let context = llama_init_from_model(model, contextParameters) else {
            llama_model_free(model)
            throw EmbedderError.contextInit
        }
        self.model = model
        self.vocab = vocab
        self.context = context
        self.maxTokens = maxTokens
        self.dimension = Int(llama_model_n_embd(model))
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    /// Token count with special tokens, for callers that budget text before `embed`.
    public func tokenCount(_ text: String) -> Int {
        tokens(text).count
    }

    /// L2-normalized embedding of `text`. Callers add the model's task prefix themselves
    /// (EmbeddingGemma: "task: search result | query: " / "title: none | text: ").
    public func embed(_ text: String) throws -> [Float] {
        let tokens = tokens(text)
        guard tokens.count <= maxTokens else { throw EmbedderError.tooLong(tokens: tokens.count, limit: maxTokens) }
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]![0] = 0
            batch.logits[index] = 1
        }
        batch.n_tokens = Int32(tokens.count)
        llama_memory_clear(llama_get_memory(context), true)
        let status = llama_decode(context, batch)
        guard status == 0 else { throw EmbedderError.decode(status) }
        guard let pooled = llama_get_embeddings_seq(context, 0) else { throw EmbedderError.noPooledOutput }
        let vector = (0..<dimension).map { pooled[$0] }
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? vector.map { $0 / norm } : vector
    }

    private func tokens(_ text: String) -> [llama_token] {
        let byteCount = text.utf8.count
        var buffer = [llama_token](repeating: 0, count: byteCount + 8)
        let count = llama_tokenize(vocab, text, Int32(byteCount), &buffer, Int32(buffer.count), true, false)
        return count > 0 ? Array(buffer.prefix(Int(count))) : []
    }
}
