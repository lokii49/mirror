import Foundation

/// Serializes entries to Markdown using the stored rich-text model
/// (`NoteTextStyleDocument` + `InlineStyleDocument`, see `NoteEditorTypes.swift`)
/// instead of the plain `entry.text` the existing text export uses. Plain-text
/// export silently drops bold/lists/checklists/highlights even though
/// `ArchiveSettingsView.importEntries(from:)` can read formatted files back in —
/// an export you can't reimport with fidelity, against "your data is always yours."
enum MarkdownExportService {
    static func export(entries: [Entry]) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        return entries.map { entry -> String in
            var block = "## \(formatter.string(from: entry.createdAt))"
            if let mood = entry.mood { block += "  \n*Mood: \(mood)*" }
            let body = markdownBody(for: entry)
            if !body.isEmpty { block += "\n\n\(body)" }
            return block
        }
        .joined(separator: "\n\n---\n\n")
    }

    static func markdownBody(for entry: Entry) -> String {
        if entry.textDecryptionFailed { return "*Encrypted entry unavailable*" }
        let text = entry.text
        guard !text.isEmpty else { return "" }

        let paragraphStyles = decodedParagraphStyles(entry.textStyleData)
        let indentLevels = decodedIndentLevels(entry.textStyleData)
        let inlineRanges = decodedInlineRanges(entry.inlineStyleData)

        let nsText = text as NSString
        var lines: [String] = []
        var paragraphIndex = 0
        // Keyed by indent level — matches NoteEditorTextView's renderer so a
        // nested numbered sub-list restarts at 1 instead of continuing the
        // parent sequence, and exported Markdown numbering matches what the
        // editor actually displays.
        var numberedCounters: [Int: Int] = [:]

        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, subRange, _, _ in
            let style = paragraphIndex < paragraphStyles.count ? paragraphStyles[paragraphIndex] : .body
            let level = paragraphIndex < indentLevels.count ? indentLevels[paragraphIndex] : 0
            let raw = nsText.substring(with: subRange)
            let styled = applyingInlineStyles(raw: raw, paragraphStart: subRange.location, ranges: inlineRanges)

            var numberedCounter = 0
            if style == .numberedList {
                numberedCounters = numberedCounters.filter { $0.key <= level }
                numberedCounter = (numberedCounters[level] ?? 0) + 1
                numberedCounters[level] = numberedCounter
            } else {
                numberedCounters.removeAll()
            }
            lines.append(markdownLine(for: styled, style: style, level: level, number: numberedCounter))
            paragraphIndex += 1
        }

        return textWithPhotoTokensReplaced(lines.joined(separator: "\n"))
    }

    // MARK: - Decoding

    private static func decodedParagraphStyles(_ data: Data?) -> [NoteParagraphTextStyle] {
        guard let data, let doc = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data) else { return [] }
        return doc.paragraphStyles
    }

    private static func decodedIndentLevels(_ data: Data?) -> [Int] {
        guard let data, let doc = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data), let levels = doc.indentLevels else { return [] }
        return levels
    }

    private static func decodedInlineRanges(_ data: Data?) -> [InlineStyleRange] {
        guard let data, let doc = try? JSONDecoder().decode(InlineStyleDocument.self, from: data) else { return [] }
        return doc.ranges.sorted { $0.location < $1.location }
    }

    // MARK: - Inline styling

    /// `ranges` come from `NSAttributedString.enumerateAttributes`, so they're
    /// already non-overlapping — this only clips each one to the paragraph's
    /// span and wraps the covered substring, no interval-merging needed.
    private static func applyingInlineStyles(raw: String, paragraphStart: Int, ranges: [InlineStyleRange]) -> String {
        guard !ranges.isEmpty else { return raw }
        let ns = raw as NSString
        let paragraphEnd = paragraphStart + ns.length

        let relevant: [(NSRange, InlineStyleRange)] = ranges.compactMap { r in
            let start = max(r.location, paragraphStart)
            let end = min(r.location + r.length, paragraphEnd)
            guard end > start else { return nil }
            return (NSRange(location: start - paragraphStart, length: end - start), r)
        }
        guard !relevant.isEmpty else { return raw }

        var result = ""
        var cursor = 0
        for (localRange, style) in relevant {
            guard localRange.location >= cursor else { continue }  // defensive: ranges shouldn't overlap post-clip
            if localRange.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: localRange.location - cursor))
            }
            result += wrapped(ns.substring(with: localRange), style: style)
            cursor = localRange.location + localRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    private static func wrapped(_ text: String, style: InlineStyleRange) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        if style.underline { result = "<u>\(result)</u>" }
        if style.strikethrough { result = "~~\(result)~~" }
        if style.italic { result = "*\(result)*" }
        if style.bold { result = "**\(result)**" }
        if style.highlightIndex != nil { result = "==\(result)==" }
        // Outermost: other emphasis nests inside the link text, e.g. [**bold**](url).
        if let urlString = style.linkURL, !urlString.isEmpty { result = "[\(result)](\(urlString))" }
        return result
    }

    // MARK: - Paragraph markers

    private static func markdownLine(for text: String, style: NoteParagraphTextStyle, level: Int, number: Int) -> String {
        let indent = String(repeating: "  ", count: max(0, level))
        switch style {
        case .body:              return text
        case .title:             return "# \(text)"
        case .heading:           return "## \(text)"
        case .subheading:        return "### \(text)"
        case .monospaced:        return text.isEmpty ? text : "`\(text)`"
        case .blockQuote:        return "> \(text)"
        case .checklistUnchecked: return "\(indent)- [ ] \(text)"
        case .checklistChecked:  return "\(indent)- [x] \(text)"
        case .bulletedList:      return "\(indent)- \(text)"
        case .dashedList:        return "\(indent)- \(text)"
        case .numberedList:      return "\(indent)\(number). \(text)"
        }
    }
}
