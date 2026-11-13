import Foundation

/// How wide a photo is drawn in an entry (3.1.9, owner 2026-11-13: Small / Medium / Full in the
/// photo's long-press menu). Full is today's look and the default.
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
    /// in a row of thumbnails chosen to be full width stores "full" (`PhotoSizes.setting(stored:)`),
    /// which takes it out of the row.
    var storedValue: String? { self == .full ? nil : rawValue }

    init(stored: String?) {
        self = stored.flatMap(PhotoSize.init(rawValue:)) ?? .full
    }
}

nonisolated enum PhotoSizes {
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

    /// Photos with a size of their own, "full" included, by photo index. They're drawn on their
    /// own, not as thumbnails in a row (`PhotoRuns`).
    static func sizedPhotos(text: String, inlineStyleData: Data?) -> Set<Int> {
        guard let data = inlineStyleData,
              let ranges = try? JSONDecoder().decode(InlineStyleDocument.self, from: data).ranges,
              ranges.contains(where: { $0.photoSize != nil }) else { return [] }
        var result = Set<Int>()
        for (photoIndex, offset) in inlineOffsets(in: text)
            where ranges.contains(where: { $0.photoSize != nil && $0.location <= offset && offset < $0.location + $0.length }) {
            result.insert(photoIndex)
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
            if let range = ranges.last(where: { $0.photoSize != nil && $0.location <= offset && offset < $0.location + $0.length }) {
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
