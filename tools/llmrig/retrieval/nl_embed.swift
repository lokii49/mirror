// Embeds the corpus and queries with Apple's on-device NaturalLanguage embeddings, as the app could
// at no size cost: NLEmbedding.sentenceEmbedding (per language) and NLContextualEmbedding (per script,
// mean-pooled token vectors, whole entry and per sentence).
// Usage: swift nl_embed.swift out/corpus_400.jsonl cases/queries.tsv out/nl_vectors.json
import Foundation
import NaturalLanguage

let args = CommandLine.arguments
guard args.count == 4 else { fatalError("usage: nl_embed.swift corpus.jsonl queries.tsv out.json") }

struct Item { let key: String; let lang: String; let text: String }

var items: [Item] = []
for line in try String(contentsOfFile: args[1], encoding: .utf8).split(separator: "\n") {
    let o = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    items.append(Item(key: o["id"] as! String, lang: o["lang"] as! String, text: o["text"] as! String))
}
for (i, line) in try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").enumerated() where i > 0 {
    let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    items.append(Item(key: "q:" + c[0], lang: c[2], text: c[4]))
}

func sentences(_ text: String) -> [String] {
    let t = NLTokenizer(unit: .sentence)
    t.string = text
    var out: [String] = []
    t.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
        let s = text[r].trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { out.append(s) }
        return true
    }
    return out.isEmpty ? [text] : out
}

var sentenceModels: [String: NLEmbedding] = [:]
var contextualModels: [String: NLContextualEmbedding] = [:]
var report: [String: String] = [:]

func sentenceModel(_ lang: String) -> NLEmbedding? {
    if let m = sentenceModels[lang] { return m }
    let m = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: lang))
    report["nls." + lang] = m.map { "dim \($0.dimension)" } ?? "unavailable"
    if let m { sentenceModels[lang] = m }
    return m
}

func contextualModel(_ lang: String) -> NLContextualEmbedding? {
    if let m = contextualModels[lang] { return m }
    guard let m = NLContextualEmbedding(language: NLLanguage(rawValue: lang)) else {
        report["nlc." + lang] = "unavailable"; return nil
    }
    if !m.hasAvailableAssets {
        let done = DispatchSemaphore(value: 0)
        m.requestAssets { result, error in
            report["nlc." + lang + ".assets"] = "\(result.rawValue) \(error.map { "\($0)" } ?? "")"
            done.signal()
        }
        done.wait()
    }
    do { try m.load() } catch { report["nlc." + lang] = "load failed: \(error)"; return nil }
    report["nlc." + lang] = "model \(m.modelIdentifier) dim \(m.dimension) maxSeq \(m.maximumSequenceLength)"
    contextualModels[lang] = m
    return m
}

func meanPooled(_ m: NLContextualEmbedding, _ text: String, _ lang: String) -> [Double]? {
    guard let r = try? m.embeddingResult(for: text, language: NLLanguage(rawValue: lang)) else { return nil }
    var sum = [Double](repeating: 0, count: m.dimension)
    var n = 0
    r.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { v, _ in
        for i in 0..<v.count { sum[i] += v[i] }
        n += 1
        return true
    }
    return n == 0 ? nil : sum.map { $0 / Double(n) }
}

var nls: [String: Any] = [:], nlcFull: [String: Any] = [:], nlcSent: [String: Any] = [:], nlcModel: [String: String] = [:]
for item in items {
    if let m = sentenceModel(item.lang), let v = m.vector(for: item.text) { nls[item.key] = v }
    if let m = contextualModel(item.lang) {
        nlcModel[item.key] = m.modelIdentifier
        if let v = meanPooled(m, item.text, item.lang) { nlcFull[item.key] = v }
        let vs = sentences(item.text).compactMap { meanPooled(m, $0, item.lang) }
        if !vs.isEmpty { nlcSent[item.key] = vs }
    }
}

let out: [String: Any] = ["report": report, "nls": nls, "nlc_full": nlcFull, "nlc_sent": nlcSent, "nlc_model": nlcModel]
try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: args[3]))
for (k, v) in report.sorted(by: { $0.key < $1.key }) { print(k, v) }
print("items \(items.count), nls \(nls.count), nlc \(nlcFull.count)")
