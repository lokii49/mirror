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

// Round 10 (RUBRIC_FM.md): the shipped guide asking for two or three sentences. If it passes, this exact text
// replaces FoundationModelEngine.DailyReflectionDraft's.
@Generable struct DailyV1f {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
    var quote: String
    @Guide(description: "Two or three sentences speaking to the person as 'you': what this seems to mean for them, using only feelings they wrote or plainly showed. Each sentence says something new. If the day was ordinary, say so. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
}

@Generable struct DailyV1bEasy {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
    var quote: String
    @Guide(description: "One or two sentences speaking to the person as 'you': what this seems to mean for them, using only feelings they wrote or plainly showed. If the day was ordinary, say so. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
}

@Generable struct DailyV1c {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words, one sentence only")
    var quote: String
    @Guide(description: "Exactly two sentences speaking to the person as 'you'. First: what this seems to mean for them, using only feelings they wrote or plainly showed. Second: the need, the tension between two things they wrote, or what they seem to hope or worry about, as their own words show it. Plain everyday words. No advice. Nothing they did not write")
    var insight: String
}

/// Capitalises every sentence and makes sure the text ends with punctuation (what the app does).
func tidyAll(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    var out = "", capNext = true
    for ch in t {
        if capNext, ch.isLetter { out += ch.uppercased(); capNext = false } else { out.append(ch) }
        if ".!?…".contains(ch) { capNext = true }
    }
    if let last = out.last, !".!?…".contains(last) { out += "." }
    return out
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


/// Today's entries (the first entry's date) from a dumped "Daily reflection context" prompt, the
/// same set the app's `groundedNudgeSourceEntries` gives the guard.
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
                case "v1c":
                    let r = try await session.respond(to: user, generating: DailyV1c.self, options: opts).content
                    rec["text"] = "You wrote, \"\(r.quote)\" \(tidyAll(r.insight))"
                    rec["quoteVerbatim"] = source.contains(norm(r.quote))
                    rec["fields"] = ["quote": r.quote, "insight": r.insight]
                case "v1d":
                    // V1b's short prompt for every mood, no model-written suggestion, app-side tidy.
                    let r = try await session.respond(to: user, generating: DailyV1bEasy.self, options: opts).content
                    rec["text"] = "You wrote, \"\(r.quote)\" \(tidyAll(r.insight))"
                    rec["quoteVerbatim"] = source.contains(norm(r.quote))
                    rec["fields"] = ["quote": r.quote, "insight": r.insight]
                case "v1e":
                    // V1d plus the app's guards and retry loop (up to 3 attempts). Shown text = first
                    // attempt that survives; none -> fallback (the app would use Gemma / the honest card).
                    let sources = todaySources(user)
                    var raws: [[String: String]] = []
                    var shown: FMDailyGuard.Verified?
                    var attempts = 0
                    for _ in 1...3 {
                        attempts += 1
                        let r = try await session.respond(to: user, generating: DailyV1bEasy.self, options: opts).content
                        raws.append(["quote": r.quote, "insight": r.insight])
                        if let v = FMDailyGuard.verify(quote: r.quote, insight: r.insight, sources: sources) { shown = v; break }
                    }
                    rec["attempts"] = attempts
                    rec["raws"] = raws
                    if let v = shown {
                        rec["text"] = "You wrote, \"\(v.quote)\" \(v.insight)"
                        rec["quoteVerbatim"] = source.contains(norm(v.quote))
                        rec["fields"] = ["quote": v.quote, "insight": v.insight]
                        rec["dropped"] = v.droppedSentences
                    } else {
                        rec["fallback"] = true
                    }
                case "prod", "v1f":
                    // Round 10. prod = the shipped reflection (V1e: guide, guard at 2 sentences, 3 attempts);
                    // v1f = two-or-three-sentence guide, guard keeps up to 3. The system prompt comes from argv.
                    let sources = todaySources(user)
                    let cap = variant == "v1f" ? 3 : FMDailyGuard.maxInsightSentences
                    var raws: [[String: String]] = []
                    var shown: FMDailyGuard.Verified?
                    var attempts = 0
                    for _ in 1...3 {
                        attempts += 1
                        let (quote, insight): (String, String)
                        if variant == "v1f" {
                            let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: DailyV1f.self, options: opts).content
                            (quote, insight) = (r.quote, r.insight)
                        } else {
                            let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: DailyV1bEasy.self, options: opts).content
                            (quote, insight) = (r.quote, r.insight)
                        }
                        raws.append(["quote": quote, "insight": insight])
                        if let v = FMDailyGuard.verify(quote: quote, insight: insight, sources: sources, maxSentences: cap) { shown = v; break }
                    }
                    rec["attempts"] = attempts
                    rec["raws"] = raws
                    if let v = shown {
                        rec["text"] = "You wrote, \"\(v.quote)\" \(v.insight)"
                        rec["quoteVerbatim"] = source.contains(norm(v.quote))
                        rec["fields"] = ["quote": v.quote, "insight": v.insight]
                        rec["dropped"] = v.droppedSentences
                    } else {
                        rec["fallback"] = true
                    }
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
