import Testing
import Foundation
@testable import mirror

/// Copy / Cut / Paste of a selection with photos (`PhotoFragment`, 2026-11-15). Synthetic text only.
struct PhotoFragmentTests {
    private let p0 = inlinePhotoToken(at: 0), p1 = inlinePhotoToken(at: 1), p2 = inlinePhotoToken(at: 2), p3 = inlinePhotoToken(at: 3)
    private let picture = Data([1, 2, 3])

    private func photo(size: String? = nil, link: String? = nil, tile: Bool = false) -> PhotoFragment.Line {
        PhotoFragment.Line(photo: picture, size: size, link: link, wasTile: tile)
    }

    private func insert(_ fragment: PhotoFragment, into text: String, after: Int?, styles: NoteTextStyleDocument? = nil,
                        inline: Data? = nil, photoCount: Int) -> (text: String, styles: [NoteParagraphTextStyle], inline: Data?) {
        let result = fragment.inserted(into: text, afterParagraph: after, textStyleData: styles.flatMap { try? JSONEncoder().encode($0) },
                                       inlineStyleData: inline, photoCount: photoCount, entryFont: "system",
                                       hasPicture: { _ in true }, isLandscape: { _ in false })
        let paragraphStyles = result.textStyleData.flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }?.paragraphStyles ?? []
        return (result.text, paragraphStyles, result.inlineStyleData)
    }

    private func sizes(_ text: String, _ inline: Data?) -> [Int: String] { PhotoSizes.storedSizes(text: text, inlineStyleData: inline) }

    private func tiles(_ text: String, _ inline: Data?) -> [Bool] {
        PhotoPlacement.placements(text: text, inlineStyleData: inline, hasPicture: { _ in true }, isLandscape: { _ in false }).map(\.isTile)
    }

    @Test func linesAndPhotosGoInInOrderWithNewNumbers() {
        let fragment = PhotoFragment(lines: [.init(text: "Walk"), photo(), photo(), .init(text: "Home")])
        // Mid-entry, after the caret's line.
        let mid = insert(fragment, into: "Day\n\(p0)\nEnd", after: 0, photoCount: 1)
        #expect(mid.text == "Day\nWalk\n\(p1)\n\(p2)\nHome\n\(p0)\nEnd")
        // At the end.
        let end = insert(fragment, into: "Day\n\(p0)", after: nil, photoCount: 1)
        #expect(end.text == "Day\n\(p0)\nWalk\n\(p1)\n\(p2)\nHome")
        // On an empty line: it takes the line's place.
        let blank = insert(fragment, into: "Day\n\nEnd", after: 1, photoCount: 0)
        #expect(blank.text == "Day\nWalk\n\(p0)\n\(p1)\nHome\nEnd")
        // An empty entry.
        #expect(insert(fragment, into: "", after: nil, photoCount: 0).text == "Walk\n\(p0)\n\(p1)\nHome")
    }

    @Test func sizesLinksAndLooksTravel() throws {
        let fragment = PhotoFragment(lines: [photo(size: "small"), .init(text: "Between"), photo(link: "https://maps.apple.com/?q=river"), photo(tile: true)])
        let result = insert(fragment, into: "Day", after: 0, photoCount: 0)
        #expect(result.text == "Day\n\(p0)\nBetween\n\(p1)\n\(p2)")
        // The first keeps its size; the last two make a row, so the tile needs nothing stored.
        #expect(sizes(result.text, result.inline) == [0: "small"])
        #expect(tiles(result.text, result.inline) == [false, true, true])
        let ranges = try #require(result.inline.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges)
        #expect(ranges.contains { $0.linkURL == "https://maps.apple.com/?q=river" && $0.location == 14 && $0.length == 1 })
        // A tile pasted alone keeps its look: it stores "thumbnail".
        let alone = insert(PhotoFragment(lines: [photo(tile: true)]), into: "Day", after: 0, photoCount: 0)
        #expect(sizes(alone.text, alone.inline) == [0: PhotoSizes.thumbnail])
        // A full-width photo pasted alone stores nothing.
        let full = insert(PhotoFragment(lines: [photo()]), into: "Day", after: 0, photoCount: 0)
        #expect(full.inline == nil)
    }

    @Test func theEntrysOwnPhotosAndFormattingStayPut() throws {
        // A row of two; the block goes between them (the caret on the first): both were tiles and stay tiles.
        let fragment = PhotoFragment(lines: [.init(text: "Words")])
        let split = insert(fragment, into: "\(p0)\n\(p1)", after: 0, photoCount: 2)
        #expect(split.text == "\(p0)\nWords\n\(p1)")
        #expect(sizes(split.text, split.inline) == [0: PhotoSizes.thumbnail, 1: PhotoSizes.thumbnail])
        // Bold on "Day" and on "End", a size on the photo under the block: each stays on its own.
        let bold = { (location: Int, length: Int) in
            InlineStyleRange(location: location, length: length, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        }
        var inline = try JSONEncoder().encode(InlineStyleDocument(ranges: [bold(0, 3), bold(6, 3)]))   // Day \n P0 \n End
        inline = try #require(PhotoSizes.setting(stored: "medium", atInlineOffset: 4, in: inline))
        let styled = insert(PhotoFragment(lines: [photo(), .init(text: "Mid")]), into: "Day\n\(p0)\nEnd", after: 0, inline: inline, photoCount: 1)
        #expect(styled.text == "Day\n\(p1)\nMid\n\(p0)\nEnd")
        #expect(sizes(styled.text, styled.inline) == [0: "medium"])
        let ranges = try #require(styled.inline.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges)
        #expect(ranges.filter(\.bold).map { [$0.location, $0.length] }.sorted { $0[0] < $1[0] } == [[0, 3], [12, 3]])
    }

    @Test func paragraphStylesStayOnTheirLines() {
        let styles = NoteTextStyleDocument(paragraphStyles: [.heading, .checklistUnchecked, .body], indentLevels: nil, fontChoices: nil)
        let result = insert(PhotoFragment(lines: [photo(), .init(text: "Note")]), into: "Title\nTask\nEnd", after: 0, styles: styles, photoCount: 0)
        #expect(result.text == "Title\n\(p0)\nNote\nTask\nEnd")
        #expect(result.styles == [.heading, .body, .body, .checklistUnchecked, .body])
    }

    @Test func theClipboardFormatIsCheckedOnTheWayIn() throws {
        let fragment = PhotoFragment(lines: [.init(text: "Walk"), photo(size: "small", tile: false)])
        let data = try #require(fragment.encoded())
        #expect(PhotoFragment.decoded(data) == fragment)
        #expect(fragment.plainText == "Walk")
        #expect(PhotoFragment.decoded(Data("not a fragment".utf8)) == nil)
        let tooMany = PhotoFragment(lines: Array(repeating: photo(), count: PhotoFragment.maxPhotos + 1))
        #expect(PhotoFragment.decoded(try #require(tooMany.encoded())) == nil)
        // An unknown size is ignored, not stored.
        let odd = insert(PhotoFragment(lines: [photo(size: "huge")]), into: "Day", after: 0, photoCount: 0)
        #expect(odd.inline == nil)
        // A line of words can't smuggle a line break or a token of its own numbering in.
        let sneaky = insert(PhotoFragment(lines: [.init(text: "a\nb")]), into: "Day", after: 0, photoCount: 0)
        #expect(sneaky.text == "Day\na b")
    }
}
