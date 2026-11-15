import Foundation
import Testing
@testable import mirror

/// Mac 1.1.9 edits entries with photos between lines (owner, 2026-11-15, option A): the Mac
/// editor's text holds each such photo as one U+FFFC carrying its number and size, as inline
/// ranges count it. These check the codec's side: text → editor → text gives back the same text
/// and the same documents.
@Suite("Mac photo text")
struct MacPhotoTextTests {
    private func roundTrip(_ text: String, inline: Data? = nil, styles: Data? = nil) -> (text: String, inline: Data?, styles: Data?) {
        let rendered = NoteEditorCodec.render(text: text, textStyleData: styles, inlineStyleData: inline, entryFont: .system)
        return (NoteEditorCodec.textFromEditor(rendered.attributed),
                NoteEditorCodec.extractInlineStyleData(from: rendered.attributed),
                NoteEditorCodec.extractTextStyleData(from: rendered.attributed, trailing: rendered.trailing, entryFont: .system))
    }

    private func ranges(_ data: Data?) -> [InlineStyleRange] {
        NoteEditorCodec.decodeInlineStyleDocument(data)?.ranges ?? []
    }

    @Test func aPhotoBetweenLinesIsOneCharacterAndComesBack() {
        let text = "Walked to the lake.\n[[mirror-photo-0]]\nMade soup."
        let display = NoteEditorCodec.editorDisplay(text)
        #expect(display.string == "Walked to the lake.\n\u{FFFC}\nMade soup.")
        #expect(display.numbers == [0])
        #expect(roundTrip(text).text == text)
        #expect(NoteEditorCodec.displayLength(text) == (display.string as NSString).length)
    }

    @Test func numbersStayWithTheirPhotosNotTheirPlaces() {
        // Paperclip above an older photo, or a row reordered on iPhone: numbers out of text order.
        let text = "a\n[[mirror-photo-2]]\nb\n[[mirror-photo-0]]\n[[mirror-photo-1]]"
        #expect(NoteEditorCodec.editorDisplay(text).numbers == [2, 0, 1])
        #expect(roundTrip(text).text == text)
    }

    @Test func aSizeAndALinkOnAPhotoBetweenLinesSurvive() {
        let text = "Lunch\n[[mirror-photo-0]]\nAfter"
        // Inline coordinates: "Lunch\n" is 6, the photo is offset 6.
        var sized = InlineStyleRange(location: 6, length: 1, bold: false, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        sized.photoSize = "small"
        sized.linkURL = "https://maps.apple.com/?q=lake"
        var bold = InlineStyleRange(location: 8, length: 5, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        bold.linkURL = nil
        let inline = try? JSONEncoder().encode(InlineStyleDocument(ranges: [sized, bold]))
        let back = roundTrip(text, inline: inline)
        #expect(back.text == text)
        #expect(ranges(back.inline) == [sized, bold])
    }

    @Test func paragraphStylesKeepTheirLinesAroundAPhoto() {
        let text = "Title\n[[mirror-photo-0]]\nitem"
        let doc = NoteTextStyleDocument(paragraphStyles: [.heading, .body, .checklistUnchecked])
        let styles = try? JSONEncoder().encode(doc)
        let back = roundTrip(text, styles: styles)
        #expect(back.text == text)
        let models = NoteEditorCodec.storedParagraphs(from: back.styles, entryFont: .system).map(\.style)
        #expect(Array(models.prefix(3)) == [.heading, .body, .checklistUnchecked])
    }

    @Test func trailingPhotosKeepTheirNumbersWhenTheBodyChanges() {
        let text = "Words\n[[mirror-photo-1]]\nmore\n[[mirror-photo-2]]\n[[mirror-photo-0]]"
        #expect(NoteEditorCodec.trailingPhotoNumbers(text) == [2, 0])
        let body = NoteEditorCodec.splitTrailingPhotoTokens(text).body
        #expect(body == "Words\n[[mirror-photo-1]]\nmore")
        let edited = NoteEditorCodec.replacingBody(of: text, with: body + " and more")
        #expect(edited == "Words\n[[mirror-photo-1]]\nmore and more\n[[mirror-photo-2]]\n[[mirror-photo-0]]\n")
        // The old count-based writer would have renumbered them 0, 1.
        #expect(NoteEditorCodec.trailingPhotoNumbers(edited) == [2, 0])
    }

    // MARK: Editing around a photo (`photoLineEdit`)

    private let doc = "Lake\n\u{FFFC}\nSoup"   // photo at offset 5, its line 5..<6

    @Test func typingAfterAPhotoGoesOnANewLineBelow() {
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 6, length: 0), replacement: "h")
                == .replace("\nh", caret: 8))
    }

    @Test func typingBeforeAPhotoGoesOnANewLineAbove() {
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 5, length: 0), replacement: "h")
                == .replace("h\n", caret: 6))
    }

    @Test func backspaceThatWouldJoinAPhotosLineMovesTheCaret() {
        // At the start of "Soup": the break after the photo.
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 6, length: 1), replacement: "") == .moveCaret(6))
        // At the start of the photo's line: the break after "Lake".
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 4, length: 1), replacement: "") == .moveCaret(4))
    }

    @Test func aPhotoCannotBeDeletedOrTypedOverInTheText() {
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 5, length: 1), replacement: "") == .refuse)
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 2, length: 6), replacement: "x") == .refuse)
    }

    @Test func ordinaryEditsAreLeftAlone() {
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 2, length: 0), replacement: "k") == .asIs)
        // Return at the end of the photo's line, and deleting a whole line above it.
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 6, length: 0), replacement: "\n") == .asIs)
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 0, length: 5), replacement: "") == .asIs)
        #expect(NoteEditorCodec.photoLineEdit(display: "no photos", range: NSRange(location: 0, length: 2), replacement: "x") == .asIs)
    }

    @Test func aSelectionEndingAtAPhotoKeepsItsBreak() {
        // "La|ke\n" deleted: the photo would join "La".
        #expect(NoteEditorCodec.photoLineEdit(display: doc, range: NSRange(location: 2, length: 3), replacement: "")
                == .replace("\n", caret: 2))
    }

    // MARK: Removing a photo (`removingPhoto`)

    @Test func removingAPhotoBetweenLinesRenumbersTheOthersAndMovesStyles() {
        let text = "Lake\n[[mirror-photo-0]]\nSoup\n[[mirror-photo-1]]"
        // Bold on "Soup" (inline offset 7..<11) and a size on photo 1 (offset 12).
        var bold = InlineStyleRange(location: 7, length: 4, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        bold.linkURL = nil
        var sized = InlineStyleRange(location: 12, length: 1, bold: false, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        sized.photoSize = "small"
        let inline = try? JSONEncoder().encode(InlineStyleDocument(ranges: [bold, sized]))
        let styles = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.heading, .body, .checklistUnchecked, .body]))
        let result = NoteEditorCodec.removingPhoto(number: 0, text: text, textStyleData: styles, inlineStyleData: inline)
        #expect(result?.text == "Lake\nSoup\n[[mirror-photo-0]]")
        let models = NoteEditorCodec.storedParagraphs(from: result?.textStyleData, entryFont: .system).map(\.style)
        #expect(Array(models.prefix(3)) == [.heading, .checklistUnchecked, .body])
        var boldAfter = bold; boldAfter.location = 5
        var sizedAfter = sized; sizedAfter.location = 10
        #expect(ranges(result?.inlineStyleData) == [boldAfter, sizedAfter])
    }

    @Test func removingTheLastTrailingPhotoKeepsTheOthersNumbers() {
        let text = "Words\n[[mirror-photo-2]]\n[[mirror-photo-0]]\n[[mirror-photo-1]]"
        #expect(NoteEditorCodec.removingPhoto(number: 1, text: text, textStyleData: nil, inlineStyleData: nil)?.text
                == "Words\n[[mirror-photo-1]]\n[[mirror-photo-0]]")
        #expect(NoteEditorCodec.removingPhoto(number: 5, text: text, textStyleData: nil, inlineStyleData: nil) == nil)
    }

    // MARK: Write's body binding on Mac

    @Test func emptyingTheLineUnderAPhotoKeepsItInTheBody() {
        let start = "words\n[[mirror-photo-0]]\nmore"
        #expect(NoteEditorCodec.editorBody(of: start, lastSet: nil) == start)
        // The editor empties "more": the photo now looks trailing in the stored text...
        let emptied = NoteEditorCodec.text(settingEditorBody: "words\n[[mirror-photo-0]]\n", in: start, photoCount: 1)
        #expect(emptied == "words\n[[mirror-photo-0]]\n")
        // ...but the editor keeps seeing the body it set, and typing goes under the photo, once.
        let last = (emptied, "words\n[[mirror-photo-0]]\n")
        #expect(NoteEditorCodec.editorBody(of: emptied, lastSet: last) == last.1)
        let typed = NoteEditorCodec.text(settingEditorBody: "words\n[[mirror-photo-0]]\nnew", in: emptied, photoCount: 1)
        #expect(typed == "words\n[[mirror-photo-0]]\nnew")
        // An outside change (a photo attached) shows the split again.
        #expect(NoteEditorCodec.editorBody(of: "x\n[[mirror-photo-0]]", lastSet: last) == "x")
    }

    @Test func settingTheBodyKeepsTrailingNumbersAndAddsMissingPhotos() {
        let text = "a\n[[mirror-photo-1]]\nb\n[[mirror-photo-2]]\n[[mirror-photo-0]]"
        #expect(NoteEditorCodec.text(settingEditorBody: "a\n[[mirror-photo-1]]\nbc", in: text, photoCount: 3)
                == "a\n[[mirror-photo-1]]\nbc\n[[mirror-photo-2]]\n[[mirror-photo-0]]\n")
        // A photo with no token anywhere gets one at the end.
        #expect(NoteEditorCodec.text(settingEditorBody: "plain", in: "plain", photoCount: 1) == "plain\n[[mirror-photo-0]]\n")
    }

    @Test func textWithoutPhotosIsUntouched() {
        let text = "Plain words\nand a second line\n"
        #expect(NoteEditorCodec.editorDisplay(text).string == text)
        #expect(roundTrip(text).text == text)
        #expect(NoteEditorCodec.trailingPhotoNumbers(text).isEmpty)
        #expect(NoteEditorCodec.replacingBody(of: text, with: "new") == "new")
    }
}
