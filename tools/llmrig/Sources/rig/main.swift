import Foundation
import SwiftLlama
import llama

// Mac test rig: same llama.cpp build (b6102 xcframework), same SwiftLlama wrapper sources, same
// GGUF as the app. Generation loop mirrors SwiftLlama's Llama.swift (processPrompt +
// generateNextToken) exactly, so results transfer — plus a raw-prompt mode for prefill tests.

let args = CommandLine.arguments
let modelPath = ProcessInfo.processInfo.environment["MODEL"]!
let mode = args[1]

llama_backend_init()
llama_log_set({ _, _, _ in }, nil)
guard let model = LlamaModel(path: modelPath) else { fatalError("model load failed") }

func show(_ s: String) -> String {
    s.replacingOccurrences(of: "\n", with: "\\n")
}

func makeContext() -> LlamaContext {
    var p = llama_context_default_params()
    p.n_ctx = 4096
    p.n_batch = 256
    p.n_ubatch = 256
    p.offload_kqv = true
    return LlamaContext(model: model, parameters: p)!
}

/// Mirrors Llama.initializeCompletion(text:) + processPrompt + generateNextToken loop.
func generate(prompt: String, temperature: Float, seed: UInt32, maxChars: Int = 700, grammar: String? = nil) -> String {
    let ctx = makeContext()
    let tokens = model.tokenize(text: prompt, addBos: model.shouldAddBos(), special: true)
    let batch = LlamaBatch(initialSize: 256)
    batch.reset()
    var n: Int32 = 0
    // Same as the patched Llama.processPrompt (Packages/SwiftLlama/PATCHES.md #2).
    for (i, t) in tokens.enumerated() {
        batch.addToken(t, at: n, logits: i == tokens.count - 1)
        n += 1
        if batch.size == 256 { try! ctx.decode(batch: batch); batch.reset() }
    }
    if batch.size > 0 { try! ctx.decode(batch: batch) }
    let sampler = LlamaSampler(config: LlamaSamplingConfig(temperature: temperature, seed: seed, topP: 0.9, topK: 40, grammarConfig: grammar.map { LlamaGrammarConfig(grammar: $0) }), model: model)
    var out = ""
    var decoder = UTF8StreamDecoder()   // same as the patched Llama.generateNextToken
    while n < 4096 {
        let tok = sampler.sample(context: ctx)
        if model.isEogToken(tok) { break }
        batch.reset()
        batch.addToken(tok, at: n, logits: true)
        n += 1
        try! ctx.decode(batch: batch)
        out += decoder.append(model.pieceBytes(from: tok))
        if out.contains("<end_of_turn>") || out.contains("<eos>") || out.count > maxChars { break }
    }
    return out
}

switch mode {
case "integrity":
    let sys = try! String(contentsOfFile: args[2], encoding: .utf8)
    let user = try! String(contentsOfFile: args[3], encoding: .utf8)
    let formatted = model.applyChatTemplate(to: [
        LlamaChatMessage(role: .system, content: sys),
        LlamaChatMessage(role: .user, content: user),
    ])
    let toks = model.tokenize(text: formatted, addBos: model.shouldAddBos(), special: true)
    print("shouldAddBos=\(model.shouldAddBos()) bos=\(model.bosToken())")
    print("formatted.head=\(show(String(formatted.prefix(160))))")
    print("formatted.tail=\(show(String(formatted.suffix(120))))")
    print("tokenCount=\(toks.count)")
    print("first8=\(toks.prefix(8).map { "\($0):\(show(model.piece(from: $0, renderSpecial: true)))" })")
    print("last8=\(toks.suffix(8).map { "\($0):\(show(model.piece(from: $0, renderSpecial: true)))" })")
    print("count(105)=\(toks.filter { $0 == 105 }.count) count(106)=\(toks.filter { $0 == 106 }.count) count(bos)=\(toks.filter { $0 == model.bosToken() }.count)")
    for id: llama_token in [1, 105, 106] {
        print("token \(id): text=\(show(model.string(from: id))) isEog=\(model.isEogToken(id)) piece(noSpecial)='\(show(model.piece(from: id)))' piece(special)='\(show(model.piece(from: id, renderSpecial: true)))'")
    }
    let sot = model.tokenize(text: "<start_of_turn>", addBos: false, special: true)
    let eot = model.tokenize(text: "<end_of_turn>", addBos: false, special: true)
    print("tokenize('<start_of_turn>')=\(sot) tokenize('<end_of_turn>')=\(eot)")
case "gen":
    // gen <promptFile(raw, already templated)> <temp> <n>
    let prompt = try! String(contentsOfFile: args[2], encoding: .utf8)
    let temp = Float(args[3])!
    let runs = Int(args[4])!
    for i in 1...runs {
        let text = generate(prompt: prompt, temperature: temp, seed: UInt32(1000 + i))
        print("[\(i)] \(show(text.replacingOccurrences(of: "<end_of_turn>", with: "")))")
        fflush(stdout)
    }
case "gengrammar":
    let prompt = try! String(contentsOfFile: args[2], encoding: .utf8)
    let grammar = try! String(contentsOfFile: args[3], encoding: .utf8)
    let temp = Float(args[4])!
    let runs = Int(args[5])!
    let maxChars = args.count > 6 ? Int(args[6])! : 700   // app: .dailyNudge 700, .weeklyDigest/.monthlyReport 2800
    for i in 1...runs {
        let text = generate(prompt: prompt, temperature: temp, seed: UInt32(1000 + i), maxChars: maxChars, grammar: grammar)
        print("[\(i)] \(show(text))")
        fflush(stdout)
    }
case "vcount":
    // Tokenizer-only load (what LocalLLMService's batch-boundary guard uses) vs the full model.
    guard let vocab = LlamaModel.vocabularyOnly(path: modelPath) else { print("vocab-only load returned nil"); exit(1) }
    let prompt = try! String(contentsOfFile: args[2], encoding: .utf8)
    let full = model.tokenize(text: prompt, addBos: model.shouldAddBos(), special: true).count
    let v = vocab.tokenize(text: prompt, addBos: vocab.shouldAddBos(), special: true).count
    let msgs = [LlamaChatMessage(role: .user, content: "hello there")]
    print("full=\(full) vocabOnly=\(v) templateEqual=\(vocab.applyChatTemplate(to: msgs) == model.applyChatTemplate(to: msgs))")
case "count":
    let prompt = try! String(contentsOfFile: args[2], encoding: .utf8)
    print(model.tokenize(text: prompt, addBos: model.shouldAddBos(), special: true).count)
case "template":
    // template <sysFile> <userFile> -> prints templated prompt exactly as the app builds it
    let sys = try! String(contentsOfFile: args[2], encoding: .utf8)
    let user = try! String(contentsOfFile: args[3], encoding: .utf8)
    print(model.applyChatTemplate(to: [
        LlamaChatMessage(role: .system, content: sys),
        LlamaChatMessage(role: .user, content: user),
    ]), terminator: "")
default:
    fatalError("unknown mode")
}
