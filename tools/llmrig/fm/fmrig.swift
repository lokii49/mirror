import FoundationModels
import Foundation

// fmrig <variant> <system.txt> <user.txt> <label> <N> [temperature]
// Variants: free (plain respond, the shipped way), v1 (quote + insight + suggestion),
// v2 (v1 + connection to an earlier entry). One JSON object per line on stdout.

@Generable struct DailyV1 {
    @Guide(description: "ONE sentence copied word for word, with the same punctuation, from TODAY's entry: the one that shows the biggest thing that happened to them or how they felt")
    var quote: String
    @Guide(description: "One or two sentences speaking to the person as 'you': what this seems to mean for them, a feeling, need or tension that their own words support. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
    @Guide(description: "Only if their mood is hard: one small action that uses a specific thing named in the quoted sentence. Otherwise an empty string")
    var suggestion: String
}

@Generable struct DailyV2 {
    @Guide(description: "ONE sentence copied word for word, with the same punctuation, from TODAY's entry: the one that shows the biggest thing that happened to them or how they felt")
    var quote: String
    @Guide(description: "One or two sentences speaking to the person as 'you': what this seems to mean for them, a feeling, need or tension that their own words support. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
    @Guide(description: "ONE sentence copied word for word from an EARLIER entry that connects to today, or an empty string if no earlier entry truly connects")
    var earlierQuote: String
    @Guide(description: "If earlierQuote is not empty: one sentence saying how that earlier sentence and today's connect. Otherwise an empty string")
    var connection: String
    @Guide(description: "Only if their mood is hard: one small action that uses a specific thing named in the quoted sentence. Otherwise an empty string")
    var suggestion: String
}

@Generable struct DailyV1bHard {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
    var quote: String
    @Guide(description: "One or two sentences speaking to the person as 'you': what this seems to mean for them, using only feelings they wrote or plainly showed. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
    @Guide(description: "One small practical thing they could do soon, using a person, task or item they named in today's entry")
    var suggestion: String
}

@Generable struct DailyV1bEasy {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
    var quote: String
    @Guide(description: "One or two sentences speaking to the person as 'you': what this seems to mean for them, using only feelings they wrote or plainly showed. If the day was ordinary, say so. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
}

func tidy(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = t.first else { return t }
    t = first.uppercased() + t.dropFirst()
    if let last = t.last, !".!?…".contains(last) { t += "." }
    return t
}

func norm(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
     .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
     .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
}

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) { print(s) }
}

@main struct Rig {
    static func main() async {
        let a = CommandLine.arguments
        guard a.count >= 6, let n = Int(a[5]) else { print("usage: fmrig <variant> <system.txt> <user.txt> <label> <N> [temp]"); return }
        let variant = a[1], label = a[4]
        let temp = a.count > 6 ? Double(a[6]) ?? 0.45 : 0.45
        let system = try! String(contentsOfFile: a[2], encoding: .utf8)
        let user = try! String(contentsOfFile: a[3], encoding: .utf8)
        let source = norm(user)
        let opts = GenerationOptions(temperature: temp)
        for i in 1...n {
            let t0 = Date()
            var rec: [String: Any] = ["variant": variant, "case": label, "i": i]
            do {
                let session = LanguageModelSession(instructions: system)
                switch variant {
                case "free":
                    let r = try await session.respond(to: user, options: opts)
                    rec["text"] = r.content
                case "v1":
                    let r = try await session.respond(to: user, generating: DailyV1.self, options: opts).content
                    var t = "You wrote, \"\(r.quote)\" \(r.insight)"
                    if !r.suggestion.isEmpty { t += " \(r.suggestion)" }
                    rec["text"] = t
                    rec["quoteVerbatim"] = source.contains(norm(r.quote))
                    rec["fields"] = ["quote": r.quote, "insight": r.insight, "suggestion": r.suggestion]
                case "v2":
                    let r = try await session.respond(to: user, generating: DailyV2.self, options: opts).content
                    var t = "You wrote, \"\(r.quote)\" \(r.insight)"
                    if !r.earlierQuote.isEmpty { t += " Earlier you wrote, \"\(r.earlierQuote)\" \(r.connection)" }
                    if !r.suggestion.isEmpty { t += " \(r.suggestion)" }
                    rec["text"] = t
                    rec["quoteVerbatim"] = source.contains(norm(r.quote))
                    rec["earlierVerbatim"] = r.earlierQuote.isEmpty ? true : source.contains(norm(r.earlierQuote))
                    rec["fields"] = ["quote": r.quote, "insight": r.insight, "earlierQuote": r.earlierQuote, "connection": r.connection, "suggestion": r.suggestion]
                case "v1b_hard":
                    let r = try await session.respond(to: user, generating: DailyV1bHard.self, options: opts).content
                    rec["text"] = "You wrote, \"\(r.quote)\" \(tidy(r.insight)) \(tidy(r.suggestion))"
                    rec["quoteVerbatim"] = source.contains(norm(r.quote))
                    rec["fields"] = ["quote": r.quote, "insight": r.insight, "suggestion": r.suggestion]
                case "v1b_easy":
                    let r = try await session.respond(to: user, generating: DailyV1bEasy.self, options: opts).content
                    rec["text"] = "You wrote, \"\(r.quote)\" \(tidy(r.insight))"
                    rec["quoteVerbatim"] = source.contains(norm(r.quote))
                    rec["fields"] = ["quote": r.quote, "insight": r.insight]
                default:
                    rec["error"] = "unknown variant"
                }
            } catch {
                rec["error"] = String(describing: error)
            }
            rec["seconds"] = (Date().timeIntervalSince(t0) * 10).rounded() / 10
            emit(rec)
        }
    }
}
