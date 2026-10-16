import Foundation

// Round 23 (RUBRIC_FM.md): judges saved model outputs with the guard it is built with, so the old and new
// FMDailyGuard / FMDigestGuard can be compared on identical outputs. No model runs.
// replay23 daily <results.jsonl> <dumpdir>    every daily attempt: the insight the guard keeps, or null
// replay23 digest <results.jsonl> <dumpdir>   every W3 digest: assembled sections + app-fixed list

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) { print(s) }
}

func blocks(_ user: String, after marker: String, until end: String) -> [(text: String, mood: String, date: String)] {
    let head = user.components(separatedBy: end)[0]
    guard let r = head.range(of: marker) else { return [] }
    var out: [(String, String, String)] = []
    for b in String(head[r.upperBound...]).components(separatedBy: "\n---\n") {
        var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { continue }
        let date = lines[0].components(separatedBy: " - ").dropFirst().joined(separator: " - ")
        let mood = lines[1].replacingOccurrences(of: "Mood: ", with: "").components(separatedBy: ".")[0]
        lines.removeFirst(2)
        out.append((lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), mood, date))
    }
    return out
}

@main struct Replay {
    static func main() {
        let a = CommandLine.arguments
        guard a.count == 4, let data = try? String(contentsOfFile: a[2], encoding: .utf8) else {
            print("usage: replay23 daily|digest <results.jsonl> <dumpdir>"); return
        }
        for line in data.split(separator: "\n") {
            guard let rec = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let label = rec["case"] as? String, let raws = rec["raws"] as? [[String: String]] else { continue }
            let variant = rec["variant"] as? String ?? ""
            if a[1] == "daily" {
                let user = (try? String(contentsOfFile: "\(a[3])/\(label)_fm_user.txt", encoding: .utf8)) ?? ""
                let all = blocks(user, after: "Recent entries:\n", until: "Long-term context:")
                let today = all.filter { $0.date == all.first?.date }.map { FMDailyGuard.Source(text: $0.text, mood: $0.mood) }
                for (k, raw) in raws.enumerated() {
                    let v = FMDailyGuard.verify(quote: raw["quote"] ?? "", insight: raw["insight"] ?? "", sources: today)
                    emit(["case": label, "variant": variant, "i": rec["i"] ?? 0, "attempt": k, "insight": raw["insight"] ?? "", "kept": v?.insight ?? NSNull()])
                }
            } else {
                let user = (try? String(contentsOfFile: "\(a[3])/\(label)_user.txt", encoding: .utf8)) ?? ""
                let src = blocks(user, after: "Recent entries:\n", until: "Long-term context:").map { FMDailyGuard.Source(text: $0.text, mood: $0.mood) }
                let drafts = raws.map { r in FMDigestGuard.Draft(theme: r["theme"] ?? "", energyQuote: r["energyQuote"] ?? "", energyRead: r["energyRead"] ?? "",
                    buildingQuote: r["buildingQuote"] ?? "", buildingRead: r["buildingRead"] ?? "", watchQuote: r["watchQuote"] ?? "",
                    watchRead: r["watchRead"] ?? "", boost: r["boost"] ?? "", nextWeek: r["nextWeek"] ?? "") }
                // As the app: drafts accumulate until all six sections pass, then the app fills the rest.
                var used: [FMDigestGuard.Draft] = []
                var verified: FMDigestGuard.Verified?
                for d in drafts { used.append(d); if let v = FMDigestGuard.merge(used, sources: src) { verified = v; break } }
                var out: [String: Any] = ["case": label, "i": rec["i"] ?? 0]
                if let v = verified { out["sections"] = v.sections; out["fixed"] = [String]() }
                else if let asm = FMDigestGuard.assemble(used, sources: src) { out["sections"] = asm.verified.sections; out["fixed"] = asm.fixed.map(\.rawValue) }
                emit(out)
            }
        }
    }
}
