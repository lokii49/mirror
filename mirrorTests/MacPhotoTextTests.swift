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

    @Test func textWithoutPhotosIsUntouched() {
        let text = "Plain words\nand a second line\n"
        #expect(NoteEditorCodec.editorDisplay(text).string == text)
        #expect(roundTrip(text).text == text)
        #expect(NoteEditorCodec.trailingPhotoNumbers(text).isEmpty)
        #expect(NoteEditorCodec.replacingBody(of: text, with: "new") == "new")
    }
}
