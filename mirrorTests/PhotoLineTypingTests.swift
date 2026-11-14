import Testing
import SwiftUI
import UIKit
@testable import mirror

/// A photo keeps a line of its own while typing (2026-11-14): words typed beside a photo used to
/// land on its line, which drew a Thumbnail full width and broke one-token-per-line. Synthetic
/// text only.
@MainActor
struct PhotoLineTypingTests {
    private static let portrait: Data = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { ctx in
        UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 70, height: 100))
    }.pngData()!

    private final class Store {
        var text: String
        var styles: Data?
        var inline: Data?
        var photos: [Data]
        init(text: String, inline: Data?, photos: [Data]) { self.text = text; self.inline = inline; self.photos = photos }
    }

    private func harness(_ text: String, photos: Int, inline: Data? = nil) -> (NoteEditorTextView.Coordinator, UITextView, Store) {
        let store = Store(text: text, inline: inline, photos: Array(repeating: Self.portrait, count: photos))
        let editor = NoteEditorTextView(
            text: Binding(get: { store.text }, set: { store.text = $0 }),
            textStyleData: Binding(get: { store.styles }, set: { store.styles = $0 }),
            inlineStyleData: Binding(get: { store.inline }, set: { store.inline = $0 }),
            photoDataArray: Binding(get: { store.photos }, set: { store.photos = $0 }),
            command: .constant(nil), commandRevision: .constant(0), isFocused: .constant(false),
            activeParagraphStyle: .constant(.body), activeInlineStyles: .constant(InlineStyleSet()),
            showFormattingPanel: .constant(false), canUndo: .constant(false), canRedo: .constant(false),
            fontChoiceRaw: .constant(WritingFontChoice.system.rawValue), panelState: FormattingPanelState(),
            displayMode: .classic
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        textView.delegate = coordinator
        coordinator.applyStyledText(to: textView, preservingSelection: false)
        return (coordinator, textView, store)
    }

    /// Types `replacement` at display offset `location` the way the keyboard does: ask the
    /// delegate, and apply it when allowed.
    private func type(_ replacement: String, at location: Int, in textView: UITextView, _ coordinator: NoteEditorTextView.Coordinator) {
        textView.selectedRange = NSRange(location: location, length: 0)
        let range = NSRange(location: location, length: 0)
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: replacement) {
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = NSRange(location: location + (replacement as NSString).length, length: 0)
            coordinator.textViewDidChange(textView)
        }
    }

    private func backspace(at location: Int, in textView: UITextView, _ coordinator: NoteEditorTextView.Coordinator) {
        let range = NSRange(location: location - 1, length: 1)
        textView.selectedRange = NSRange(location: location, length: 0)
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: "") {
            textView.textStorage.replaceCharacters(in: range, with: "")
            textView.selectedRange = NSRange(location: location - 1, length: 0)
            coordinator.textViewDidChange(textView)
        }
    }

    private let p0 = inlinePhotoToken(at: 0)
    private let p1 = inlinePhotoToken(at: 1)

    @Test func wordsTypedAfterAPhotoStartTheNextLine() {
        let (coordinator, textView, store) = harness(p0, photos: 1)
        type("h", at: 1, in: textView, coordinator)
        type("i", at: textView.selectedRange.location, in: textView, coordinator)
        #expect(store.text == "\(p0)\nhi")
        #expect(textView.selectedRange.location == 4, "caret after the typed words")
    }

    @Test func aThumbnailStaysATileWhenWordsAreTypedBesideIt() {
        let thumb = PhotoSizes.setting(stored: PhotoSizes.thumbnail, atInlineOffset: 0, in: nil)
        let (coordinator, textView, store) = harness(p0, photos: 1, inline: thumb)
        type("x", at: 1, in: textView, coordinator)
        #expect(store.text == "\(p0)\nx")
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail])
        let placement = PhotoPlacement.placements(text: store.text, inlineStyleData: store.inline,
                                                  hasPicture: { _ in true }, isLandscape: { _ in false })[0]
        #expect(placement.isTile)
    }

    @Test func wordsTypedBeforeAPhotoGoOnTheLineAbove() {
        let (coordinator, textView, store) = harness("Day\n\(p0)", photos: 1)
        type("x", at: 4, in: textView, coordinator)
        #expect(store.text == "Day\nx\n\(p0)")
        #expect(textView.selectedRange.location == 5, "caret after the typed letter, above the photo")
    }

    @Test func returnAfterAPhotoIsUnchanged() {
        let (coordinator, textView, store) = harness(p0, photos: 1)
        type("\n", at: 1, in: textView, coordinator)
        #expect(store.text == "\(p0)\n")
    }

    @Test func backspaceUnderAPhotoDoesNotPullWordsOntoItsLine() {
        let (coordinator, textView, store) = harness("\(p0)\nhi", photos: 1)
        backspace(at: 2, in: textView, coordinator)
        #expect(store.text == "\(p0)\nhi")
        #expect(textView.selectedRange.location == 1, "the caret moves to the photo's line end")
    }

    @Test func backspaceBeforeAPhotoDoesNotPullItOntoTheWordsLine() {
        let (coordinator, textView, store) = harness("hi\n\(p0)", photos: 1)
        backspace(at: 3, in: textView, coordinator)
        #expect(store.text == "hi\n\(p0)")
        #expect(textView.selectedRange.location == 2)
    }

    @Test func backspaceBetweenTwoPhotosAndOnBlankLinesIsUnchanged() {
        // An empty line under a photo still goes.
        let (c1, t1, s1) = harness("\(p0)\n\nhi", photos: 1)
        backspace(at: 2, in: t1, c1)
        #expect(s1.text == "\(p0)\nhi")
        // Typing between two photo lines goes on its own line too (it breaks the row).
        let (c2, t2, s2) = harness("\(p0)\n\(p1)", photos: 2)
        type("x", at: 1, in: t2, c2)
        #expect(s2.text == "\(p0)\nx\n\(p1)")
    }

    private func tiles(_ textView: UITextView) -> [Bool] {
        var result: [Bool] = []
        textView.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textView.attributedText.length)) { value, _, _ in
            if let photo = value as? PhotoAttachment { result.append(photo.isTile) }
        }
        return result
    }

    /// Return then words between two tiles: the row splits, and both photos keep their look
    /// (they store "thumbnail" now that no row makes them tiles).
    @Test func typingBetweenTwoTilesKeepsThemTiles() {
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)", photos: 2)
        #expect(tiles(textView) == [true, true])
        type("\n", at: 1, in: textView, coordinator)
        type("w", at: 2, in: textView, coordinator)
        #expect(store.text == "\(p0)\nw\n\(p1)")
        #expect(tiles(textView) == [true, true])
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail, 1: PhotoSizes.thumbnail])
    }

    /// Owner, 14 Pro 2026-11-14: a row of thumbnails, a photo added, Backspace until a photo is
    /// deleted: the photo left alone went back to full width.
    @Test func deletingAPhotoLeavesItsNeighbourAThumbnail() {
        let p2 = inlinePhotoToken(at: 2)
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)\n\(p2)\n", photos: 3)
        #expect(tiles(textView) == [true, true, true])
        let end = (textView.text as NSString).length
        backspace(at: end, in: textView, coordinator)          // the empty last line
        backspace(at: end - 1, in: textView, coordinator)      // photo 2
        #expect(store.photos.count == 2)
        #expect(tiles(textView) == [true, true])
        #expect(store.inline == nil, "still a row: nothing stored")
        backspace(at: (textView.text as NSString).length, in: textView, coordinator)   // photo 1
        #expect(store.photos.count == 1)
        #expect(tiles(textView) == [true], "the photo left keeps its look")
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail])
    }

    /// A photo shown full width (a lone photo, a row's map) stays full width when its neighbour goes.
    @Test func deletingANeighbourOfAFullWidthPhotoStoresNothing() {
        let (coordinator, textView, store) = harness("\(p0)\n\nWords\n\(p1)", photos: 2)
        #expect(tiles(textView) == [false, false])
        backspace(at: (textView.text as NSString).length, in: textView, coordinator)
        #expect(store.photos.count == 1)
        #expect(store.inline == nil)
    }
}
