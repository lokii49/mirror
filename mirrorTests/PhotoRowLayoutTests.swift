#if os(iOS)
import Testing
import UIKit
@testable import mirror

/// The editor draws thumbnail tiles three to a line (`PhotoRowLayout`), as the reader does, while
/// the text keeps one photo per line. TextKit 1 stack as the editor builds it.
@MainActor
@Suite("Photo row layout")
struct PhotoRowLayoutTests {
    private let tileSide: CGFloat = 100
    private let lineWidth: CGFloat = 340

    private func photo(tile: Bool, side: CGFloat = 100, height: CGFloat? = nil) -> NSAttributedString {
        let attachment = PhotoAttachment()
        let size = CGSize(width: side, height: height ?? side)
        attachment.image = UIGraphicsImageRenderer(size: size).image { _ in }
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: size)
        attachment.fullBounds = attachment.bounds
        attachment.isTile = tile
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        style.paragraphSpacing = 8
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes([.paragraphStyle: style, .font: UIFont.systemFont(ofSize: 17)], range: NSRange(location: 0, length: 1))
        return result
    }

    private func words(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17)])
    }

    /// The TextKit stack, kept together: a layout manager holds its text storage weakly, so a
    /// dropped storage leaves an empty layout.
    final class Stack {
        let storage: NSTextStorage, lm: ChecklistLayoutManager, container: NSTextContainer
        init(_ storage: NSTextStorage, _ lm: ChecklistLayoutManager, _ container: NSTextContainer) {
            self.storage = storage; self.lm = lm; self.container = container
        }
    }

    /// Lays `parts` out as the editor does.
    private func layout(_ parts: [NSAttributedString]) -> Stack {
        let text = NSMutableAttributedString()
        parts.forEach { text.append($0) }
        let storage = NSTextStorage(attributedString: text)
        let lm = ChecklistLayoutManager()
        lm.delegate = lm.photoRows
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: CGSize(width: lineWidth, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)
        lm.ensureLayout(for: container)
        return Stack(storage, lm, container)
    }

    private func fragment(_ lm: NSLayoutManager, char: Int) -> CGRect {
        lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: char), effectiveRange: nil)
    }

    private func hit(_ lm: NSLayoutManager, _ container: NSTextContainer, _ point: CGPoint) -> Int {
        lm.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
    }

    @Test func threeTilesShareALineAndAFourthWraps() {
        // "Hi\n" T0 "\n" T1 "\n" T2 "\n" T3 "\n" "After"
        let nl = words("\n")
        let stack = layout([words("Hi\n"), photo(tile: true), nl, photo(tile: true), nl,
                                         photo(tile: true), nl, photo(tile: true), nl, words("After")])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        let t0 = fragment(lm, char: 3), t1 = fragment(lm, char: 5), t2 = fragment(lm, char: 7), t3 = fragment(lm, char: 9)
        #expect(t0.minY == t1.minY && t1.minY == t2.minY)
        #expect(t0.minX == 0 && t1.minX == tileSide + PhotoRowLayout.gap && t2.minX == 2 * (tileSide + PhotoRowLayout.gap))
        #expect(t2.maxX <= lineWidth + 0.5)
        #expect(t3.minX == 0 && t3.minY >= t0.maxY - 0.5)
        let after = fragment(lm, char: 11)
        #expect(after.minX == 0 && after.minY >= t3.maxY - 0.5, "words after the row start under it")
        // A tap on each tile finds that tile's photo.
        let y = t0.minY + 40
        #expect(hit(lm, container, CGPoint(x: 50, y: y)) == 3)
        #expect(hit(lm, container, CGPoint(x: t1.minX + 50, y: y)) == 5)
        #expect(hit(lm, container, CGPoint(x: t2.minX + 50, y: y)) == 7)
        #expect(hit(lm, container, CGPoint(x: 50, y: t3.minY + 40)) == 9)
    }

    @Test func aMapLeadsFullWidthAndTheTilesStartUnderIt() {
        let nl = words("\n")
        let stack = layout([photo(tile: false, side: 300, height: 170), nl, photo(tile: true), nl, photo(tile: true), nl])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        let map = fragment(lm, char: 0), t1 = fragment(lm, char: 2), t2 = fragment(lm, char: 4)
        #expect(t1.minX == 0 && t1.minY >= map.maxY - 0.5)
        #expect(t2.minY == t1.minY && t2.minX > t1.minX)
    }

    @Test func aSizedPhotoInARunEndsTheRowAndTheNextTilesStartANewOne() {
        let nl = words("\n")
        let stack = layout([photo(tile: true), nl, photo(tile: false, side: 200), nl, photo(tile: true), nl, photo(tile: true)])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        let t0 = fragment(lm, char: 0), sized = fragment(lm, char: 2), t2 = fragment(lm, char: 4), t3 = fragment(lm, char: 6)
        #expect(sized.minX == 0 && sized.minY >= t0.maxY - 0.5)
        #expect(t2.minX == 0 && t2.minY >= sized.maxY - 0.5)
        #expect(t3.minY == t2.minY && t3.minX > 0)
    }

    @Test func wordsBetweenTilesBreakTheRow() {
        let nl = words("\n")
        let stack = layout([photo(tile: true), words("\nnote\n"), photo(tile: true)])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        let t0 = fragment(lm, char: 0), t1 = fragment(lm, char: 7)
        #expect(t1.minX == 0 && t1.minY > t0.minY)
        _ = nl
    }

    @Test func aShorterTileDoesNotLetTheNextLineOverlapTheRow() {
        let nl = words("\n")
        let stack = layout([photo(tile: true, height: 140), nl, photo(tile: true, height: 60), nl, words("After")])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        let t0 = fragment(lm, char: 0), after = fragment(lm, char: 4)
        #expect(after.minY >= t0.maxY - 0.5)
    }

    @Test func spacesAroundATileKeepItInTheRow() {
        let stack = layout([photo(tile: true), words("\n "), photo(tile: true), words(" \n"), photo(tile: true)])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        let t0 = fragment(lm, char: 0), t1 = fragment(lm, char: 2), t2 = fragment(lm, char: 6)
        #expect(t1.minY == t0.minY && t2.minY == t0.minY)
        #expect(t1.minX > t0.minX && t2.minX > t1.minX)
    }

    /// UITextView lays out lazily (non-contiguous): a tile far down the page is laid out alone,
    /// before the tile beside it. It must still land beside it, as on the 14 Pro (2026-11-15).
    @Test func lazyLayoutStillPutsALaterTileBesideTheOneBefore() {
        let nl = words("\n")
        let long = words(String(repeating: "A line of words to push the photos well down the page.\n", count: 120))
        let text = NSMutableAttributedString()
        [long, photo(tile: true), nl, photo(tile: true), nl, words("After")].forEach { text.append($0) }
        let storage = NSTextStorage(attributedString: text)
        let lm = ChecklistLayoutManager()
        lm.allowsNonContiguousLayout = true
        lm.delegate = lm.photoRows
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: CGSize(width: lineWidth, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)
        defer { withExtendedLifetime(storage) {} }
        let first = (storage.string as NSString).range(of: "\u{FFFC}").location
        // Ask for the second tile first, nothing laid out before it.
        let second = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: first + 2), length: 1), in: container)
        let firstRect = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: first), length: 1), in: container)
        #expect(second.width > 0)
        #expect(abs(second.minY - firstRect.minY) < 1, "beside, not under: \(firstRect) \(second)")
        #expect(second.minX > firstRect.maxX - 1)
    }

    /// The editor sets its text again on each render. With UIKit's lazy layout that left a tile
    /// beside a map at a stale place (14 Pro, 2026-11-15); the editor turns lazy layout off while
    /// tiles are drawn.
    @Test func settingTheTextAgainKeepsATileBesideTheOneBefore() {
        let storage = NSTextStorage()
        let lm = ChecklistLayoutManager()
        storage.addLayoutManager(lm)
        storage.delegate = lm.markerSpacing
        lm.delegate = lm.photoRows
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = UITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), textContainer: container)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        let nl = words("\n")
        let text = NSMutableAttributedString()
        [photo(tile: false, side: 340, height: 190), nl, photo(tile: true), nl, photo(tile: true)].forEach { text.append($0) }
        #expect(PhotoRowLayout.hasTiles(in: text))
        lm.allowsNonContiguousLayout = !PhotoRowLayout.hasTiles(in: text)
        for _ in 0..<2 {
            tv.attributedText = text
            tv.layoutIfNeeded()
            let t1 = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: 2), length: 1), in: container)
            let t2 = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: 4), length: 1), in: container)
            #expect(abs(t1.minY - t2.minY) < 1 && t2.minX >= t1.maxX, "\(t1) \(t2)")
            #expect(tv.caretRect(for: tv.endOfDocument).minX > t2.minX, "end caret after the last tile")
        }
        #expect(!PhotoRowLayout.hasTiles(in: words("No photos")))
    }

    /// TextKit can lay a tile line out as two fragments (the picture, then its line break). The
    /// break's fragment stays in the picture's cell, and the next tile measures from the picture
    /// (editor on the 14 Pro and the simulator, 2026-11-15: the next tile went off the right edge).
    @Test func aTileLinesBreakLaidOutAloneStaysInItsCell() {
        let nl = words("\n")
        let stack = layout([photo(tile: true), nl, photo(tile: true), nl, words("After")])
        let lm = stack.lm, container = stack.container
        defer { withExtendedLifetime(stack) {} }
        let cell = fragment(lm, char: 0)
        var rect = CGRect(x: 0, y: cell.maxY, width: lineWidth, height: 28)
        var used = CGRect(x: 0, y: cell.maxY, width: 8, height: 20)
        var baseline: CGFloat = 16
        let handled = lm.photoRows.layoutManager(lm, shouldSetLineFragmentRect: &rect, lineFragmentUsedRect: &used,
                                                 baselineOffset: &baseline, in: container,
                                                 forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: 1), length: 1))
        #expect(handled)
        #expect(rect.minY == cell.minY && rect.maxY <= cell.maxY + 0.5, "\(rect) in \(cell)")
        #expect(rect.minX >= cell.minX + tileSide - 0.5 && rect.maxX <= cell.maxX + 0.5)
        // The next tile still goes beside the picture, one cell over.
        var next = CGRect(x: 0, y: cell.maxY + 28, width: lineWidth, height: 116)
        var nextUsed = CGRect(x: 0, y: cell.maxY + 28, width: 100, height: 108)
        _ = lm.photoRows.layoutManager(lm, shouldSetLineFragmentRect: &next, lineFragmentUsedRect: &nextUsed,
                                       baselineOffset: &baseline, in: container,
                                       forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: 2, length: 2), actualCharacterRange: nil))
        #expect(next.minY == cell.minY && next.minX == cell.minX + tileSide + PhotoRowLayout.gap)
    }

    /// The editor doesn't scroll: UIKit keeps its text container as tall as the view, which is as
    /// tall as the side-by-side layout. TextKit first tries a later tile where it would stack (below
    /// the one before), finds no room and drops it, before the delegate can move it up (14 Pro and
    /// simulator, 2026-11-15: the second tile after a map vanished).
    @Test func aNonScrollingEditorAsTallAsTheRowStillDrawsTheLastTile() {
        let storage = NSTextStorage()
        let lm = ChecklistLayoutManager()
        storage.addLayoutManager(lm)
        lm.delegate = lm.photoRows
        let container = PhotoRowTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = UITextView(frame: CGRect(x: 0, y: 0, width: 380, height: 100), textContainer: container)
        tv.isScrollEnabled = false
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        let nl = words("\n")
        let text = NSMutableAttributedString()
        [photo(tile: false, side: 340, height: 190), nl, photo(tile: true), nl, photo(tile: true)].forEach { text.append($0) }
        tv.attributedText = text
        // Size the view to fit, as SwiftUI does, then lay out again at that height.
        for _ in 0..<3 {
            let fit = tv.sizeThatFits(CGSize(width: 380, height: CGFloat.greatestFiniteMagnitude))
            tv.frame.size = CGSize(width: 380, height: fit.height)
            tv.layoutIfNeeded()
        }
        lm.ensureLayout(for: container)
        let t1 = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: 2), length: 1), in: container)
        let t2 = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: 4), length: 1), in: container)
        #expect(t2.width > 0, "last tile laid out: \(t2), container \(container.size)")
        #expect(abs(t1.minY - t2.minY) < 1 && t2.minX >= t1.maxX)
    }

    @Test func editingAboveTheRowKeepsItSideBySide() {
        let nl = words("\n")
        let stack = layout([words("Hi\n"), photo(tile: true), nl, photo(tile: true), nl, photo(tile: true)])
        let lm = stack.lm, storage = stack.storage, container = stack.container
        _ = (storage, container); defer { withExtendedLifetime(stack) {} }
        storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "A much longer first line that wraps onto a second line here\nand a third")
        lm.ensureLayout(for: container)
        let ns = storage.string as NSString
        let first = ns.range(of: "\u{FFFC}").location
        let t0 = fragment(lm, char: first), t1 = fragment(lm, char: first + 2), t2 = fragment(lm, char: first + 4)
        #expect(t0.minY == t1.minY && t1.minY == t2.minY)
        #expect(t0.minX == 0 && t1.minX > 0 && t2.minX > t1.minX)
    }
}
#endif
