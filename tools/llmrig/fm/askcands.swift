import Foundation

// Round 28 (RUBRIC_FM.md): candidate sentences of a dumped Ask prompt, and the shipped quote call's picks as the
// app shows them. No model runs. Build with FMDailyGuard.swift + FMDigestGuard.swift.
// askcands cands <user.txt>                -> {"sources": [{day, text}], "sentences": [{day, quote}]}
// askcands shown <user.txt> <q1> <q2>      -> {"shown": [{day, quote}]}  (locateSentence, as askEvidenceQuotes)

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) { print(s) }
}

/// Every entry the Ask prompt shows: "Most relevant entries" blocks and "Representative older excerpts" lines.
func sources(_ user: String) -> [(day: String, text: String)] {
    var out: [(String, String)] = []
    if let r = user.range(of: "Representative older excerpts:\n") {
        for line in String(user[r.upperBound...]).components(separatedBy: "\n") {
            guard line.hasPrefix("- "), let colon = line.range(of: ": ") else { break }
            let date = String(line[line.index(line.startIndex, offsetBy: 2)..<colon.lowerBound])
            out.append((date.split(separator: " ").prefix(2).joined(separator: " "), String(line[colon.upperBound...])))
        }
    }
    if let r = user.range(of: "Most relevant entries:\n") {
        let block = String(user[r.upperBound...]).components(separatedBy: "\n\nQuestion:")[0]
        for b in block.components(separatedBy: "\n---\n") {
            var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { continue }
            let date = lines[0].components(separatedBy: " - ").dropFirst().joined(separator: " - ")
            lines.removeFirst(2)
            out.append((date.split(separator: " ").prefix(2).joined(separator: " "),
                        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
    return out
}

@main struct AskCands {
    static func main() {
        let a = CommandLine.arguments
        guard a.count >= 3, let user = try? String(contentsOfFile: a[2], encoding: .utf8) else {
            print("usage: askcands cands|shown <user.txt> [q1 q2]"); return
        }
        let src = sources(user)
        switch a[1] {
        case "cands":
            var seen = Set<String>()
            var sentences: [[String: String]] = []
            for s in src {
                for q in FMDigestGuard.quotableSentences(of: s.text) where seen.insert(q).inserted {
                    sentences.append(["day": s.day, "quote": q])
                }
            }
            emit(["sources": src.map { ["day": $0.day, "text": $0.text] }, "sentences": sentences])
        case "shown":
            var shown: [[String: String]] = []
            for q in a.dropFirst(3) {
                guard let found = FMDailyGuard.locateSentence(quote: q, in: src.map(\.text)),
                      !shown.contains(where: { ($0["quote"] ?? "").contains(found.quote) || found.quote.contains($0["quote"] ?? "") }) else { continue }
                shown.append(["day": src[found.index].day, "quote": found.quote])
            }
            emit(["shown": shown])
        default:
            print("unknown mode")
        }
    }
}
