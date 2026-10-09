import Foundation

enum SearchService {
    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "was", "are", "were", "be", "been",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "can", "i", "me", "my", "we", "our",
        "you", "your", "he", "she", "it", "they", "them", "their", "this",
        "that", "these", "those", "what", "when", "where", "how", "why", "who",
        "about", "just", "so", "up", "out", "if", "its", "also", "then", "than",
        "not", "no", "very", "really", "feel", "felt", "feeling", "think", "thought"
    ]

    /// A keyword found in more than this share of the entries carries no signal ("ich", "que" and
    /// "time" otherwise match nearly everything, and the newest entries win).
    static let genericKeywordShare = 0.25
    /// Below this many entries the share cutoff would drop real topic words (2 gym entries out of 5
    /// is 40%), so small journals rely on the IDF weight alone.
    static let genericCutoffMinimumEntries = 20

    /// Ask's retrieval. Keywords match whole words by `searchStem` ("migraines" finds "migraine",
    /// "pet" no longer finds "carpet"), entries are ranked by the summed IDF of the keywords they
    /// contain, ties keep `entries`' order (newest first at both call sites), and no match at all
    /// falls back to the first `limit` entries. Measured on synthetic journals in
    /// tools/llmrig/retrieval (2026-10-08, `kw-stemidf`), against the old substring search.
    static func search(query: String, in entries: [Entry], limit: Int = 8) -> [Entry] {
        let keywords = Set(extractKeywords(from: query).map(searchStem))
        guard !keywords.isEmpty, !entries.isEmpty else {
            return Array(entries.prefix(limit))
        }

        let stems: [Set<String>] = entries.map { entry in
            Set(words(in: ([entry.insightContext] + entry.tags).joined(separator: " ")).map(searchStem))
        }
        let count = Double(entries.count)
        var weights: [String: Double] = [:]
        for keyword in keywords {
            let documentFrequency = Double(stems.filter { $0.contains(keyword) }.count)
            guard documentFrequency > 0 else { continue }
            if entries.count >= genericCutoffMinimumEntries, documentFrequency / count > genericKeywordShare { continue }
            weights[keyword] = log(count / documentFrequency)
        }

        var scored: [(index: Int, score: Double)] = []
        for (index, entryStems) in stems.enumerated() {
            var score = 0.0
            for (keyword, weight) in weights where entryStems.contains(keyword) {
                score += weight
            }
            if score > 0 { scored.append((index, score)) }
        }
        guard !scored.isEmpty else {
            return Array(entries.prefix(limit))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return scored.prefix(limit).map { entries[$0.index] }
    }

    /// `InsightService.askStem`, then a trailing "e" dropped, so "migraine"/"migraines" and
    /// "argue"/"argued" meet (askStem gives "migraine" vs "migrain", "argue" vs "argu").
    static func searchStem(_ word: String) -> String {
        dropTrailingE(InsightService.askStem(word))
    }

    private static func dropTrailingE(_ stem: String) -> String {
        stem.count > 3 && stem.hasSuffix("e") ? String(stem.dropLast()) : stem
    }

    /// One split for questions and entries: any character that isn't a letter or digit separates
    /// words, apostrophes of both kinds included, so "Mom's" and "Mom’s" give "mom", and
    /// "l'entretien" gives "entretien".
    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func filter(query: String, in entries: [Entry]) -> [Entry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        let raw = query.lowercased()
        let tagQuery = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        return entries.filter {
            $0.insightContext.lowercased().contains(raw)
            || (!tagQuery.isEmpty && $0.tags.contains { $0.lowercased().contains(tagQuery) })
        }
    }

    private static func extractKeywords(from text: String) -> [String] {
        words(in: text).filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
