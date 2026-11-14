import Foundation

/// How wide a photo is drawn in an entry (3.1.9, owner 2026-11-13: Small / Medium / Full in the
/// photo's long-press menu). Full is today's look and the default.
///
/// A size belongs to the photo its range starts on, and only to it: a longer range (an earlier
/// build let the size spread to text typed after the photo) never sizes later photos.
///
/// Stored as `InlineStyleRange.photoSize` on the photo's one character in inline coordinates
/// (`InlineStyleRange.location`), the way a linked photo stores its link. The `[[mirror-photo-N]]`
/// token never changes, so versions before 3.1.9 still show the photo, full width, and drop the
/// size only if they edit that entry. Ranges already move with the text on every edit (typing,
/// list reorders, deleting checked items), so the size moves with its photo.
nonisolated enum PhotoSize: String, CaseIterable, Sendable {
    case small, medium, full

    /// Share of the line's width the picture takes. A photo never grows past its own pixels.
    var widthFraction: Double {
        switch self {
        case .small: 0.36
        case .medium: 0.64
        case .full: 1
        }
    }

    /// The stored value: nil for full width, so an entry without sizes stores nothing new. A photo
    /// in a row of thumbnails chosen to be full width stores "full" (`PhotoPlacement`), which takes
    /// it out of the row.
    var storedValue: String? { self == .full ? nil : rawValue }

    init(stored: String?) {
        self = stored.flatMap(PhotoSize.init(rawValue:)) ?? .full
    }
}

nonisolated enum PhotoSizes {
    /// Stored on a photo on its own line to draw it as one square thumbnail, the size of a tile in a
    /// row (owner, 2026-11-13). In a row it means what no size means there: a thumbnail. Versions
    /// before it (and `PhotoSize(stored:)`) read it as full width.
    static let thumbnail = "thumbnail"

    /// Each photo token in `text`, in order: its photo index and its offset in inline coordinates
    /// (a photo is one character there, its token isn't).
    static func inlineOffsets(in text: String) -> [(photoIndex: Int, offset: Int)] {
        let tokens = allPhotoTokens(in: text)
            .map { (range: NSRange($0.range, in: text), index: $0.index) }
            .sorted { $0.range.location < $1.range.location }
        var result: [(Int, Int)] = []
        var shift = 0
        for token in tokens {
            result.append((token.index, token.range.location - shift))
            shift += token.range.length - 1
        }
        return result
    }

    /// Each photo's stored size ("small", "medium", "full", "thumbnail"), by photo index.
    static func storedSizes(text: String, inlineStyleData: Data?) -> [Int: String] {
        guard let data = inlineStyleData,
              let ranges = try? JSONDecoder().decode(InlineStyleDocument.self, from: data).ranges,
              ranges.contains(where: { $0.photoSize != nil }) else { return [:] }
        var result: [Int: String] = [:]
        for (photoIndex, offset) in inlineOffsets(in: text) {
            if let stored = ranges.last(where: { $0.photoSize != nil && $0.location == offset })?.photoSize { result[photoIndex] = stored }
        }
        return result
    }

    /// The size of each photo that isn't full width, by photo index.
    static func sizes(text: String, inlineStyleData: Data?) -> [Int: PhotoSize] {
        guard let data = inlineStyleData,
              let ranges = try? JSONDecoder().decode(InlineStyleDocument.self, from: data).ranges,
              ranges.contains(where: { $0.photoSize != nil }) else { return [:] }
        var result: [Int: PhotoSize] = [:]
        for (photoIndex, offset) in inlineOffsets(in: text) {
            if let range = ranges.last(where: { $0.photoSize != nil && $0.location == offset }) {
                let size = PhotoSize(stored: range.photoSize)
                if size != .full { result[photoIndex] = size }
            }
        }
        return result
    }

    /// After photo `removed` was taken out of `oldText` (giving `newText`): its own ranges are
    /// dropped and the other photos' one-character ranges move to where their photo is now.
    /// Ranges on the words don't move (a photo is removed from the end of the text, on Mac).
    static func removingPhoto(at removed: Int, oldText: String, newText: String, in inlineStyleData: Data?) -> Data? {
        guard let data = inlineStyleData,
              let ranges = try? JSONDecoder().decode(InlineStyleDocument.self, from: data).ranges else { return inlineStyleData }
        let old = inlineOffsets(in: oldText).map(\.offset)
        let new = inlineOffsets(in: newText).map(\.offset)
        guard old.indices.contains(removed), new.count == old.count - 1 else { return inlineStyleData }
        var result: [InlineStyleRange] = []
        for range in ranges {
            guard range.length == 1, let position = old.firstIndex(of: range.location) else { result.append(range); continue }
            if position == removed { continue }
            var moved = range
            moved.location = new[position < removed ? position : position - 1]
            result.append(moved)
        }
        guard !result.isEmpty else { return nil }
        return try? JSONEncoder().encode(InlineStyleDocument(ranges: result))
    }

    /// The inline document with the photo at inline `offset` set to `size`. Any other style on
    /// that character (a link) is kept; a range that covers more than the photo keeps its other
    /// characters as they were.
    static func setting(_ size: PhotoSize, atInlineOffset offset: Int, in inlineStyleData: Data?) -> Data? {
        setting(stored: size.storedValue, atInlineOffset: offset, in: inlineStyleData)
    }

    /// The same with the stored value itself: "small", "medium", "full" (a photo taken out of a
    /// row of thumbnails at full width) or nil (no size: full width alone, a thumbnail in a row).
    static func setting(stored: String?, atInlineOffset offset: Int, in inlineStyleData: Data?) -> Data? {
        var ranges = inlineStyleData.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0).ranges } ?? []
        var result: [InlineStyleRange] = []
        for range in ranges {
            let covers = range.photoSize != nil && range.location <= offset && offset < range.location + range.length
            guard covers else { result.append(range); continue }
            // Split off the photo's character; the rest keeps its size (it can only be another
            // photo when ranges were merged, which they aren't across different sizes).
            if offset > range.location {
                var before = range
                before.length = offset - range.location
                result.append(before)
            }
            if offset + 1 < range.location + range.length {
                var after = range
                after.location = offset + 1
                after.length = range.location + range.length - (offset + 1)
                result.append(after)
            }
            // The photo's own character, without the size, if it carries anything else.
            var own = range
            own.location = offset
            own.length = 1
            own.photoSize = nil
            if own.bold || own.italic || own.underline || own.strikethrough || own.highlightIndex != nil
                || own.linkURL != nil || own.textColorIndex != nil {
                result.append(own)
            }
        }
        ranges = result
        if let stored {
            ranges.append(InlineStyleRange(location: offset, length: 1, bold: false, italic: false, underline: false,
                                           strikethrough: false, highlightIndex: nil, photoSize: stored))
        }
        ranges.sort { $0.location < $1.location }
        guard !ranges.isEmpty else { return nil }
        return try? JSONEncoder().encode(InlineStyleDocument(ranges: ranges))
    }
}

/// How one photo is drawn: a square tile, or on its own at a share of the line.
nonisolated enum PhotoDrawn: Equatable, Sendable {
    case tile
    case width(PhotoSize)
}

/// The Photo Size menu's choices, in menu order (iPhone, iPad and Mac).
nonisolated enum PhotoSizeOption: String, CaseIterable, Sendable {
    case thumbnail, small, medium, full
}

/// The one photo-size rule (3.1.9, owner 2026-11-14: "photo resizing is still an issue"). The
/// editor's drawing, the iPhone menu, the reader and the Mac picker all read it, so what a photo
/// looks like, which menu item is ticked and what each item stores can't disagree.
///
/// - A *photo line* is a line (split on "\n") that is one photo token with its picture, spaces
///   aside. 2+ photo lines in a row make a *run*; a blank line, a line of spaces or words end it.
/// - In a run, no size draws a square tile, except a landscape first photo (a map), drawn full
///   width. A size of its own ("small", "medium", "full") draws the photo alone at that width,
///   out of the run; its neighbours stay tiles. Runs are found before sizes are applied.
/// - "thumbnail" draws a tile on any photo line, a run of one included. A photo sharing its line
///   with words can't be a tile: it's drawn full width and its menu has no Thumbnail.
/// - The tick is what is drawn. Each choice stores nothing when no size already draws it that
///   way: an unneeded range makes Mac 1.1.8 open the entry read-only.
nonisolated struct PhotoPlacement: Equatable, Sendable {
    var photoIndex: Int
    /// The stored value on the photo's inline character, or nil.
    var stored: String?
    /// The token is the only thing on its line (spaces aside) and has its picture.
    var photoLine: Bool
    /// In a run of 2+ photo lines (photos with a size of their own count).
    var inRun: Bool
    /// First photo of its run and landscape.
    var leadsAsMap: Bool

    /// What a stored value draws in this place.
    func drawn(for stored: String?) -> PhotoDrawn {
        switch stored {
        case nil: inRun && !leadsAsMap ? .tile : .width(.full)
        case PhotoSizes.thumbnail?: photoLine ? .tile : .width(.full)
        case let value?: .width(PhotoSize(stored: value))
        }
    }

    var drawn: PhotoDrawn { drawn(for: stored) }

    var isTile: Bool { drawn == .tile }

    /// The menu item that matches what is drawn.
    var tick: PhotoSizeOption {
        switch drawn {
        case .tile: .thumbnail
        case .width(.small): .small
        case .width(.medium): .medium
        case .width(.full): .full
        }
    }

    /// The menu's choices here: Thumbnail only on a photo line.
    var options: [PhotoSizeOption] { photoLine ? PhotoSizeOption.allCases : [.small, .medium, .full] }

    /// What choosing `option` stores: nil when no size already draws it that way.
    func storedValue(for option: PhotoSizeOption) -> String? {
        let none = drawn(for: nil)
        switch option {
        case .thumbnail: return none == .tile ? nil : PhotoSizes.thumbnail
        case .small: return PhotoSize.small.rawValue
        case .medium: return PhotoSize.medium.rawValue
        case .full: return none == .width(.full) ? nil : PhotoSize.full.rawValue
        }
    }

    /// Every photo token in `text`, in text order. `hasPicture(i)`: photo i's data exists;
    /// `isLandscape(i)`: photo i is wider than tall (`PhotoRuns.isLandscape`).
    static func placements(text: String, inlineStyleData: Data?,
                           hasPicture: (Int) -> Bool, isLandscape: (Int) -> Bool) -> [PhotoPlacement] {
        let ns = text as NSString
        let tokens = allPhotoTokens(in: text)
            .map { (range: NSRange($0.range, in: text), index: $0.index) }
            .sorted { $0.range.location < $1.range.location }
        guard !tokens.isEmpty else { return [] }
        let ranges = (inlineStyleData.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? [])
            .filter { $0.photoSize != nil }

        // Line number of each token, and whether it's a photo line.
        var lineOf: [Int] = []
        var photoLine: [Bool] = []
        var line = 0
        var scanned = 0
        var inlineShift = 0
        var stored: [String?] = []
        for token in tokens {
            for i in scanned..<token.range.location where ns.character(at: i) == 10 { line += 1 }
            scanned = token.range.location
            lineOf.append(line)
            var start = token.range.location
            while start > 0, isSpace(ns.character(at: start - 1)) { start -= 1 }
            var end = NSMaxRange(token.range)
            while end < ns.length, isSpace(ns.character(at: end)) { end += 1 }
            let alone = (start == 0 || ns.character(at: start - 1) == 10) && (end == ns.length || ns.character(at: end) == 10)
            photoLine.append(alone && hasPicture(token.index))
            // A size belongs to the photo its range starts on (`PhotoSizes.storedSizes`).
            let offset = token.range.location - inlineShift
            stored.append(ranges.last(where: { $0.location == offset })?.photoSize)
            inlineShift += token.range.length - 1
        }

        var result: [PhotoPlacement] = []
        for k in tokens.indices {
            // Neighbouring photo lines: the previous / next token on the line just above / below.
            let above = k > 0 && photoLine[k - 1] && lineOf[k - 1] == lineOf[k] - 1
            let below = k + 1 < tokens.count && photoLine[k + 1] && lineOf[k + 1] == lineOf[k] + 1
            let inRun = photoLine[k] && (above || below)
            result.append(PhotoPlacement(photoIndex: tokens[k].index, stored: stored[k], photoLine: photoLine[k], inRun: inRun,
                                         leadsAsMap: inRun && !above && isLandscape(tokens[k].index)))
        }
        return result
    }

    /// By photo index (the first token when one appears twice), for the reader and the Mac.
    static func byPhoto(_ placements: [PhotoPlacement]) -> [Int: PhotoPlacement] {
        var result: [Int: PhotoPlacement] = [:]
        for placement in placements where result[placement.photoIndex] == nil { result[placement.photoIndex] = placement }
        return result
    }

    private static func isSpace(_ c: unichar) -> Bool {
        Unicode.Scalar(c).map { CharacterSet.whitespaces.contains($0) } ?? false
    }
}
