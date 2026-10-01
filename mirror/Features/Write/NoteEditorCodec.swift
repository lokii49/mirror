import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The rich-text note format, independent of any text view.
///
/// An entry stores its text plus two optional JSON documents (`textStyleData`: one style per
/// paragraph; `inlineStyleData`: character ranges), both in *logical* coordinates: list
/// markers and checkbox glyphs are never part of the stored text. The iOS editor displays
/// markers as real characters and maps display offsets to logical ones; the Mac editor draws
/// markers outside the text, so its display text IS the logical text and no mapping exists.
///
/// This codec holds the Mac editor's side of the contract: build an attributed string carrying
/// only *model* attributes (paragraph style, indent, font choice, inline flags), and read the
/// two documents back out. Fonts and colors are applied by the view layer from those attributes.
/// It compiles on iOS so the iOS test target can check it against the iOS editor's own output.
enum NoteEditorCodec {

    // MARK: - Model attribute keys

    // The first five match the iOS coordinator's keys by name.
    static let paragraphStyleKey = NSAttributedString.Key("mirror.paragraphStyle")
    static let highlightIndexKey = NSAttributedString.Key("mirror.highlightIndex")
    static let textColorIndexKey = NSAttributedString.Key("mirror.textColorIndex")
    static let indentLevelKey = NSAttributedString.Key("mirror.indentLevel")
    static let fontChoiceKey = NSAttributedString.Key("mirror.fontChoice")
    /// Explicit inline bold/italic. Kept as flags (not read back from the font) so a restyle that
    /// recomputes fonts from the paragraph style cannot lose them.
    static let boldKey = NSAttributedString.Key("mirror.inlineBold")
    static let italicKey = NSAttributedString.Key("mirror.inlineItalic")

    // MARK: - Paragraph model

    /// What a paragraph carries. `fontChoice == nil` means "the entry default".
    struct ParagraphModel: Equatable {
        var style: NoteParagraphTextStyle = .body
        var indent: Int = 0
        var fontChoice: WritingFontChoice? = nil

        var attributes: [NSAttributedString.Key: Any] {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if style != .body { attrs[NoteEditorCodec.paragraphStyleKey] = style.rawValue }
            if indent > 0 { attrs[NoteEditorCodec.indentLevelKey] = indent }
            if let fontChoice { attrs[NoteEditorCodec.fontChoiceKey] = fontChoice.rawValue }
            return attrs
        }
    }

    static func isListStyle(_ style: NoteParagraphTextStyle) -> Bool {
        switch style {
        case .checklistUnchecked, .checklistChecked, .bulletedList, .dashedList, .numberedList: return true
        default: return false
        }
    }

    // MARK: - Decoding

    static func decodeTextStyleDocument(_ data: Data?) -> NoteTextStyleDocument? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
    }

    static func decodeInlineStyleDocument(_ data: Data?) -> InlineStyleDocument? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(InlineStyleDocument.self, from: data)
    }

    /// The paragraph models stored for an entry, one per stored index.
    static func storedParagraphs(from data: Data?, entryFont: WritingFontChoice) -> [ParagraphModel] {
        guard let document = decodeTextStyleDocument(data) else { return [] }
        return document.paragraphStyles.indices.map { index in
            var model = ParagraphModel()
            model.style = document.paragraphStyles[index]
            if let levels = document.indentLevels, levels.indices.contains(index) { model.indent = levels[index] }
            if let choices = document.fontChoices, choices.indices.contains(index),
               let choice = WritingFontChoice(rawValue: choices[index]), choice != entryFont {
                model.fontChoice = choice
            }
            return model
        }
    }

    // MARK: - Building the model attributed string

    struct Rendered {
        var attributed: NSMutableAttributedString
        /// The paragraph after a final newline (or the only paragraph of an empty text) has no
        /// characters to hang attributes on; its model lives here.
        var trailing: ParagraphModel
    }

    /// Paragraphs are split on "\n" exactly like the iOS renderer (`components(separatedBy:)`), so
    /// "a\n" has two paragraphs and the stored style at index 1 belongs to the empty last one.
    static func render(text: String, textStyleData: Data?, inlineStyleData: Data?, entryFont: WritingFontChoice) -> Rendered {
        let paragraphs = storedParagraphs(from: textStyleData, entryFont: entryFont)
        let attributed = NSMutableAttributedString(string: text)
        let nsText = text as NSString
        var location = 0
        var index = 0
        var trailing = ParagraphModel()

        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            let isLast = location + lineLength >= nsText.length
            let model = paragraphs.indices.contains(index) ? paragraphs[index] : ParagraphModel()
            let enclosing = NSRange(location: location, length: min(lineLength + (isLast ? 0 : 1), nsText.length - location))
            if enclosing.length > 0 {
                attributed.addAttributes(model.attributes, range: enclosing)
            }
            if isLast { trailing = model }
            location += lineLength + 1
            index += 1
        }

        applyInlineStyles(from: inlineStyleData, to: attributed)
        return Rendered(attributed: attributed, trailing: trailing)
    }

    /// Inline ranges are logical coordinates and so are ours: no mapping, just clamping.
    static func applyInlineStyles(from data: Data?, to attributed: NSMutableAttributedString) {
        guard let document = decodeInlineStyleDocument(data) else { return }
        let length = attributed.length
        for range in document.ranges {
            let start = max(0, min(range.location, length))
            let end = max(start, min(range.location + range.length, length))
            guard end > start else { continue }
            let nsRange = NSRange(location: start, length: end - start)
            if range.bold { attributed.addAttribute(boldKey, value: true, range: nsRange) }
            if range.italic { attributed.addAttribute(italicKey, value: true, range: nsRange) }
            if range.underline { attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange) }
            if range.strikethrough { attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange) }
            if let idx = range.highlightIndex { attributed.addAttribute(highlightIndexKey, value: idx, range: nsRange) }
            if let idx = range.textColorIndex { attributed.addAttribute(textColorIndexKey, value: idx, range: nsRange) }
            if let url = validatedLinkURL(from: range.linkURL) { attributed.addAttribute(.link, value: url, range: nsRange) }
        }
    }

    // MARK: - Reading a paragraph back

    static func paragraphModel(at location: Int, in attributed: NSAttributedString) -> ParagraphModel {
        guard attributed.length > 0 else { return ParagraphModel() }
        let loc = min(max(0, location), attributed.length - 1)
        var model = ParagraphModel()
        if let raw = attributed.attribute(paragraphStyleKey, at: loc, effectiveRange: nil) as? String,
           let style = NoteParagraphTextStyle(rawValue: raw) {
            model.style = style
        }
        model.indent = attributed.attribute(indentLevelKey, at: loc, effectiveRange: nil) as? Int ?? 0
        if let raw = attributed.attribute(fontChoiceKey, at: loc, effectiveRange: nil) as? String {
            model.fontChoice = WritingFontChoice(rawValue: raw)
        }
        return model
    }

    /// Start offsets of every "\n"-separated paragraph, including a final empty one.
    static func paragraphStarts(in text: NSString) -> [Int] {
        var starts = [0]
        var i = 0
        while i < text.length {
            if text.character(at: i) == 10 { starts.append(i + 1) }
            i += 1
        }
        return starts
    }

    /// The marker number of each paragraph in a numbered list; nil elsewhere. A nested list
    /// restarts at 1 and returning to the outer list resumes its own count (same rule as iOS).
    static func numberedIndices(for models: [ParagraphModel]) -> [Int?] {
        var counters: [Int: Int] = [:]
        return models.map { model in
            if model.style == .numberedList {
                counters = counters.filter { $0.key <= model.indent }
                let next = (counters[model.indent] ?? 0) + 1
                counters[model.indent] = next
                return next
            }
            counters.removeAll()
            return nil
        }
    }

    // MARK: - Extraction: textStyleData

    static func extractTextStyleData(from attributed: NSAttributedString, trailing: ParagraphModel, entryFont: WritingFontChoice) -> Data? {
        let text = attributed.string as NSString
        let starts = paragraphStarts(in: text)
        var models: [ParagraphModel] = []

        for (index, start) in starts.enumerated() {
            let isLast = index == starts.count - 1
            let isEmptyLast = isLast && start >= text.length
            if isEmptyLast {
                // The iOS display text shows a list marker for an empty last list item, so
                // iOS enumerates (and stores) it; a plain empty last paragraph is invisible
                // there and is not stored.
                if isListStyle(trailing.style) { models.append(trailing) }
            } else {
                models.append(paragraphModel(at: start, in: attributed))
            }
        }
        guard !models.isEmpty else { return nil }

        let hasIndent = models.contains { $0.indent > 0 }
        let hasFontOverride = models.contains { ($0.fontChoice ?? entryFont) != entryFont }
        guard models.contains(where: { $0.style != .body }) || hasIndent || hasFontOverride else { return nil }

        return try? JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: models.map(\.style),
            indentLevels: hasIndent ? models.map(\.indent) : nil,
            fontChoices: models.map { ($0.fontChoice ?? entryFont).rawValue }
        ))
    }

    // MARK: - Extraction: inlineStyleData

    static func extractInlineStyleData(from attributed: NSAttributedString) -> Data? {
        guard attributed.length > 0 else { return nil }
        var ranges: [InlineStyleRange] = []

        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            // Title and heading bold is the paragraph style, not an inline choice.
            let style = paragraphModel(at: range.location, in: attributed).style
            let paragraphBold = style == .heading || style == .title
            let bold = (attrs[boldKey] as? Bool ?? false) && !paragraphBold
            let italic = attrs[italicKey] as? Bool ?? false
            let underline = attrs[.underlineStyle] != nil
            let strikethrough = attrs[.strikethroughStyle] != nil
            let highlight = attrs[highlightIndexKey] as? Int
            let textColor = attrs[textColorIndexKey] as? Int
            let link = (attrs[.link] as? URL)?.absoluteString

            guard bold || italic || underline || strikethrough || highlight != nil || link != nil || textColor != nil else { return }
            ranges.append(InlineStyleRange(
                location: range.location,
                length: range.length,
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough,
                highlightIndex: highlight,
                linkURL: link,
                textColorIndex: textColor
            ))
        }

        let merged = mergeInlineRanges(ranges)
        guard !merged.isEmpty else { return nil }
        return try? JSONEncoder().encode(InlineStyleDocument(ranges: merged))
    }

    /// Same rule as the iOS coordinator's `mergeInlineRanges`.
    static func mergeInlineRanges(_ ranges: [InlineStyleRange]) -> [InlineStyleRange] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { $0.location < $1.location }
        var result: [InlineStyleRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = result[result.count - 1]
            let lastEnd = last.location + last.length
            if range.location <= lastEnd
                && range.bold == last.bold
                && range.italic == last.italic
                && range.underline == last.underline
                && range.strikethrough == last.strikethrough
                && range.highlightIndex == last.highlightIndex
                && range.linkURL == last.linkURL
                && range.textColorIndex == last.textColorIndex {
                result[result.count - 1] = InlineStyleRange(
                    location: last.location,
                    length: max(lastEnd, range.location + range.length) - last.location,
                    bold: last.bold, italic: last.italic,
                    underline: last.underline, strikethrough: last.strikethrough,
                    highlightIndex: last.highlightIndex,
                    linkURL: last.linkURL,
                    textColorIndex: last.textColorIndex
                )
            } else {
                result.append(range)
            }
        }
        return result
    }

    // MARK: - Safety gate

    // MARK: - Photos at the end of the text

    /// A photo is stored as a `[[mirror-photo-N]]` token line inside the text. The Mac editor does
    /// not draw photos inline; it supports photos only when every token sits at the very end of
    /// the text (what attaching a photo produces), shows them as thumbnails under the editor, and
    /// keeps the tokens out of the editable text.
    static func splitTrailingPhotoTokens(_ text: String) -> (body: String, count: Int) {
        var rest = text
        while rest.hasSuffix("\n") { rest.removeLast() }
        var count = 0
        let pattern = #"\[\[mirror-photo(?:-\d+)?\]\]$"#
        while let range = rest.range(of: pattern, options: .regularExpression) {
            rest.removeSubrange(range.lowerBound..<rest.endIndex)
            count += 1
            if rest.hasSuffix("\n") { rest.removeLast() }
        }
        // No photo tokens: the text is untouched (its trailing newlines are content).
        return count == 0 ? (text, 0) : (rest, count)
    }

    /// The inverse of `splitTrailingPhotoTokens`: the body with one token line per photo.
    static func appendingPhotoTokens(to body: String, count: Int) -> String {
        var text = body
        for index in 0..<max(0, count) {
            let token = inlinePhotoToken(at: index)
            if text.isEmpty {
                text = token
            } else {
                var trimmed = text
                if index > 0 { while trimmed.hasSuffix("\n") { trimmed.removeLast() } }
                text = trimmed + "\n" + token + "\n"
            }
        }
        return text
    }

    // MARK: - Safety gate

    /// True when an entry can be edited by the Mac editor without changing what iPhone and iPad
    /// read back. Photos are allowed only when their tokens are all at the end of the text and
    /// match the stored photos one to one; legacy entries (no style document, block style inferred
    /// from a "# ", "○ ", "✓ " or 4-space prefix) are converted by the iOS editor only. The round
    /// trip check proves the stored documents survive load → save unchanged; anything it cannot
    /// prove stays read-only on Mac.
    static func canEditOnMac(text: String, textStyleData: Data?, inlineStyleData: Data?, entryFont: WritingFontChoice, photoCount: Int) -> Bool {
        let (body, tokenCount) = splitTrailingPhotoTokens(text)
        guard tokenCount == photoCount,
              allPhotoTokens(in: body).isEmpty,
              appendingPhotoTokens(to: body, count: tokenCount) == text
        else { return false }
        if textStyleData == nil, hasLegacyPrefix(body) { return false }

        let rendered = render(text: body, textStyleData: textStyleData, inlineStyleData: inlineStyleData, entryFont: entryFont)
        let styles = extractTextStyleData(from: rendered.attributed, trailing: rendered.trailing, entryFont: entryFont)
        let inline = extractInlineStyleData(from: rendered.attributed)
        return normalizedParagraphs(styles, entryFont: entryFont) == normalizedParagraphs(textStyleData, entryFont: entryFont)
            && decodeInlineStyleDocument(inline)?.ranges == decodeInlineStyleDocument(inlineStyleData)?.ranges
    }

    /// Stored style documents compared by meaning: absent font choices and indent levels mean
    /// "default", and trailing all-default paragraphs carry no information.
    private static func normalizedParagraphs(_ data: Data?, entryFont: WritingFontChoice) -> [ParagraphModel] {
        var models = storedParagraphs(from: data, entryFont: entryFont)
        while let last = models.last, last == ParagraphModel() { models.removeLast() }
        return models
    }

    static func hasLegacyPrefix(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { line in
            line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ")
                || line.hasPrefix("    ") || line.hasPrefix("○ ") || line.hasPrefix("✓ ")
        }
    }
}

extension InlineStyleDocument: Equatable {
    static func == (lhs: InlineStyleDocument, rhs: InlineStyleDocument) -> Bool {
        lhs.ranges == rhs.ranges
    }
}
