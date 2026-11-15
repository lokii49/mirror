#if os(iOS)
import UIKit

/// Draws the editor's thumbnail tiles side by side, three to a line, as the reader and the Mac app
/// do (owner, 2026-11-15: "unable to place images side by side").
///
/// Layout only. The text is unchanged: each photo is still one attachment character on a line of
/// its own, so `keepsPhotoOnItsLine`, inline-range offsets, `PhotoFragment` and every older reader
/// see exactly what they saw before. Which photos are tiles is `PhotoPlacement`'s rule, read from
/// `PhotoAttachment.isTile`; this never decides it.
///
/// TextKit 1 places each line fragment under the one before it. For a tile line that follows
/// another tile line, this moves the fragment up beside it: same top, next column. The line after
/// a row then starts under the row's tallest tile, because each later tile carries the row's
/// height. Caret rects, selection and `characterIndex(for:)` all read fragment rects, so taps,
/// holds and the caret follow the tiles.
final class PhotoRowLayout: NSObject, NSLayoutManagerDelegate {
    static let columns = 3
    static let gap: CGFloat = 8

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return false }
        let ns = storage.string as NSString
        let first = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        guard first < ns.length else { return false }
        let paragraph = ns.paragraphRange(for: NSRange(location: first, length: 0))
        guard let (tile, picture) = Self.tile(in: paragraph, of: storage) else { return false }
        let containerWidth = textContainer.size.width
        var rect = lineFragmentRect.pointee
        var used = lineFragmentUsedRect.pointee

        // TextKit can lay a tile line out as two fragments, the picture and then its line break
        // (seen in the editor on the 14 Pro and the simulator). The break's fragment stays inside
        // the picture's cell, just right of it, so the line after it isn't pushed down and the
        // caret after the picture sits beside it.
        let pictureGlyph = layoutManager.glyphIndexForCharacter(at: picture)
        if !NSLocationInRange(pictureGlyph, glyphRange) {
            guard first > picture else { return false }
            let cellRect = layoutManager.lineFragmentRect(forGlyphAt: pictureGlyph, effectiveRange: nil,
                                                          withoutAdditionalLayout: true)
            guard cellRect.height > 0 else { return false }
            rect = CGRect(x: cellRect.minX + tile.bounds.width, y: cellRect.minY,
                          width: max(1, cellRect.maxX - cellRect.minX - tile.bounds.width), height: cellRect.height)
            used = CGRect(x: rect.minX, y: rect.minY, width: 0, height: min(used.height, rect.height))
            lineFragmentRect.pointee = rect
            lineFragmentUsedRect.pointee = used
            return true
        }

        // Column: how many tile lines come right before this one in the same run.
        var column = 0
        var start = paragraph.location
        var previousPicture: Int?
        while start > 0 {
            let previous = ns.paragraphRange(for: NSRange(location: start - 1, length: 0))
            guard let found = Self.tile(in: previous, of: storage) else { break }
            if previousPicture == nil { previousPicture = found.index }
            column += 1
            start = previous.location
        }
        column %= Self.columns

        let cell = tile.bounds.width + Self.gap
        if column > 0, let previousPicture {
            // The tile before this one is already laid out (fragments are laid out in order).
            // Measured from its picture's own fragment, never its line break's.
            let previousRect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: previousPicture),
                                                              effectiveRange: nil, withoutAdditionalLayout: true)
            guard previousRect.height > 0 else { return false }
            rect.origin.y = previousRect.minY
            // Carry the row's height, so the line after the row starts under its tallest tile.
            rect.size.height = max(rect.height, previousRect.height)
            rect.origin.x = previousRect.minX + cell
        } else {
            rect.origin.x = 0
        }
        // The last column takes what's left of the line (no sliver to its right to tap into).
        rect.size.width = column == Self.columns - 1 || containerWidth <= 0
            ? max(cell, containerWidth - rect.minX)
            : cell
        used.origin = CGPoint(x: rect.minX, y: rect.minY)
        used.size.width = min(used.width, rect.width)
        lineFragmentRect.pointee = rect
        lineFragmentUsedRect.pointee = used
        return true
    }

    /// Whether `text` draws any thumbnail tile.
    static func hasTiles(in text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if (value as? PhotoAttachment)?.isTile == true { found = true; stop.pointee = true }
        }
        return found
    }

    /// The tile drawn on `paragraph` and its character, when the line is one tile and spaces.
    static func tile(in paragraph: NSRange, of storage: NSAttributedString) -> (attachment: PhotoAttachment, index: Int)? {
        guard paragraph.length > 0, NSMaxRange(paragraph) <= storage.length else { return nil }
        let ns = storage.string as NSString
        var found: (attachment: PhotoAttachment, index: Int)?
        for i in paragraph.location..<NSMaxRange(paragraph) {
            let c = ns.character(at: i)
            if c == 0xFFFC {
                guard found == nil,
                      let attachment = storage.attribute(.attachment, at: i, effectiveRange: nil) as? PhotoAttachment,
                      attachment.isTile else { return nil }
                found = (attachment, i)
            } else if c != 0x20, c != 0x09, c != 10, c != 13, c != 0x2028, c != 0x2029 {
                return nil
            }
        }
        return found
    }
}

/// The editor's text container: as wide as UIKit makes it, never limited in height.
///
/// The editor doesn't scroll, and UIKit then keeps its container only as tall as the view, which
/// SwiftUI sizes to the laid-out text. A tile drawn beside the one before it ends higher than
/// TextKit first proposes (under that tile), so with the height limit TextKit found no room for
/// it and dropped it before `PhotoRowLayout` could move it up: the tile vanished (2026-11-15).
final class PhotoRowTextContainer: NSTextContainer {
    override var size: CGSize {
        get { super.size }
        set { super.size = CGSize(width: newValue.width, height: CGFloat.greatestFiniteMagnitude) }
    }
}
#endif
