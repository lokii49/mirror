import XCTest
import NaturalLanguage
import SwiftLlama
@testable import mirror

// Dumps Gemma Ask's real prompt, grammar and every candidate sentence for the Gemma Ask pick round
// (tools/llmrig/ask/RUBRIC.md). No model generates here; the rig runs Gemma on the dumped files.
// Synthetic pool only (tools/llmrig/ask/build_pool.py).
//
// TEST_RUNNER_ASK_POOL=<pool.jsonl> TEST_RUNNER_ASK_QUERIES=<queries.tsv> TEST_RUNNER_HARNESS_DUMP_DIR=<dir>
// TEST_RUNNER_ASK_RETRIEVAL=semantic|keyword. Semantic copies mirror/LocalModels/embeddinggemma-300M-Q8_0.gguf
// into the simulator's model directory and indexes the pool, and leaves it there (later Ask tests in that
// simulator then rank with it); keyword removes it.
final class AskPickRigDump: XCTestCase {

    private struct PoolRow: Decodable {
        let id: String
        let text: String
        let date: String
    }

    func test_dumpGemmaAskPicksForRig() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let poolPath = env["ASK_POOL"], let queriesPath = env["ASK_QUERIES"], let dir = env["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set ASK_POOL, ASK_QUERIES and HARNESS_DUMP_DIR to dump")
        }
        let semantic = env["ASK_RETRIEVAL"] != "keyword"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        iso.timeZone = .current
        var corpusID: [UUID: String] = [:]
        let entries: [Entry] = try String(contentsOfFile: poolPath, encoding: .utf8)
            .split(separator: "\n").map { line in
                let row = try JSONDecoder().decode(PoolRow.self, from: Data(line.utf8))
                let entry = Entry(text: row.text)
                entry.createdAt = try XCTUnwrap(iso.date(from: row.date), row.date)
                corpusID[entry.id] = row.id
                return entry
            }
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let documents = sorted.map { SemanticSearchService.Document(id: $0.id, text: $0.insightContext) }

        let modelURL = try SemanticSearchService.modelFileURL()
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let devModel = projectRoot.appendingPathComponent("mirror/LocalModels").appendingPathComponent(SemanticSearchService.modelFileName)
        if semantic {
            if !FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: devModel, to: modelURL)
            }
            await SemanticSearchService.shared.refresh(documents)
        } else {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let embedder = try LlamaEmbedder(path: devModel.path)

        LocalLLMService.forceGemmaForTesting = true
        defer {
            LocalLLMService.forceGemmaForTesting = false
            LocalLLMService.generateInterceptForTesting = nil
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "d MMM"
        let hasWordEmbedding = NLEmbedding.wordEmbedding(for: .english) != nil

        let queryLines = try String(contentsOfFile: queriesPath, encoding: .utf8).split(separator: "\n").dropFirst()
        for line in queryLines {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let (qid, question) = (fields[0], fields[4])

            let semanticIDs = await SemanticSearchService.shared.search(question: question, in: documents, limit: 10)
            XCTAssertEqual(semanticIDs != nil, semantic, "\(qid): retrieval mode")

            // The pool ask() builds. Since 2026-10-24 English Ask on Gemma shows rankedAskAnswer and no
            // longer sends this plan; it is dumped as the round's S0 (what shipped before).
            let relevant = await InsightService.askRelevantEntries(question: question, newestFirst: sorted)
            let relevantIDs = Set(relevant.map(\.id))
            let pool = relevant + sorted.filter { !relevantIDs.contains($0.id) }.prefix(8)
            let plan = InsightService.groundedAskPlan(question: question, pool: pool, languageCode: "en")
            guard case .grammarConstrained(let user, let grammar) = plan.plan else {
                XCTFail("\(qid): no grammar-constrained plan"); continue
            }
            let shipped = (user: user, grammar: grammar)
            let s0 = Set(plan.quoteOptions)

            let terms = InsightService.askTerms(for: question)
            let query = try embedder.embed(SemanticSearchService.queryPrefix + question)
            var seen = Set<String>()
            var sentences: [[String: Any]] = []
            for entry in pool {
                for quote in InsightService.groundedQuoteCandidates(of: entry) where seen.insert(quote).inserted {
                    let option = "On \(dayFormatter.string(from: entry.createdAt)), you wrote, \"\(quote)\""
                    let stems = Set(quote.lowercased().split { !$0.isLetter && $0 != "'" }.map { InsightService.askStem(String($0)) })
                    let vector = try embedder.embed(SemanticSearchService.documentPrefix + quote)
                    sentences.append([
                        "id": corpusID[entry.id] ?? "?",
                        "quote": quote,
                        "option": option,
                        "inS0": s0.contains(option),
                        "inPrompt": shipped.user.contains(quote),
                        "lex": stems.intersection(terms).count,
                        "sem": Double(zip(query, vector).reduce(0) { $0 + $1.0 * $1.1 }),
                    ])
                }
            }
            let record: [String: Any] = [
                "qid": qid,
                "question": question,
                "retrieval": semantic ? "semantic" : "keyword",
                "wordEmbedding": hasWordEmbedding,
                "pool": pool.map { corpusID[$0.id] ?? "?" },
                "s0Options": plan.quoteOptions,
                "sentences": sentences,
            ]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "\(dir)/\(qid).json"))
            try shipped.user.write(toFile: "\(dir)/\(qid)_user.txt", atomically: true, encoding: .utf8)
            try shipped.grammar.write(toFile: "\(dir)/\(qid)_s0.gbnf", atomically: true, encoding: .utf8)
        }
    }

    /// RUBRIC_FM.md round 28: scores every candidate sentence of a Foundation Models Ask answer against the answer
    /// (EmbeddingGemma, and shared `askTerms` stems) and against the question. TEST_RUNNER_ASK_EVIDENCE_IN=<jsonl of
    /// {id, question, answer, sentences}> TEST_RUNNER_HARNESS_DUMP_DIR=<dir> -> <dir>/evidence_scores.jsonl.
    func test_scoreAskEvidenceForRig() throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["ASK_EVIDENCE_IN"], let dir = env["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set ASK_EVIDENCE_IN and HARNESS_DUMP_DIR to score")
        }
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let embedder = try LlamaEmbedder(path: projectRoot.appendingPathComponent("mirror/LocalModels")
            .appendingPathComponent(SemanticSearchService.modelFileName).path)
        func score(_ query: String, _ sentence: String) throws -> Double {
            let q = try embedder.embed(SemanticSearchService.queryPrefix + query)
            let d = try embedder.embed(SemanticSearchService.documentPrefix + sentence)
            return Double(zip(q, d).reduce(0) { $0 + $1.0 * $1.1 })
        }
        func stems(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && $0 != "'" }.map { InsightService.askStem(String($0)) })
        }
        var out = ""
        for line in try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n") {
            let rec = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            let question = try XCTUnwrap(rec["question"] as? String), answer = try XCTUnwrap(rec["answer"] as? String)
            let terms = InsightService.askTerms(for: answer)
            let scored: [[String: Any]] = try (rec["sentences"] as? [String] ?? []).map { s in
                ["quote": s, "semA": try score(answer, s), "semQ": try score(question, s), "lexA": stems(s).intersection(terms).count]
            }
            let data = try JSONSerialization.data(withJSONObject: ["id": rec["id"] ?? "", "scores": scored], options: [.sortedKeys])
            out += String(decoding: data, as: UTF8.self) + "\n"
        }
        try out.write(toFile: "\(dir)/evidence_scores.jsonl", atomically: true, encoding: .utf8)
    }
}
