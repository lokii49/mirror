import Foundation

// Round 27 (RUBRIC_FM.md): Ask evidence quotes judged by `locate` (before) and `locateSentence` (after) on the same
// saved ask_quotes outputs. No model runs.
// replay27 <results.jsonl> <dumpdir>   dumpdir holds <label>_user.txt (the ask_quotes user message)

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) { print(s) }
}

func askTexts(_ user: String) -> [String] {
    guard let r = user.range(of: "Most relevant entries:\n") else { return [] }
    let block = String(user[r.upperBound...]).components(separatedBy: "\n\nQuestion:")[0]
    return block.components(separatedBy: "\n---\n").compactMap { b in
        var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { return nil }
        lines.removeFirst(2)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func shown(_ quotes: [String], texts: [String], whole: Bool) -> [String] {
    var out: [String] = []
    for q in quotes {
        guard let found = whole ? FMDailyGuard.locateSentence(quote: q, in: texts) : FMDailyGuard.locate(quote: q, in: texts),
              !out.contains(where: { $0.contains(found.quote) || found.quote.contains($0) }) else { continue }
        out.append(found.quote)
    }
    return out
}

@main struct Replay27 {
    static func main() {
        let a = CommandLine.arguments
        guard a.count == 3, let data = try? String(contentsOfFile: a[1], encoding: .utf8) else {
            print("usage: replay27 <results.jsonl> <dumpdir>"); return
        }
        for line in data.split(separator: "\n") {
            guard let rec = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let label = rec["case"] as? String, let raws = rec["raws"] as? [[String: String]], let raw = raws.first else { continue }
            let user = (try? String(contentsOfFile: "\(a[2])/\(label)_user.txt", encoding: .utf8)) ?? ""
            let texts = askTexts(user)
            let quotes = [raw["quote1"] ?? "", raw["quote2"] ?? ""]
            emit(["case": label, "i": rec["i"] ?? 0, "raw": quotes,
                  "before": shown(quotes, texts: texts, whole: false), "after": shown(quotes, texts: texts, whole: true)])
        }
    }
}
