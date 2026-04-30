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

    static func search(query: String, in entries: [Entry], limit: Int = 8) -> [Entry] {
        let keywords = extractKeywords(from: query)
        guard !keywords.isEmpty else {
            return Array(entries.prefix(limit))
        }

        let matched = entries.filter { entry in
            let lower = entry.insightContext.lowercased()
            return keywords.contains { lower.contains($0) }
        }

        let results = matched.isEmpty ? Array(entries) : matched
        return Array(results.prefix(limit))
    }

    static func filter(query: String, in entries: [Entry]) -> [Entry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter { $0.insightContext.lowercased().contains(lower) }
    }

    private static func extractKeywords(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .init(charactersIn: " .,!?;:\"'()[]{}"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
