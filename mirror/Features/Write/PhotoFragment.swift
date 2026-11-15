import Foundation

/// What Copy or Cut puts on the clipboard when the selection has photos in it (3.1.9, owner
/// 2026-11-15: "photos should travel"): the selection's lines in order, each a line of words or a
/// photo with its picture, size and link. Paste in the editor puts them back as lines of their
/// own. It carries no token text and no photo numbers: the entry it lands in numbers the photos.
/// Other apps still get the words as plain text.
nonisolated struct PhotoFragment: Codable, Equatable, Sendable {
    static let pasteboardType = "org.mirrornotes.editor-fragment"
    /// A clipboard is untrusted: more than this and the paste is refused.
    static let maxPhotos = 20

    struct Line: Codable, Equatable, Sendable {
        /// The line's words; empty for a photo line.
        var text: String = ""
        /// A photo line: the prepared picture, as stored in the entry.
        var photo: Data?
        /// The stored size ("thumbnail", "small", "medium", "full"), nil for none.
        var size: String?
        /// The link the photo opens (a map), as stored on its inline character.
        var link: String?
        /// Drawn as a square tile when it was copied: it keeps that look where it lands.
        var wasTile: Bool = false
    }

    var lines: [Line]

    var photos: [Data] { lines.compactMap(\.photo) }

    /// The words alone, for other apps.
    var plainText: String { lines.filter { $0.photo == nil }.map(\.text).joined(separator: "\n") }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(_ data: Data) -> PhotoFragment? {
        guard let fragment = try? JSONDecoder().decode(PhotoFragment.self, from: data),
              !fragment.lines.isEmpty, fragment.photos.count <= maxPhotos else { return nil }
        return fragment
    }

    /// The entry after the fragment goes in under paragraph `afterParagraph` (the caret's; the last
    /// when nil), every line of it on a line of its own. On an empty line it takes that line's
    /// place. `photoCount`: pictures the entry has now; the fragment's get the next numbers, in
    /// order (the caller appends `photos` to the entry's pictures). `hasPicture` / `isLandscape`
    /// answer for the entry's pictures with the fragment's already appended. One result, so one
    /// undo step.
    func inserted(into text: String, afterParagraph: Int?, textStyleData: Data?, inlineStyleData: Data?,
                  photoCount: Int, entryFont: String,
                  hasPicture: (Int) -> Bool, isLandscape: (Int) -> Bool) -> (text: String, textStyleData: Data?, inlineStyleData: Data?) {
        var number = photoCount
        let block: [String] = lines.map { line in
            guard line.photo != nil else { return line.text.replacingOccurrences(of: "\n", with: " ") }
            defer { number += 1 }
            return inlinePhotoToken(at: number)
        }
        var existing = text.components(separatedBy: "\n")
        let at = max(0, min(afterParagraph ?? (existing.count - 1), existing.count - 1))
        let replacesLine = existing[at].trimmingCharacters(in: .whitespaces).isEmpty
        // How each photo already in the entry is drawn, to keep that look (`keepingTiles`).
        let before = PhotoPlacement.byPhoto(PhotoPlacement.placements(
            text: text, inlineStyleData: inlineStyleData, hasPicture: hasPicture, isLandscape: isLandscape))

        // Inline coordinates: a photo is one character.
        func logicalLength(_ string: String) -> Int {
            (string as NSString).length - allPhotoTokens(in: string).reduce(0) { $0 + (NSRange($1.range, in: string).length - 1) }
        }
        let blockText = block.joined(separator: "\n")
        let isLast = at == existing.count - 1
        let replaced: NSRange
        let insertedLength: Int
        if replacesLine {
            // The empty line's own characters (spaces) give way to the block.
            replaced = NSRange(location: logicalLength(existing[..<at].map { $0 + "\n" }.joined()), length: logicalLength(existing[at]))
            insertedLength = logicalLength(blockText)
        } else if isLast {
            // At the end: a line break, then the block.
            replaced = NSRange(location: logicalLength(text), length: 0)
            insertedLength = logicalLength(blockText) + 1
        } else {
            // Mid-entry: the block, then a line break, at the start of the next line.
            replaced = NSRange(location: logicalLength(existing[...at].map { $0 + "\n" }.joined()), length: 0)
            insertedLength = logicalLength(blockText) + 1
        }
        // Formatting before the block stays, after it moves down; a range across the place is
        // split around the block, so nothing of the entry's formatting lands on the new lines.
        let oldRanges = inlineStyleData.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? []
        let replacedEnd = NSMaxRange(replaced), delta = insertedLength - replaced.length
        let movedRanges = oldRanges.flatMap { range -> [InlineStyleRange] in
            var pieces: [InlineStyleRange] = []
            let start = range.location, end = range.location + range.length
            if start < replaced.location {
                var head = range; head.length = min(end, replaced.location) - start; pieces.append(head)
            }
            if end > replacedEnd {
                var tail = range
                let from = max(start, replacedEnd)
                tail.location = from + delta; tail.length = end - from
                pieces.append(tail)
            }
            return pieces.filter { $0.length > 0 }
        }
        var inline: Data? = movedRanges.isEmpty ? nil : try? JSONEncoder().encode(InlineStyleDocument(ranges: movedRanges))

        if replacesLine {
            existing.replaceSubrange(at...at, with: block)
        } else {
            existing.insert(contentsOf: block, at: at + 1)
        }
        let newText = existing.joined(separator: "\n")

        // Paragraph styles: body for every line of the block.
        var styles = textStyleData
        if let data = textStyleData, var document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data) {
            let oldCount = text.components(separatedBy: "\n").count
            func spliced<T>(_ values: [T], _ filler: T) -> [T] {
                var padded = Array(values.prefix(oldCount))
                padded += Array(repeating: filler, count: oldCount - padded.count)
                let added = Array(repeating: filler, count: block.count)
                if replacesLine { padded.replaceSubrange(at...at, with: added) } else { padded.insert(contentsOf: added, at: at + 1) }
                return padded
            }
            document.paragraphStyles = spliced(document.paragraphStyles, .body)
            if let indents = document.indentLevels { document.indentLevels = spliced(indents, 0) }
            if let fonts = document.fontChoices { document.fontChoices = spliced(fonts, entryFont) }
            styles = try? JSONEncoder().encode(document)
        }

        // Sizes and links on the new photos, at their places in the new text.
        let offsets = PhotoSizes.inlineOffsets(in: newText)
        var photoLines = lines.filter { $0.photo != nil }[...]
        var wasTile: [Bool?] = []
        for place in offsets {
            guard place.photoIndex >= photoCount, let line = photoLines.first else {
                wasTile.append(before[place.photoIndex]?.isTile)
                continue
            }
            photoLines = photoLines.dropFirst()
            wasTile.append(line.wasTile)
            if let size = line.size, [PhotoSizes.thumbnail, "small", "medium", "full"].contains(size) {
                inline = PhotoSizes.setting(stored: size, atInlineOffset: place.offset, in: inline)
            }
            if let link = line.link, let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                var ranges = inline.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? []
                if let k = ranges.firstIndex(where: { $0.location == place.offset && $0.length == 1 }) {
                    ranges[k].linkURL = link
                } else {
                    ranges.append(InlineStyleRange(location: place.offset, length: 1, bold: false, italic: false, underline: false,
                                                   strikethrough: false, highlightIndex: nil, linkURL: link))
                }
                inline = try? JSONEncoder().encode(InlineStyleDocument(ranges: ranges))
            }
        }
        inline = PhotoPlacement.keepingTiles(wasTile: wasTile, text: newText, inlineStyleData: inline,
                                             hasPicture: hasPicture, isLandscape: isLandscape)
        return (newText, styles, inline)
    }
}
