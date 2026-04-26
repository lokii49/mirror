import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case typed
    case voice
}

@Model final class Entry {
    var id: UUID = UUID()
    var text: String = ""           // plain text — used for Claude API + search
    var richTextData: Data? = nil   // archived NSAttributedString — source of truth for display
    var createdAt: Date = Date()
    var wordCount: Int = 0
    var source: EntrySource = EntrySource.typed
    var weekIdentifier: String = ""
    var mood: String? = nil
    var tags: [String] = []
    var title: String = ""

    init(text: String, richTextData: Data? = nil, source: EntrySource = .typed, mood: String? = nil, title: String? = nil) {
        self.id = UUID()
        self.text = text
        self.richTextData = richTextData
        self.createdAt = Date()
        self.wordCount = text.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
        self.source = source
        self.weekIdentifier = DateHelpers.weekIdentifier(for: Date())
        self.mood = mood
        self.tags = Self.extractTags(from: text)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.extractTitle(from: text)
    }

    static func extractTags(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![&\w])#([a-zA-Z]\w{1,})"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
            .uniqued()
            .prefix(20)
            .map { $0 }
    }

    static func extractTitle(from text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let s = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip native list markers before deriving the display title.
                .replacingOccurrences(of: #"^[•☐☑○●]\t"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\d+\.\t"#, with: "", options: .regularExpression)
            if !s.isEmpty { return String(s.prefix(80)) }
        }
        return ""
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
