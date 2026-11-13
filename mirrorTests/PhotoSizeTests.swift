import Foundation
import Testing
@testable import mirror

/// Photo sizes (3.1.9): stored on the photo's one inline character. Synthetic text only.
@Suite("Photo size")
struct PhotoSizeTests {
    private func doc(_ data: Data?) -> [InlineStyleRange] {
        data.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0).ranges } ?? []
    }

    @Test func inlineOffsetsCountEachPhotoAsOneCharacter() {
        let text = "Market\n[[mirror-photo-0]]\nBread\n[[mirror-photo-1]]"
        let offsets = PhotoSizes.inlineOffsets(in: text)
        #expect(offsets.map(\.photoIndex) == [0, 1])
        #expect(offsets.map(\.offset) == [7, 15])   // "Market\n" = 7; "+1 photo +\nBread\n" = 7+1+7
    }

    @Test func settingAndReadingSizes() {
        let text = "Market\n[[mirror-photo-0]]\nBread\n[[mirror-photo-1]]"
        var data = PhotoSizes.setting(.small, atInlineOffset: 7, in: nil)
        data = PhotoSizes.setting(.medium, atInlineOffset: 15, in: data)
        #expect(PhotoSizes.sizes(text: text, inlineStyleData: data) == [0: .small, 1: .medium])
        // Back to full stores nothing for that photo.
        data = PhotoSizes.setting(.full, atInlineOffset: 7, in: data)
        #expect(PhotoSizes.sizes(text: text, inlineStyleData: data) == [1: .medium])
        data = PhotoSizes.setting(.full, atInlineOffset: 15, in: data)
        #expect(data == nil)
    }

    @Test func aLinkOnThePhotoIsKept() {
        let link = InlineStyleRange(location: 0, length: 1, bold: false, italic: false, underline: false, strikethrough: false,
                                    highlightIndex: nil, linkURL: "https://maps.apple.com/?q=x")
        let start = try! JSONEncoder().encode(InlineStyleDocument(ranges: [link]))
        let sized = PhotoSizes.setting(.small, atInlineOffset: 0, in: start)
        #expect(doc(sized).contains { $0.linkURL != nil })
        #expect(PhotoSizes.sizes(text: "[[mirror-photo-0]]", inlineStyleData: sized) == [0: .small])
        let back = PhotoSizes.setting(.full, atInlineOffset: 0, in: sized)
        #expect(doc(back) == [link])
    }

    @Test func oldDocumentsDecodeAndNewOnesStayReadable() throws {
        // A 3.1.8 document (no photoSize key) decodes; a 3.1.9 one decodes in a struct without the key too.
        let old = #"{"ranges":[{"location":0,"length":3,"bold":true,"italic":false,"underline":false,"strikethrough":false}]}"#
        #expect(doc(Data(old.utf8)).first?.photoSize == nil)
        struct OldRange: Decodable { var location: Int; var length: Int; var bold: Bool }
        struct OldDoc: Decodable { var ranges: [OldRange] }
        let new = try #require(PhotoSizes.setting(.medium, atInlineOffset: 4, in: Data(old.utf8)))
        #expect(try JSONDecoder().decode(OldDoc.self, from: new).ranges.count == 2)
    }

    @Test func macKeepsTrailingPhotoRangesAcrossBodyEdits() {
        let body = "Morning walk"
        let text = NoteEditorCodec.appendingPhotoTokens(to: body, count: 2)
        let offsets = PhotoSizes.inlineOffsets(in: text).map(\.offset)
        let sized = PhotoSizes.setting(.small, atInlineOffset: offsets[1], in: nil)
        let kept = NoteEditorCodec.trailingPhotoRanges(in: sized, bodyLength: (body as NSString).length)
        #expect(kept.count == 1)
        // The body grows on Mac; the size follows the second photo.
        let newBody = "Morning walk by the river"
        let merged = NoteEditorCodec.addingTrailingPhotoRanges(kept, to: nil, bodyLength: (newBody as NSString).length)
        let newText = NoteEditorCodec.appendingPhotoTokens(to: newBody, count: 2)
        #expect(PhotoSizes.sizes(text: newText, inlineStyleData: merged) == [1: .small])
    }

    @Test func macKeepsTheSizeWhenTheBodyStartsOrEndsEmpty() {
        // A photo attached to an empty entry sits at offset 0; typing a first letter moves it to 2.
        let empty = NoteEditorCodec.appendingPhotoTokens(to: "", count: 1)
        let sized = PhotoSizes.setting(.small, atInlineOffset: PhotoSizes.inlineOffsets(in: empty)[0].offset, in: nil)
        let kept = NoteEditorCodec.trailingPhotoRanges(in: sized, bodyLength: 0)
        let typed = NoteEditorCodec.addingTrailingPhotoRanges(kept, to: nil, bodyLength: 1)
        #expect(PhotoSizes.sizes(text: NoteEditorCodec.appendingPhotoTokens(to: "A", count: 1), inlineStyleData: typed) == [0: .small])
        // And back: the body emptied again.
        let keptAgain = NoteEditorCodec.trailingPhotoRanges(in: typed, bodyLength: 1)
        let cleared = NoteEditorCodec.addingTrailingPhotoRanges(keptAgain, to: nil, bodyLength: 0)
        #expect(PhotoSizes.sizes(text: empty, inlineStyleData: cleared) == [0: .small])
        // Two photos under an empty body: the second keeps its own size.
        let two = NoteEditorCodec.appendingPhotoTokens(to: "", count: 2)
        let second = PhotoSizes.setting(.medium, atInlineOffset: PhotoSizes.inlineOffsets(in: two)[1].offset, in: nil)
        let moved = NoteEditorCodec.addingTrailingPhotoRanges(NoteEditorCodec.trailingPhotoRanges(in: second, bodyLength: 0), to: nil, bodyLength: 4)
        #expect(PhotoSizes.sizes(text: NoteEditorCodec.appendingPhotoTokens(to: "Walk", count: 2), inlineStyleData: moved) == [1: .medium])
    }

    @Test func theSizeMovesWithItsRowAndWithEdits() {
        // Rows: "Milk", photo, "Eggs" (inline coordinates: the photo is one character).
        let inlineText = "Milk\n\u{FFFC}\nEggs"
        let sized = PhotoSizes.setting(.small, atInlineOffset: 5, in: nil)
        // Reorder: the photo row goes first (as sorting or deleting checked items moves rows).
        let reordered = NoteEditorCodec.remapInlineStyles(sized, in: inlineText, rowOrder: [1, 0, 2])
        #expect(doc(reordered) .map(\.location) == [0])
        #expect(doc(reordered).first?.photoSize == "small")
        // Typing three characters before the photo shifts it.
        let typed = NoteEditorCodec.adjustInlineStyles(sized, replacing: NSRange(location: 0, length: 0), withLength: 3)
        #expect(doc(typed).first?.location == 8)
        #expect(doc(typed).first?.photoSize == "small")
        // Deleting the photo's character drops its size.
        #expect(NoteEditorCodec.adjustInlineStyles(sized, replacing: NSRange(location: 5, length: 1), withLength: 0) == nil)
    }

    @Test func aSizedTrailingPhotoStaysEditableOnMac() {
        let body = "Morning walk"
        let text = NoteEditorCodec.appendingPhotoTokens(to: body, count: 1)
        let offset = PhotoSizes.inlineOffsets(in: text)[0].offset
        let sized = PhotoSizes.setting(.medium, atInlineOffset: offset, in: nil)
        #expect(NoteEditorCodec.canEditOnMac(text: text, textStyleData: nil, inlineStyleData: sized, entryFont: .system, photoCount: 1))
    }

    @Test func removingAPhotoMovesTheOthersSizes() {
        let body = "Trip"
        let old = NoteEditorCodec.appendingPhotoTokens(to: body, count: 3)
        let offsets = PhotoSizes.inlineOffsets(in: old).map(\.offset)
        var data = PhotoSizes.setting(.small, atInlineOffset: offsets[0], in: nil)
        data = PhotoSizes.setting(.medium, atInlineOffset: offsets[2], in: data)
        let new = NoteEditorCodec.appendingPhotoTokens(to: body, count: 2)
        let after = PhotoSizes.removingPhoto(at: 1, oldText: old, newText: new, in: data)
        #expect(PhotoSizes.sizes(text: new, inlineStyleData: after) == [0: .small, 1: .medium])
        let afterFirst = PhotoSizes.removingPhoto(at: 0, oldText: old, newText: new, in: data)
        #expect(PhotoSizes.sizes(text: new, inlineStyleData: afterFirst) == [1: .medium])
    }
}
