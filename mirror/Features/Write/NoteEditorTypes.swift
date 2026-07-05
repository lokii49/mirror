import Foundation

// MARK: - Commands

enum NoteTextCommand: Equatable {
    case checklist
    case title
    case heading
    case subheading
    case body
    case monospaced
    case bulletedList
    case dashedList
    case numberedList
    case fontFamily(WritingFontChoice)
    case bold
    case italic
    case underline
    case strikethrough
    case highlight(index: Int?)   // nil = remove highlight; 0-4 = apply color
    case checkAllItems
    case uncheckAllItems
    case deleteCheckedItems
    case sortCheckedToBottom
    case indentMore
    case indentLess
    case photo(index: Int)
    case undo
    case redo
}

// MARK: - Paragraph styles

enum NoteParagraphTextStyle: String, Codable {
    case body
    case title
    case heading
    case subheading
    case monospaced
    case checklistUnchecked
    case checklistChecked
    case bulletedList
    case dashedList
    case numberedList
}

struct NoteTextStyleDocument: Codable {
    var paragraphStyles: [NoteParagraphTextStyle]
    var indentLevels: [Int]?   // nil means all zero; only stored when at least one paragraph has level > 0
    // WritingFontChoice.rawValue per paragraph. nil, or an index past the end of this
    // array, means "no per-paragraph override" — falls back to Entry.fontChoice, then
    // .system. Actively-edited entries store a resolved value at every index; the
    // sparse/absent fallback only ever applies to data written before this field existed.
    var fontChoices: [String]?
}

// MARK: - Inline styles

enum InlineTextStyle: String, CaseIterable {
    case bold, italic, underline, strikethrough
}

struct InlineStyleSet: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false

    var isEmpty: Bool { !bold && !italic && !underline && !strikethrough }

    func contains(_ style: InlineTextStyle) -> Bool {
        switch style {
        case .bold: return bold
        case .italic: return italic
        case .underline: return underline
        case .strikethrough: return strikethrough
        }
    }

    mutating func set(_ style: InlineTextStyle, _ value: Bool) {
        switch style {
        case .bold: bold = value
        case .italic: italic = value
        case .underline: underline = value
        case .strikethrough: strikethrough = value
        }
    }
}

struct InlineStyleRange: Codable, Equatable {
    var location: Int   // logical text coordinate
    var length: Int
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var highlightIndex: Int?
}

struct InlineStyleDocument: Codable {
    var ranges: [InlineStyleRange]
}

// MARK: - Photo tokens

nonisolated func inlinePhotoToken(at index: Int) -> String { "[[mirror-photo-\(index)]]" }

nonisolated func inlinePhotoIndex(from token: String) -> Int? {
    if token == "[[mirror-photo]]" { return 0 }
    let prefix = "[[mirror-photo-"
    let suffix = "]]"
    guard token.hasPrefix(prefix), token.hasSuffix(suffix) else { return nil }
    return Int(token.dropFirst(prefix.count).dropLast(suffix.count))
}

nonisolated func allPhotoTokens(in text: String) -> [(range: Range<String.Index>, index: Int)] {
    var results: [(Range<String.Index>, Int)] = []
    let search = text.startIndex..<text.endIndex
    let regex = try? NSRegularExpression(pattern: #"\[\[mirror-photo(?:-(\d+))?\]\]"#)
    regex?.enumerateMatches(in: text, range: NSRange(search, in: text)) { match, _, _ in
        guard let match, let range = Range(match.range, in: text) else { return }
        let token = String(text[range])
        if let idx = inlinePhotoIndex(from: token) {
            results.append((range, idx))
        }
    }
    return results
}

nonisolated func strippedWordCount(_ s: String) -> Int {
    var cleaned = s
    for (range, _) in allPhotoTokens(in: s).reversed() { cleaned.removeSubrange(range) }
    return cleaned.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
}
