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

// Round 12 (RUBRIC_FM.md, reflection styles Tier 2): only the insight guide differs from the shipped one.
@Generable struct DailyS1Plain {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
    var quote: String
    @Guide(description: "One short sentence, at most 15 words, speaking to the person as 'you': plainly what happened or how they felt, using only feelings they wrote or plainly showed. Do not explain what it means. If the day was ordinary, say so. Plain everyday words. Say nothing about anything they did not write")
    var insight: String
}

@Generable struct DailyS2Question {
    @Guide(description: "The single most important sentence from TODAY's entry, copied word for word with the same punctuation, at most 25 words")
    var quote: String
    @Guide(description: "One open question to the person as 'you' about something they wrote today, in their own words: what it means to them or how it sits with them. No suggested answer, feeling or action. Plain everyday words. Ask about nothing they did not write")
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


// Round 15 (RUBRIC_FM.md): the weekly digest in the Gemma digest's shape. If it passes, this exact text
// becomes FoundationModelEngine.WeeklyDigestDraft's.
@Generable struct WeeklyDigestD1 {
    @Guide(description: "What this week was mostly about, in 3 to 10 plain words that finish 'A week of'. Name real things they wrote about")
    var theme: String
    @Guide(description: "One sentence copied word for word, with the same punctuation, from this week's entries: the one that best shows when they had the most or the least energy")
    var energyQuote: String
    @Guide(description: "One sentence to the person as 'you': what that moment shows about their week, or how it connects to another day they wrote about. Only feelings they wrote or plainly showed")
    var energyRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something good that is growing or changing for them")
    var buildingQuote: String
    @Guide(description: "One sentence to the person as 'you': what that might mean for them. Say nothing about anything they did not write")
    var buildingRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something that may be quietly costing them")
    var watchQuote: String
    @Guide(description: "One gentle sentence to the person as 'you' on what to keep an eye on. Say nothing about anything they did not write")
    var watchRead: String
    @Guide(description: "One small thing they could do in the next few days, using a person, task or thing they named this week")
    var boost: String
    @Guide(description: "One kind, practical sentence for next week about something they wrote is coming up or still unfinished")
    var nextWeek: String
}

// Round 15 W2: only the watch guide differs from W1 ("quietly" removed).
@Generable struct WeeklyDigestD2 {
    @Guide(description: "What this week was mostly about, in 3 to 10 plain words that finish 'A week of'. Name real things they wrote about")
    var theme: String
    @Guide(description: "One sentence copied word for word, with the same punctuation, from this week's entries: the one that best shows when they had the most or the least energy")
    var energyQuote: String
    @Guide(description: "One sentence to the person as 'you': what that moment shows about their week, or how it connects to another day they wrote about. Only feelings they wrote or plainly showed")
    var energyRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something good that is growing or changing for them")
    var buildingQuote: String
    @Guide(description: "One sentence to the person as 'you': what that might mean for them. Say nothing about anything they did not write")
    var buildingRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something that may be costing them or wearing on them")
    var watchQuote: String
    @Guide(description: "One gentle sentence to the person as 'you' on what to keep an eye on. Say nothing about anything they did not write")
    var watchRead: String
    @Guide(description: "One small thing they could do in the next few days, using a person, task or thing they named this week")
    var boost: String
    @Guide(description: "One kind, practical sentence for next week about something they wrote is coming up or still unfinished")
    var nextWeek: String
}

// Round 16 W3: theme and read guides changed, no link between days.
@Generable struct WeeklyDigestD3 {
    @Guide(description: "One short phrase, 3 to 8 words, that finishes 'A week of' and says what the week was about for them. Not a list of names")
    var theme: String
    @Guide(description: "One sentence copied word for word, with the same punctuation, from this week's entries: the one that best shows when they had the most or the least energy")
    var energyQuote: String
    @Guide(description: "One sentence to the person as 'you': what that moment seems to show they need, hope for or worry about. Do not retell it. Only feelings they wrote or plainly showed")
    var energyRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something good that is growing or changing for them")
    var buildingQuote: String
    @Guide(description: "One sentence to the person as 'you': what that might mean for them from here on. Do not retell it. Say nothing about anything they did not write")
    var buildingRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something that may be costing them or wearing on them")
    var watchQuote: String
    @Guide(description: "One gentle sentence to the person as 'you' on what to keep an eye on and why it matters to them. Say nothing about anything they did not write")
    var watchRead: String
    @Guide(description: "One small thing they could do in the next few days, using a person, task or thing they named this week")
    var boost: String
    @Guide(description: "One kind, practical sentence for next week about something they wrote is coming up or still unfinished")
    var nextWeek: String
}

// Round 17 W4: next week and boost guides changed.
@Generable struct WeeklyDigestD4 {
    @Guide(description: "One short phrase, 3 to 8 words, that finishes 'A week of' and says what the week was about for them. Not a list of names")
    var theme: String
    @Guide(description: "One sentence copied word for word, with the same punctuation, from this week's entries: the one that best shows when they had the most or the least energy")
    var energyQuote: String
    @Guide(description: "One sentence to the person as 'you': what that moment seems to show they need, hope for or worry about. Do not retell it. Only feelings they wrote or plainly showed")
    var energyRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something good that is growing or changing for them")
    var buildingQuote: String
    @Guide(description: "One sentence to the person as 'you': what that might mean for them from here on. Do not retell it. Say nothing about anything they did not write")
    var buildingRead: String
    @Guide(description: "A different sentence copied word for word from this week's entries, about something that may be costing them or wearing on them")
    var watchQuote: String
    @Guide(description: "One gentle sentence to the person as 'you' on what to keep an eye on and why it matters to them. Say nothing about anything they did not write")
    var watchRead: String
    @Guide(description: "One small thing they could do, using a person and a task from the same entry, or a task or thing they named")
    var boost: String
    @Guide(description: "One kind, practical sentence about something they wrote is still unfinished or undecided. Do not say when anything will happen")
    var nextWeek: String
}

/// Every entry of a dumped "Weekly digest context" prompt's Recent entries, with its mood.
func weekSources(_ user: String) -> [FMDailyGuard.Source] {
    let head = user.components(separatedBy: "Long-term context:")[0]
    guard let r = head.range(of: "Recent entries:\n") else { return [] }
    var out: [FMDailyGuard.Source] = []
    for b in String(head[r.upperBound...]).components(separatedBy: "\n---\n") {
        var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { continue }
        let mood = lines[1].replacingOccurrences(of: "Mood: ", with: "").components(separatedBy: ".")[0]
        lines.removeFirst(2)
        out.append(FMDailyGuard.Source(text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), mood: mood))
    }
    return out
}

let digestLabels = ["THIS WEEK'S THEME", "YOUR ENERGY", "WHAT'S BUILDING", "WATCH OUT FOR", "MOOD BOOST", "NEXT WEEK"]


// Round 19 (RUBRIC_FM.md): the monthly report in the Gemma report's shape. If it ships, this exact text becomes
// FoundationModelEngine.MonthlyReportDraft's.
@Generable struct MonthlyM1 {
    @Guide(description: "A short image, 3 to 10 words, for how the month felt. A picture, not a fact about their life")
    var image: String
    @Guide(description: "One thing from their entries that asked for their time or heart this month, a few plain words")
    var tensionA: String
    @Guide(description: "A second, different thing from their entries that also asked for their time or heart, a few plain words")
    var tensionB: String
    @Guide(description: "One sentence copied word for word, with the same punctuation, from this month's entries: one that seems to have changed something for them")
    var momentQuote: String
    @Guide(description: "One sentence to the person as 'you': what that moment might have changed. Do not retell it. Say nothing about anything they did not write")
    var momentRead: String
    @Guide(description: "A different sentence copied word for word from a day that was not hard, that shows who they are growing into")
    var becomingQuote: String
    @Guide(description: "The end of the sentence 'You seem to be becoming someone who ...', a few plain words, using only what they wrote")
    var becomingRest: String
    @Guide(description: "A different sentence copied word for word from a hard day, about something that weighed on them")
    var releaseQuote: String
    @Guide(description: "The end of the sentence 'Maybe it's time to let go of ...', a few plain words about that weight")
    var releaseRest: String
    @Guide(description: "One honest, open question for next month about something they wrote, ending with a question mark")
    var question: String
}

/// Every entry of a dumped "Monthly deep report context" prompt, with its mood and "d MMM" day.
func monthSources(_ user: String) -> [FMMonthlyGuard.Source] {
    guard let r = user.range(of: "This month's entries (newest first):\n") else { return [] }
    var out: [FMMonthlyGuard.Source] = []
    for b in String(user[r.upperBound...]).components(separatedBy: "\n---\n") {
        var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { continue }
        let date = lines[0].components(separatedBy: " - ").dropFirst().joined(separator: " - ")
        let day = date.split(separator: " ").prefix(2).joined(separator: " ")
        let mood = lines[1].replacingOccurrences(of: "Mood: ", with: "").components(separatedBy: ".")[0]
        lines.removeFirst(2)
        out.append(FMMonthlyGuard.Source(text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), mood: mood, day: day))
    }
    return out
}

let monthlyLabels = ["YOUR MONTH IN ONE IMAGE", "THE TENSION AT THE CENTER", "A MOMENT THAT SHIFTED SOMETHING", "WHAT YOU'RE BECOMING", "WHAT WANTS TO BE RELEASED", "YOUR QUESTION FOR NEXT MONTH"]


// Round 20 (RUBRIC_FM.md): Ask with a checked answer plus the person's dated sentences.
@Generable struct AskA1 {
    @Guide(description: "True if the entries say anything about the question, otherwise false")
    var found: Bool
    @Guide(description: "If found: one or two sentences to the person as 'you' answering the question from what they wrote, in your own words, never 'I', 'me' or 'my'. Otherwise empty")
    var answer: String
    @Guide(description: "The one sentence from the entries that best answers the question, copied word for word with the same punctuation")
    var quote1: String
    @Guide(description: "A different sentence copied word for word that also answers the question, or empty")
    var quote2: String
}

/// The "Most relevant entries" of a dumped Ask prompt, with "d MMM" days.
func askSources(_ user: String) -> [(text: String, mood: String, day: String)] {
    guard let r = user.range(of: "Most relevant entries:\n") else { return [] }
    let block = String(user[r.upperBound...]).components(separatedBy: "\n\nQuestion:")[0]
    var out: [(String, String, String)] = []
    for b in block.components(separatedBy: "\n---\n") {
        var lines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, lines[0].hasPrefix("Entry ") else { continue }
        let date = lines[0].components(separatedBy: " - ").dropFirst().joined(separator: " - ")
        let mood = lines[1].replacingOccurrences(of: "Mood: ", with: "").components(separatedBy: ".")[0]
        lines.removeFirst(2)
        out.append((lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), mood, date.split(separator: " ").prefix(2).joined(separator: " ")))
    }
    return out
}

let askNoAnswer = "You haven't written about this yet."


// Round 21 (RUBRIC_FM.md): the sentences under today's Ask answer.
@Generable struct AskQuotes {
    @Guide(description: "The sentence from the entries that best backs up the answer, copied word for word with the same punctuation, or empty")
    var quote1: String
    @Guide(description: "A different sentence from the entries that also backs up the answer, copied word for word, or empty")
    var quote2: String
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
                case "prod", "v1f", "s1", "s2":
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
                        } else if variant == "s1" {
                            let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: DailyS1Plain.self, options: opts).content
                            (quote, insight) = (r.quote, r.insight)
                        } else if variant == "s2" {
                            let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: DailyS2Question.self, options: opts).content
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
                case "digest_d1", "digest_d2", "digest_d3", "digest_d4":
                    // Round 15. W1: an attempt shows only when all six sections pass in it. W2: each section
                    // comes from the first attempt where it passes (FMDigestGuard.merge). At most 3 attempts.
                    let sources = weekSources(user)
                    var raws: [[String: String]] = []
                    var drafts: [FMDigestGuard.Draft] = []
                    var missing: [[String]] = []
                    var shown: FMDigestGuard.Verified?
                    for _ in 1...3 {
                        let session = LanguageModelSession(instructions: system)
                        let d: FMDigestGuard.Draft
                        if variant == "digest_d1" {
                            let r = try await session.respond(to: user, generating: WeeklyDigestD1.self, options: opts).content
                            d = FMDigestGuard.Draft(theme: r.theme, energyQuote: r.energyQuote, energyRead: r.energyRead,
                                                    buildingQuote: r.buildingQuote, buildingRead: r.buildingRead,
                                                    watchQuote: r.watchQuote, watchRead: r.watchRead, boost: r.boost, nextWeek: r.nextWeek)
                        } else if variant == "digest_d4" {
                            let r = try await session.respond(to: user, generating: WeeklyDigestD4.self, options: opts).content
                            d = FMDigestGuard.Draft(theme: r.theme, energyQuote: r.energyQuote, energyRead: r.energyRead,
                                                    buildingQuote: r.buildingQuote, buildingRead: r.buildingRead,
                                                    watchQuote: r.watchQuote, watchRead: r.watchRead, boost: r.boost, nextWeek: r.nextWeek)
                        } else if variant == "digest_d3" {
                            let r = try await session.respond(to: user, generating: WeeklyDigestD3.self, options: opts).content
                            d = FMDigestGuard.Draft(theme: r.theme, energyQuote: r.energyQuote, energyRead: r.energyRead,
                                                    buildingQuote: r.buildingQuote, buildingRead: r.buildingRead,
                                                    watchQuote: r.watchQuote, watchRead: r.watchRead, boost: r.boost, nextWeek: r.nextWeek)
                        } else {
                            let r = try await session.respond(to: user, generating: WeeklyDigestD2.self, options: opts).content
                            d = FMDigestGuard.Draft(theme: r.theme, energyQuote: r.energyQuote, energyRead: r.energyRead,
                                                    buildingQuote: r.buildingQuote, buildingRead: r.buildingRead,
                                                    watchQuote: r.watchQuote, watchRead: r.watchRead, boost: r.boost, nextWeek: r.nextWeek)
                        }
                        raws.append(["theme": d.theme, "energyQuote": d.energyQuote, "energyRead": d.energyRead,
                                     "buildingQuote": d.buildingQuote, "buildingRead": d.buildingRead,
                                     "watchQuote": d.watchQuote, "watchRead": d.watchRead, "boost": d.boost, "nextWeek": d.nextWeek])
                        drafts = variant == "digest_d1" ? [d] : drafts + [d]
                        let filled = FMDigestGuard.sections(from: drafts, sources: sources)
                        missing.append(FMDigestGuard.Section.allCases.filter { filled[$0] == nil }.map(\.rawValue))
                        shown = FMDigestGuard.merge(drafts, sources: sources)
                        if shown != nil { break }
                    }
                    if shown == nil, variant == "digest_d3" || variant == "digest_d4", let a = FMDigestGuard.assemble(drafts, sources: sources) {
                        shown = a.verified
                        rec["fixed"] = a.fixed.map(\.rawValue)
                    }
                    rec["attempts"] = raws.count
                    rec["raws"] = raws
                    rec["missing"] = missing
                    if let v = shown {
                        rec["text"] = zip(digestLabels, v.sections).map { "\($0): \($1)" }.joined(separator: "\n")
                    } else {
                        rec["fallback"] = true
                    }
                case "monthly_m1":
                    // Round 19. Each section from the first of up to 3 attempts where it passes; the rest app-filled.
                    let sources = monthSources(user)
                    var raws: [[String: String]] = []
                    var drafts: [FMMonthlyGuard.Draft] = []
                    var shown: [String]?
                    var refusals = 0
                    for _ in 1...3 {
                        do {
                            let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: MonthlyM1.self, options: opts).content
                            let d = FMMonthlyGuard.Draft(image: r.image, tensionA: r.tensionA, tensionB: r.tensionB,
                                                         momentQuote: r.momentQuote, momentRead: r.momentRead,
                                                         becomingQuote: r.becomingQuote, becomingRest: r.becomingRest,
                                                         releaseQuote: r.releaseQuote, releaseRest: r.releaseRest, question: r.question)
                            raws.append(["image": d.image, "tensionA": d.tensionA, "tensionB": d.tensionB, "momentQuote": d.momentQuote,
                                         "momentRead": d.momentRead, "becomingQuote": d.becomingQuote, "becomingRest": d.becomingRest,
                                         "releaseQuote": d.releaseQuote, "releaseRest": d.releaseRest, "question": d.question])
                            drafts.append(d)
                            shown = FMMonthlyGuard.merge(drafts, sources: sources)
                            if shown != nil { break }
                        } catch {
                            refusals += 1
                            rec["lastError"] = String(describing: error)
                        }
                    }
                    if shown == nil, let a = FMMonthlyGuard.assemble(drafts, sources: sources) {
                        shown = a.sections
                        rec["fixed"] = a.fixed.map(\.rawValue)
                    }
                    rec["attempts"] = raws.count + refusals
                    rec["refusals"] = refusals
                    rec["raws"] = raws
                    if let v = shown {
                        rec["text"] = zip(monthlyLabels, v).map { "\($0): \($1)" }.joined(separator: "\n")
                    } else {
                        rec["fallback"] = true
                    }
                case "ask_a1":
                    // Round 20. Answer checked against the retrieved entries; quotes located in them; up to 3 attempts.
                    let src = askSources(user)
                    let guardSources = src.map { FMDailyGuard.Source(text: $0.text, mood: $0.mood) }
                    let texts = src.map(\.text)
                    var raws: [[String: String]] = []
                    var answer: String?
                    var quotes: [String] = []
                    var noAnswer = false
                    for _ in 1...3 {
                        let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: AskA1.self, options: opts).content
                        raws.append(["found": r.found ? "true" : "false", "answer": r.answer, "quote1": r.quote1, "quote2": r.quote2])
                        if quotes.isEmpty {
                            for q in [r.quote1, r.quote2] {
                                guard let found = FMDailyGuard.locate(quote: q, in: texts) else { continue }
                                let dated = "On \(src[found.index].day), you wrote, \"\(found.quote)\""
                                if !quotes.contains(where: { $0.contains(found.quote) || found.quote.contains($0) }) { quotes.append(dated) }
                            }
                        }
                        if answer == nil, r.found { answer = FMDailyGuard.cleanSentences(of: r.answer, sources: guardSources, maxSentences: 2)?.text }
                        if !r.found, !quotes.isEmpty { break }
                        if answer != nil, !quotes.isEmpty { break }
                    }
                    rec["raws"] = raws
                    if noAnswer {
                        rec["text"] = askNoAnswer
                        rec["noAnswer"] = true
                    } else {
                        if quotes.isEmpty, let first = src.first, let sentence = FMDigestGuard.quotableSentences(of: first.text).first {
                            quotes = ["On \(first.day), you wrote, \"\(sentence)\""]
                            rec["appQuote"] = true
                        }
                        rec["answerShown"] = answer != nil
                        rec["text"] = ((answer.map { $0 + " " } ?? "") + "The closest things you've written: " + quotes.joined(separator: " "))
                    }
                case "ask_quotes":
                    // Round 21. user = the Ask prompt + "\n\nAnswer given: <answer>"; quotes located in its entries.
                    let src = askSources(user)
                    let texts = src.map(\.text)
                    let r = try await LanguageModelSession(instructions: system).respond(to: user, generating: AskQuotes.self, options: opts).content
                    var shownQuotes: [String] = []
                    for q in [r.quote1, r.quote2] {
                        guard let found = FMDailyGuard.locate(quote: q, in: texts),
                              !shownQuotes.contains(where: { $0.contains(found.quote) }) else { continue }
                        shownQuotes.append("On \(src[found.index].day), you wrote, \"\(found.quote)\"")
                    }
                    rec["raws"] = [["quote1": r.quote1, "quote2": r.quote2]]
                    rec["quotes"] = shownQuotes
                    rec["text"] = shownQuotes.isEmpty ? "" : "The closest things you've written: " + shownQuotes.joined(separator: " ")
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
