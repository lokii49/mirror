import Foundation
import NaturalLanguage

/// Checks on the daily reflection that Foundation Models writes as a structured `quote` plus
/// `insight` (see `FoundationModelEngine.generateDailyReflection`). Pure text logic, no app
/// types, so tools/llmrig/fm/fmrig.swift compiles this same file and measures exactly what ships.
///
/// The quote is verified against today's entries and shown with the entry's own wording. The
/// insight is checked sentence by sentence; a sentence that fails is dropped, and the whole
/// attempt is rejected when none survives. Measured in tools/llmrig/fm/RUBRIC_FM.md (round 5).
nonisolated enum FMDailyGuard {

    struct Source {
        let text: String
        let mood: String?

        init(text: String, mood: String?) {
            self.text = text
            self.mood = mood
        }
    }

    struct Verified: Equatable {
        /// The entry's own words, cut to `maxQuoteWords` / `maxQuoteChars`.
        let quote: String
        /// One or two clean sentences, capitalised and ending in punctuation.
        let insight: String
        /// Index into the sources the quote was found in.
        let sourceIndex: Int
        /// How many insight sentences the checks removed.
        let droppedSentences: Int
    }

    static let maxQuoteWords = 25
    static let maxQuoteChars = 200
    static let minQuoteWords = 4
    static let maxInsightSentences = 2

    static func verify(quote: String, insight: String, sources: [Source]) -> Verified? {
        guard let (shownQuote, index) = locate(quote: quote, in: sources.map(\.text)) else { return nil }
        let allowed = allowedWords(sources)
        let sourceWords = Set(sources.flatMap { words($0.text) })
        let sourceText = sources.map(\.text).joined(separator: " ")
        let names = personNames(in: sourceText)
        var kept: [String] = []
        var dropped = 0
        for sentence in sentences(of: insight) {
            let restored = restoreNames(sentence, names: names)
            let duplicate = kept.contains { $0.lowercased() == tidy(restored).lowercased() }
            if !duplicate, sentenceIsClean(restored, allowed: allowed, sourceWords: sourceWords, sourceText: sourceText) {
                if kept.count < maxInsightSentences { kept.append(tidy(restored)) }
            } else {
                dropped += 1
            }
        }
        guard !kept.isEmpty else { return nil }
        return Verified(quote: shownQuote, insight: kept.joined(separator: " "), sourceIndex: index, droppedSentences: dropped)
    }

    // MARK: - Quote

    /// The model's quote as it is written in one of `texts`: matched ignoring case, runs of
    /// whitespace and curly quotes, returned with the entry's own casing and marks, cut at a word
    /// boundary to the display limits. nil when it is in none of them or too short to be a quote.
    static func locate(quote: String, in texts: [String]) -> (quote: String, index: Int)? {
        let needle = straighten(collapse(quote)).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard !needle.isEmpty else { return nil }
        for (index, text) in texts.enumerated() {
            let collapsed = collapse(text)
            let haystack = straighten(collapsed)
            guard let range = haystack.range(of: needle, options: .caseInsensitive) else { continue }
            // Curly -> straight is one character for one, so offsets carry over to the original.
            let start = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let length = haystack.distance(from: range.lowerBound, to: range.upperBound)
            let from = collapsed.index(collapsed.startIndex, offsetBy: start)
            let to = collapsed.index(from, offsetBy: length)
            let shown = cut(String(collapsed[from..<to]))
            guard shown.split(separator: " ").count >= minQuoteWords else { return nil }
            return (shown, index)
        }
        return nil
    }

    /// Keeps the longest start of `quote` that fits the limits and ends a sentence; failing that, one
    /// that ends a clause (at least 8 words in); failing that, a plain word cut. Always a verbatim start.
    private static func cut(_ quote: String) -> String {
        var fit: [Substring] = []
        var chars = 0
        for word in quote.split(separator: " ") {
            let next = chars + word.count + (fit.isEmpty ? 0 : 1)
            if fit.count >= maxQuoteWords || next > maxQuoteChars { break }
            fit.append(word)
            chars = next
        }
        let total = quote.split(separator: " ").count
        if fit.count == total { return fit.joined(separator: " ") }
        func ends(_ word: Substring, _ marks: String) -> Bool {
            guard let last = word.last(where: { !"\"')”’".contains($0) }) else { return false }
            return marks.contains(last)
        }
        if let k = fit.lastIndex(where: { ends($0, ".!?…") }), k + 1 >= minQuoteWords {
            return fit[...k].joined(separator: " ")
        }
        if let k = fit.lastIndex(where: { ends($0, ",;:—–") }), k + 1 >= 8 {
            return fit[...k].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:—– "))
        }
        return fit.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:—– "))
    }

    // MARK: - Insight

    private static func sentences(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for (i, ch) in characters.enumerated() {
            current.append(ch)
            let endsSentence = ".!?…".contains(ch) && (i + 1 == characters.count || characters[i + 1].isWhitespace)
            if endsSentence {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    /// Names the entries write (people and places), lowercased -> as written. The model sometimes
    /// writes a name in lowercase ("worried about maya").
    private static func personNames(in text: String) -> [String: String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String: String] = [:]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if let tag, tag == .personalName || tag == .placeName {
                let name = String(text[range])
                if name.first?.isUppercase == true { names[name.lowercased()] = name }
            }
            return true
        }
        return names
    }

    private static func restoreNames(_ sentence: String, names: [String: String]) -> String {
        guard !names.isEmpty else { return sentence }
        var out = ""
        var word = ""
        func flush() {
            if let name = names[word.lowercased()] { out += name } else { out += word }
            word = ""
        }
        for ch in sentence {
            if ch.isLetter || ch == "'" { word.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    private static func tidy(_ sentence: String) -> String {
        var out = ""
        var capitalised = false
        for ch in sentence.trimmingCharacters(in: .whitespaces) {
            if !capitalised, ch.isLetter { out += ch.uppercased(); capitalised = true } else { out.append(ch) }
        }
        if let last = out.last, !".!?…".contains(last) { out += "." }
        return out
    }

    private static func sentenceIsClean(_ sentence: String, allowed: [String], sourceWords: Set<String>, sourceText: String) -> Bool {
        if sentence.contains(where: { "\"“”„«»".contains($0) }) { return false }
        let tokens = words(sentence)
        guard tokens.count >= 2 else { return false }
        if tokens.contains(where: firstPerson.contains) { return false }
        if tokens.contains(where: { scenery.contains($0) && !sourceWords.contains($0) }) { return false }
        let padded = " " + tokens.joined(separator: " ") + " "
        let sourcePadded = " " + words(sourceText).joined(separator: " ") + " "
        for phrase in unsupportedClaims where padded.contains(" \(phrase) ") && !sourcePadded.contains(" \(phrase) ") { return false }
        for token in tokens where feelings.contains(where: { matches(token, $0) }) {
            if !allowed.contains(where: { matches(token, $0) }) { return false }
        }
        if hasFeelParticiple(tokens) { return false }
        if introducesName(sentence, sourceWords: sourceWords) { return false }
        return true
    }

    /// A capitalised word inside the sentence (not its first word) that the entries do not contain.
    private static func introducesName(_ sentence: String, sourceWords: Set<String>) -> Bool {
        let parts = sentence.split(separator: " ").dropFirst()
        for part in parts {
            let word = part.trimmingCharacters(in: .punctuationCharacters)
            guard let first = word.first, first.isUppercase, word.count > 1 else { continue }
            let key = straighten(word).lowercased()
            if key == "i" || sourceWords.contains(key) || sourceWords.contains(key.replacingOccurrences(of: "'s", with: "")) { continue }
            return true
        }
        return false
    }

    /// "feel missing him", "feel sad and missing him": a feeling word followed by a verb form.
    private static func hasFeelParticiple(_ tokens: [String]) -> Bool {
        for (i, token) in tokens.enumerated() where token == "feel" || token == "feels" || token == "felt" {
            var j = i + 1
            if j + 1 < tokens.count, ["and", "or"].contains(tokens[j + 1]) { j += 2 }
            guard j < tokens.count else { continue }
            let word = tokens[j]
            if word.hasSuffix("ing"), word.count > 4, !participleSafe.contains(word) { return true }
        }
        return false
    }

    // MARK: - Word lists

    private static func allowedWords(_ sources: [Source]) -> [String] {
        var allowed = Set(sources.flatMap { words($0.text) })
        for mood in sources.compactMap(\.mood) {
            let key = mood.lowercased()
            allowed.insert(key)
            allowed.formUnion(moodSynonyms[key] ?? [])
        }
        return allowed.filter { $0.count >= 3 }
    }

    /// Same word, ignoring endings: compares up to the first five letters of the shorter word.
    private static func matches(_ a: String, _ b: String) -> Bool {
        let n = min(a.count, b.count, 5)
        guard n >= 3 else { return a == b }
        return a.prefix(n) == b.prefix(n)
    }

    static func words(_ text: String) -> [String] {
        straighten(text).lowercased()
            .split(whereSeparator: { !($0.isLetter || $0 == "'") })
            .map(String.init)
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func straighten(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    private static let firstPerson: Set<String> = ["i", "i'm", "i've", "i'd", "i'll", "my", "me", "myself", "mine", "we", "our", "us"]

    private static let scenery: Set<String> = [
        "rain", "sky", "sunlight", "sunset", "sunrise", "breeze", "wind", "scent", "smell", "steam", "mug",
        "melody", "silence", "birds", "candle", "blanket", "clouds", "cloud", "moon", "stars", "snow", "fog",
        "glow", "whisper", "whispers", "laughter", "aroma", "warmth", "chill", "window"
    ]

    /// Claims that go past what the entries say unless the entries use the same word.
    private static let unsupportedClaims = [
        "before", "ever", "never", "always", "anymore", "again", "finally", "usually", "all day", "all night",
        "first time", "at last", "so much", "every"
    ]

    private static let participleSafe: Set<String> = [
        "overwhelming", "exciting", "draining", "calming", "frustrating", "disappointing", "confusing",
        "something", "nothing", "anything", "everything", "morning", "evening", "feeling", "thing"
    ]

    private static let feelings: [String] = [
        "relief", "relieved", "calm", "anxious", "anxiety", "uneasy", "unease", "hopeful", "hope", "nervous",
        "worried", "worry", "sad", "sadness", "happy", "happiness", "joy", "joyful", "proud", "pride", "lonely",
        "loneliness", "guilty", "guilt", "angry", "anger", "annoyed", "frustrated", "frustration", "stressed",
        "stress", "overwhelmed", "drained", "tired", "exhausted", "content", "peaceful", "peace", "excited",
        "excitement", "grateful", "thankful", "numb", "empty", "afraid", "scared", "fear", "disappointed",
        "upset", "hurt", "irritated", "restless", "tense", "weary", "heavy", "heaviness", "comfort", "anticipation",
        "dread", "jealous", "ashamed", "embarrassed", "confident", "motivated", "eager", "curious", "bored",
        "sorrow", "grief", "longing", "homesick", "lonesome", "delighted", "thrilled", "optimistic", "energized",
        "resentful", "regret", "regretful", "hopeless", "panicked", "burned", "burnt", "lighthearted",
        // States the model likes to add to a day: allowed only when the entry or its mood says so.
        "quiet", "focused", "productive", "active", "busy", "relaxed", "wired", "alert", "determined"
    ]

    /// Words that count as the same feeling as a mood label the person chose.
    private static let moodSynonyms: [String: [String]] = [
        "joyful": ["happy", "joy", "delighted", "glad", "thrilled", "excited", "proud", "happiness"],
        "grateful": ["thankful", "appreciate", "appreciated", "appreciative", "gratitude"],
        "peaceful": ["calm", "calmer", "relaxed", "ease", "serene", "settled", "peace", "quiet"],
        "content": ["satisfied", "steady", "calm", "settled", "okay", "fine", "ordinary", "comfortable", "peaceful"],
        "energized": ["energetic", "lively", "motivated", "alive", "eager", "energy"],
        "hopeful": ["optimistic", "hope", "encouraged", "hoping", "looking"],
        "anxious": ["nervous", "worried", "worry", "uneasy", "tense", "restless", "anxiety", "stressed"],
        "overwhelmed": ["stressed", "swamped", "pressure", "stress", "behind", "stretched"],
        "frustrated": ["annoyed", "irritated", "angry", "upset", "frustration", "annoying"],
        "drained": ["tired", "exhausted", "worn", "spent", "weary", "low", "depleted"],
        "sad": ["down", "low", "unhappy", "sorrow", "hurt", "sadness", "heavy", "grief"],
        "numb": ["flat", "empty", "disconnected", "distant", "detached"]
    ]
}
