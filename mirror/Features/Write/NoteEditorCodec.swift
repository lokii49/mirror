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
/// markers and checkbox glyphs are never part of the stored text. Inline ranges count a photo
/// as one character, not its token (see `InlineStyleRange.location`); the Mac editor only
/// edits entries whose photos are all at the end, where the two agree. The iOS editor displays
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
        return encodeTextStyleData(models: models, entryFont: entryFont)
    }

    /// The stored document for these paragraphs; nil when nothing is non-default (the iOS rule).
    static func encodeTextStyleData(models: [ParagraphModel], entryFont: WritingFontChoice) -> Data? {
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
            // Title, heading and subheading bold is the paragraph style, not an inline choice (same
            // rule as the iOS editor, which reads bold from the font and cannot tell them apart).
            let style = paragraphModel(at: range.location, in: attributed).style
            let paragraphBold = style == .heading || style == .title || style == .subheading
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

    /// Inline ranges after the "\n"-separated rows of `text` are reordered or dropped (checklist
    /// Sort Done and Delete Done). `rowOrder[i]` is the old index of new row `i`; rows left out are
    /// deleted along with their formatting. Each range is cut at row edges and moves with its row.
    /// Offsets are UTF-16, like `InlineStyleRange`.
    static func remapInlineStyles(_ data: Data?, in text: String, rowOrder: [Int]) -> Data? {
        guard let document = decodeInlineStyleDocument(data), !document.ranges.isEmpty else { return nil }
        let lengths = text.components(separatedBy: "\n").map { ($0 as NSString).length }
        var oldStarts: [Int] = []
        var offset = 0
        for length in lengths {
            oldStarts.append(offset)
            offset += length + 1
        }

        var ranges: [InlineStyleRange] = []
        var newStart = 0
        for oldRow in rowOrder where lengths.indices.contains(oldRow) {
            let rowStart = oldStarts[oldRow]
            let rowEnd = rowStart + lengths[oldRow]
            for range in document.ranges {
                let start = max(range.location, rowStart)
                let end = min(range.location + range.length, rowEnd)
                guard end > start else { continue }
                var moved = range
                moved.location = newStart + (start - rowStart)
                moved.length = end - start
                ranges.append(moved)
            }
            newStart += lengths[oldRow] + 1
        }

        let merged = mergeInlineRanges(ranges)
        guard !merged.isEmpty else { return nil }
        return try? JSONEncoder().encode(InlineStyleDocument(ranges: merged))
    }

    /// Inline ranges after `range` of the text is replaced by `length` new UTF-16 units. Ranges
    /// after the edit shift; a range that overlaps it loses the replaced part, and one that spans
    /// it keeps covering the replacement.
    static func adjustInlineStyles(_ data: Data?, replacing range: NSRange, withLength length: Int) -> Data? {
        guard let document = decodeInlineStyleDocument(data), !document.ranges.isEmpty else { return nil }
        let editEnd = range.location + range.length
        let delta = length - range.length
        func moved(_ offset: Int, isEnd: Bool) -> Int {
            if offset <= range.location { return offset }
            if offset >= editEnd { return offset + delta }
            return isEnd ? range.location : range.location + length
        }
        let ranges = document.ranges.compactMap { styleRange -> InlineStyleRange? in
            let start = moved(styleRange.location, isEnd: false)
            let end = moved(styleRange.location + styleRange.length, isEnd: true)
            guard end > start else { return nil }
            var adjusted = styleRange
            adjusted.location = start
            adjusted.length = end - start
            return adjusted
        }
        let merged = mergeInlineRanges(ranges)
        guard !merged.isEmpty else { return nil }
        return try? JSONEncoder().encode(InlineStyleDocument(ranges: merged))
    }

    /// Inline ranges with bold removed inside `range` (other formatting there stays). Used when a
    /// paragraph leaves Subheading: older iOS builds stored the subheading font's own bold as an
    /// inline range, which would otherwise follow the paragraph into its new style.
    static func clearingBold(_ data: Data?, in range: NSRange) -> Data? {
        guard let document = decodeInlineStyleDocument(data), !document.ranges.isEmpty else { return nil }
        let clearStart = range.location
        let clearEnd = range.location + range.length
        var ranges: [InlineStyleRange] = []
        for styleRange in document.ranges {
            let start = styleRange.location
            let end = styleRange.location + styleRange.length
            guard styleRange.bold, start < clearEnd, end > clearStart else { ranges.append(styleRange); continue }
            func piece(_ from: Int, _ to: Int, bold: Bool) {
                guard to > from else { return }
                var part = styleRange
                part.location = from
                part.length = to - from
                part.bold = bold
                let hasFormatting = part.bold || part.italic || part.underline || part.strikethrough
                    || part.highlightIndex != nil || part.linkURL != nil || part.textColorIndex != nil
                if hasFormatting { ranges.append(part) }
            }
            piece(start, max(start, clearStart), bold: true)
            piece(max(start, clearStart), min(end, clearEnd), bold: false)
            piece(min(end, clearEnd), end, bold: true)
        }
        let merged = mergeInlineRanges(ranges)
        guard !merged.isEmpty else { return nil }
        return try? JSONEncoder().encode(InlineStyleDocument(ranges: merged))
    }

    /// Stored inline ranges moved onto offsets in `text`, for surfaces that apply them to the raw
    /// text (reader, Markdown export). The editor counts a photo as one character; `text` holds its
    /// `[[mirror-photo-N]]` token, so every range after a mid-text photo is shifted by the token's
    /// extra length. A photo that can't be decoded is drawn as a placeholder, so it is one
    /// character too (entries edited before 3.1.0 may have counted it as nothing).
    nonisolated static func inlineRangesInTextCoordinates(_ ranges: [InlineStyleRange], text: String) -> [InlineStyleRange] {
        let tokens = allPhotoTokens(in: text).map { NSRange($0.range, in: text) }.sorted { $0.location < $1.location }
        guard !tokens.isEmpty, !ranges.isEmpty else { return ranges }
        // Each photo's position in editor coordinates and how much longer its token is.
        var photos: [(position: Int, extra: Int)] = []
        var shift = 0
        for token in tokens {
            photos.append((token.location - shift, token.length - 1))
            shift += token.length - 1
        }
        func textOffset(_ offset: Int) -> Int {
            offset + photos.reduce(0) { offset > $1.position ? $0 + $1.extra : $0 }
        }
        return ranges.map { range in
            var moved = range
            let start = textOffset(range.location)
            moved.location = start
            moved.length = textOffset(range.location + range.length) - start
            return moved
        }
    }

    // MARK: - Repairing photo-line damage (one-time cleanup)

    /// The list markers the iOS editor draws (all indent levels), as `NoteEditorTextView` renders them.
    nonisolated static let staticListMarkers = ["•  ", "◦  ", "▸  ", "–  ", "·  ", "○  ", "✓  "]

    /// Length of a list marker at the start of `line` ("•  ", "1.\t", legacy "1.  "), else 0.
    static func leadingListMarkerLength(in line: NSString) -> Int {
        for marker in staticListMarkers where line.hasPrefix(marker) { return (marker as NSString).length }
        var i = 0
        while i < line.length, (48...57).contains(line.character(at: i)) { i += 1 }
        guard i > 0, i < line.length, line.character(at: i) == 46 else { return 0 }   // "."
        i += 1
        if i < line.length, line.character(at: i) == 9 { return i + 1 }               // "\t"
        if i + 1 < line.length, line.character(at: i) == 32, line.character(at: i + 1) == 32 { return i + 2 }
        return 0
    }

    /// Undoes what the pre-3.1.0 iOS editor saved into the text of entries with a mid-text photo
    /// (audit item 2): a list marker drawn on the photo line and saved right after the token
    /// ("[[mirror-photo-0]]•  "), and list items below a photo whose own marker was saved into
    /// their text ("•  milk" stored as a bulleted paragraph, shown "•  •  milk"). The editor never
    /// writes either, so both are removed; only lines from the first photo line on are touched.
    /// Inline ranges move with the deleted characters. Styles that were shifted cannot be told
    /// from real ones and are left alone. Nil when there is nothing to repair.
    static func repairPhotoMarkerDamage(text: String, textStyleData: Data?, inlineStyleData: Data?) -> (text: String, inlineStyleData: Data?)? {
        let nsText = text as NSString
        let tokens = allPhotoTokens(in: text).map { NSRange($0.range, in: text) }.sorted { $0.location < $1.location }
        guard let firstToken = tokens.first else { return nil }

        let starts = paragraphStarts(in: nsText)
        func lineRange(_ index: Int) -> NSRange {
            let end = index + 1 < starts.count ? starts[index + 1] - 1 : nsText.length
            return NSRange(location: starts[index], length: end - starts[index])
        }
        var deletions: [NSRange] = []

        // Markers saved right after a token that starts its line.
        for token in tokens where token.location == 0 || nsText.character(at: token.location - 1) == 10 {
            var end = NSMaxRange(token)
            while end < nsText.length {
                let rest = nsText.substring(from: end) as NSString
                let markerLength = leadingListMarkerLength(in: rest)
                guard markerLength > 0 else { break }
                end += markerLength
            }
            if end > NSMaxRange(token) { deletions.append(NSRange(location: NSMaxRange(token), length: end - NSMaxRange(token))) }
        }

        // A list paragraph below a photo whose text starts with a marker.
        if let styles = decodeTextStyleDocument(textStyleData)?.paragraphStyles {
            let firstPhotoLine = starts.lastIndex { $0 <= firstToken.location } ?? 0
            for index in starts.indices where index > firstPhotoLine && styles.indices.contains(index) && isListStyle(styles[index]) {
                let line = lineRange(index)
                var length = 0
                while true {
                    let rest = nsText.substring(with: NSRange(location: line.location + length, length: line.length - length)) as NSString
                    let markerLength = leadingListMarkerLength(in: rest)
                    guard markerLength > 0 else { break }
                    length += markerLength
                }
                if length > 0 { deletions.append(NSRange(location: line.location, length: length)) }
            }
        }
        guard !deletions.isEmpty else { return nil }

        // Delete from the end so earlier offsets stay valid. Inline ranges count a photo as one
        // character, so each deletion is moved into those coordinates first.
        var repaired = nsText
        var inline = inlineStyleData
        for deletion in deletions.sorted(by: { $0.location > $1.location }) {
            let extraBefore = tokens.reduce(0) { NSMaxRange($1) <= deletion.location ? $0 + $1.length - 1 : $0 }
            inline = adjustInlineStyles(inline, replacing: NSRange(location: deletion.location - extraBefore, length: deletion.length), withLength: 0)
            repaired = repaired.replacingCharacters(in: deletion, with: "") as NSString
        }
        return (repaired as String, inline)
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
