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
    /// A row's photo that was never given a size stays a thumbnail too when it's left alone:
    /// the rule can't tell a chosen Thumbnail from one the row made (both store nothing), so
    /// every photo keeps the look it had.
    @Test func aRowPhotoNeverSizedStaysAThumbnailWhenLeftAlone() {
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)", photos: 2)
        #expect(tiles(textView) == [true, true])
        backspace(at: (textView.text as NSString).length, in: textView, coordinator)
        #expect(store.photos.count == 1)
        #expect(tiles(textView) == [true])
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail])
    }

    /// Deleting the first photo renumbers the rest: the row photo left alone keeps its tile, the
    /// full-width photo below the blank line stays full width, and a stored size moves with it.
    @Test func deletingTheFirstPhotoKeepsEachOtherPhotosLook() {
        let p2 = inlinePhotoToken(at: 2)
        let small = PhotoSizes.setting(stored: "small", atInlineOffset: 5, in: nil)   // P0 \n P1 \n \n P2: a photo counts as one
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)\n\n\(p2)", photos: 3, inline: small)
        #expect(tiles(textView) == [true, true, false])
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [2: "small"])
        backspace(at: 1, in: textView, coordinator)   // photo 0
        #expect(store.photos.count == 2)
        #expect(store.text == "\(p0)\n\n\(p1)")
        #expect(tiles(textView) == [true, false])
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail, 1: "small"])
    }

    /// Deleting a middle photo of a row of three leaves a row of two: nothing to store.
    @Test func deletingAMiddlePhotoLeavesTheRow() {
        let p2 = inlinePhotoToken(at: 2), p3 = inlinePhotoToken(at: 3)
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)\n\(p2)\n\nWords\n\(p3)", photos: 4)
        #expect(tiles(textView) == [true, true, true, false])
        backspace(at: 3, in: textView, coordinator)   // photo 1 (display: P0 \n P1)
        #expect(store.photos.count == 3)
        #expect(tiles(textView) == [true, true, false])
        #expect(store.inline == nil)
    }
    /// Replaces `range` with `replacement` the way the keyboard does (a selection delete, Cut,
    /// or a paste over a selection).
    private func replace(_ range: NSRange, with replacement: String, in textView: UITextView, _ coordinator: NoteEditorTextView.Coordinator) {
        textView.selectedRange = range
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: replacement) {
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = NSRange(location: range.location + (replacement as NSString).length, length: 0)
            coordinator.textViewDidChange(textView)
        }
    }

    /// Backspace at the start of the second photo's line never puts two photos on one line
    /// (3.1.7's reader and the Mac would show the raw tokens): the caret moves up instead.
    @Test func backspaceBetweenTwoPhotoLinesNeverJoinsThem() {
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)", photos: 2)
        backspace(at: 2, in: textView, coordinator)
        #expect(store.text == "\(p0)\n\(p1)")
        #expect(textView.selectedRange.location == 1)
        #expect(tiles(textView) == [true, true])
    }

    /// A selection from words down to a photo's line, deleted: the photo keeps its own line.
    @Test func selectionDeleteFromWordsOntoAPhotoKeepsItsLine() {
        let (coordinator, textView, store) = harness("ab\ncd\n\(p0)", photos: 1)
        replace(NSRange(location: 1, length: 5), with: "", in: textView, coordinator)   // "b\ncd\n"
        #expect(store.text == "a\n\(p0)")
        #expect(textView.selectedRange.location == 1, "caret after the kept words")
    }

    /// Words pasted over a selection that ran from one photo's line to the next: each photo
    /// keeps its own line and the words go between them.
    @Test func pasteOverASelectionBetweenTwoPhotos() {
        let (coordinator, textView, store) = harness("\(p0)\nab\n\(p1)", photos: 2)
        replace(NSRange(location: 1, length: 4), with: "xy", in: textView, coordinator)   // "\nab\n"
        #expect(store.text == "\(p0)\nxy\n\(p1)")
        #expect(textView.selectedRange.location == 4, "caret after the pasted words")
    }

    /// A paste of words with a line break, between two tiles: both keep their look.
    @Test func pasteBetweenTwoTilesKeepsThemTiles() {
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)", photos: 2)
        type("\nPasted words", at: 1, in: textView, coordinator)
        #expect(store.text == "\(p0)\nPasted words\n\(p1)")
        #expect(tiles(textView) == [true, true])
    }

    /// Selecting the words between two thumbnails and deleting them makes the row again.
    @Test func selectionDeleteOfWordsBetweenPhotosRejoinsTheRow() {
        let (coordinator, textView, store) = harness("\(p0)\nab\n\(p1)", photos: 2)
        replace(NSRange(location: 2, length: 3), with: "", in: textView, coordinator)   // "ab\n"
        #expect(store.text == "\(p0)\n\(p1)")
        #expect(tiles(textView) == [true, true])
    }

    /// A selection over a photo and the words under it.
    @Test func selectionDeleteOverAPhotoAndWords() {
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)\nab", photos: 2)
        replace(NSRange(location: 2, length: 4), with: "", in: textView, coordinator)   // P1 \n a b
        #expect(!store.text.contains("\(p0)\(p1)"))
        #expect(onePhotoPerLine(store.text), "each photo on a line of its own: \(store.text.debugDescription)")
        #expect(store.text.contains("ab"), "the words outside the photo are kept or the whole selection goes")
    }

    private func onePhotoPerLine(_ text: String) -> Bool {
        text.components(separatedBy: "\n").allSatisfy { line in
            let tokens = allPhotoTokens(in: line).count
            return tokens == 0 || (tokens == 1 && allPhotoTokens(in: line).first.map { line.trimmingCharacters(in: .whitespaces) == String(line[$0.range]) } == true)
        }
    }
    /// Typing just before the second photo of a row: the words go on their own line and both
    /// photos keep their look (the line break goes in with the words, never after them).
    @Test func typingJustBeforeASecondRowPhotoKeepsBothTiles() {
        let (coordinator, textView, store) = harness("\(p0)\n\(p1)", photos: 2)
        type("a", at: 2, in: textView, coordinator)
        #expect(store.text == "\(p0)\na\n\(p1)")
        #expect(textView.selectedRange.location == 3, "caret after the typed letter")
        #expect(tiles(textView) == [true, true])
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail, 1: PhotoSizes.thumbnail])
    }

    /// A selection from words over the photo under them: the photo goes and the words' bold
    /// stays where it was (the removal is made at the photo, not at the selection's start).
    @Test func selectionDeleteFromWordsOverAPhotoKeepsTheWordsFormatting() throws {
        let bold = InlineStyleRange(location: 0, length: 2, bold: true, italic: false, underline: false,
                                    strikethrough: false, highlightIndex: nil, photoSize: nil)
        let inline = try JSONEncoder().encode(InlineStyleDocument(ranges: [bold]))
        let (coordinator, textView, store) = harness("ab\n\(p0)", photos: 1, inline: inline)
        replace(NSRange(location: 1, length: 3), with: "", in: textView, coordinator)   // "b\n" + photo
        #expect(store.photos.isEmpty)
        #expect(!store.text.contains("mirror-photo"))
        let ranges = store.inline.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? []
        #expect(ranges.contains { $0.bold && $0.location == 0 && $0.length == 2 }, "bold still on \"ab\": \(ranges)")
    }
}
