import Foundation

// Round 13 (RUBRIC_FM.md): replays FMDailyGuard over the raw attempts fmrig recorded, the way the app
// does (first attempt the guard accepts is shown; none -> fallback). Built once with the current
// FMDailyGuard.swift and once with the one before 39fcab8, so both judge identical model outputs.
// replay13 <results.jsonl> <dumpdir>   -> one JSON line per run on stdout

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) { print(s) }
}

/// Same as fmrig's: today's entries from a dumped "Daily reflection context" prompt.
func todaySources(_ user: String) -> [FMDailyGuard.Source] {
    let head = user.components(separatedBy: "Long-term context:")[0]
    guard let r = head.range(of: "Recent entries:\n") else { return [] }
    let blocks = String(head[r.upperBound...]).components(separatedBy: "\n---\n")
    var date: String?
    var out: [FMDailyGuard.Source] = []
    for b in blocks {
        var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { continue }
        let d = lines[0].components(separatedBy: " - ").dropFirst().joined(separator: " - ")
        if date == nil { date = d }
        guard d == date else { continue }
        let mood = lines[1].replacingOccurrences(of: "Mood: ", with: "").components(separatedBy: ".")[0]
        lines.removeFirst(2)
        out.append(FMDailyGuard.Source(text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), mood: mood))
    }
    return out
}

@main struct Replay {
    static func main() {
        let a = CommandLine.arguments
        guard a.count == 3, let data = try? String(contentsOfFile: a[1], encoding: .utf8) else {
            print("usage: replay13 <results.jsonl> <dumpdir>"); return
        }
        for line in data.split(separator: "\n") {
            guard let rec = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let label = rec["case"] as? String, let i = rec["i"] else { continue }
            var out: [String: Any] = ["case": label, "i": i]
            guard let raws = rec["raws"] as? [[String: String]] else {
                out["error"] = rec["error"] ?? "no raws"; emit(out); continue
            }
            let user = (try? String(contentsOfFile: "\(a[2])/\(label)_fm_user.txt", encoding: .utf8)) ?? ""
            let sources = todaySources(user)
            var shown: FMDailyGuard.Verified?
            var attempt = 0
            for raw in raws {
                attempt += 1
                if let v = FMDailyGuard.verify(quote: raw["quote"] ?? "", insight: raw["insight"] ?? "", sources: sources) { shown = v; break }
            }
            if let v = shown {
                out["attempt"] = attempt
                out["quote"] = v.quote
                out["insight"] = v.insight
                out["dropped"] = v.droppedSentences
            } else {
                out["fallback"] = true
            }
            emit(out)
        }
    }
}
