import Foundation
import Testing
@testable import mirror

/// Which photos the editor and reader draw as square tiles (Suggestions option A, 2026-11-07).
/// The stored text keeps one token per line; this is display only.
@Suite("Photo runs")
struct PhotoRunsTests {
    /// Token positions (text order) drawn as tiles, by the shared rule (`PhotoPlacement`).
    private func tiles(_ text: String, landscape: Set<Int> = []) -> Set<Int> {
        let placements = PhotoPlacement.placements(text: text, inlineStyleData: nil, hasPicture: { _ in true },
                                                   isLandscape: { landscape.contains($0) })
        return Set(placements.indices.filter { placements[$0].isTile })
    }

    @Test func aMapLeadsAndTheRestAreTiles() {
        let text = "Dinner\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n[[mirror-photo-2]]\n"
        #expect(tiles(text, landscape: [0]) == [1, 2])
    }

    @Test func squareArtworkIsAllTiles() {
        let text = "Songs\n🎵 A · B\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n[[mirror-photo-2]]\n"
        #expect(tiles(text) == [0, 1, 2])
    }

    @Test func aSinglePhotoIsNeverATile() {
        #expect(tiles("Walk\n[[mirror-photo-0]]\nThen tea.") .isEmpty)
        #expect(tiles("[[mirror-photo-0]]\ntext\n[[mirror-photo-1]]").isEmpty, "text between photos breaks the run")
    }

    @Test func aPhotoSharingItsLineWithTextStaysFullWidth() {
        #expect(tiles("look [[mirror-photo-0]]\n[[mirror-photo-1]]").isEmpty)
    }

    /// Spaces around a token don't break a row: the reader trims them, so the editor must too.
    @Test func spacesAroundTokensKeepTheRow() {
        #expect(tiles("[[mirror-photo-0]] \n[[mirror-photo-1]]") == [0, 1])
        #expect(tiles("[[mirror-photo-0]]\n  [[mirror-photo-1]]\t\n[[mirror-photo-2]]") == [0, 1, 2])
        #expect(tiles("[[mirror-photo-0]]\n \n[[mirror-photo-1]]").isEmpty, "a blank line still breaks it")
        #expect(tiles("[[mirror-photo-0]] x\n[[mirror-photo-1]]").isEmpty)
    }
}

/// Entries row titles (Paper & Ink option D, 2026-11-07).
@Suite("Entry row title")
struct EntryRowTextTests {
    @Test func aShortFirstLineWithMoreBecomesTheTitle() {
        let split = EntryRowText.split(["Dinner by the river", "📍 Blue Door Café, Lisbon", "👥 With Maya and Tom"])
        #expect(split.title == "Dinner by the river")
        #expect(split.body == "📍 Blue Door Café, Lisbon 👥 With Maya and Tom")
    }

    @Test func aSentenceIsNotATitleUnlessTheWriterStyledIt() {
        #expect(EntryRowText.split(["Rough day.", "Then it got better."]).title == nil)
        #expect(EntryRowText.split(["今日は長かった。", "でも良かった。"]).title == nil)
        #expect(EntryRowText.split(["Rough day.", "Then it got better."], firstIsStyledTitle: true).title == "Rough day.")
        #expect(EntryRowText.split(["Weekend plan", "Groceries, call mom"]).title == "Weekend plan")
    }

    @Test func oneParagraphOrALongFirstLineHasNoTitle() {
        #expect(EntryRowText.split(["Took the long way home on purpose."]).title == nil)
        let long = String(repeating: "word ", count: 14)
        #expect(EntryRowText.split([long, "more"]).title == nil)
        #expect(EntryRowText.split([]).body.isEmpty)
    }

    /// The stored style is read for the first paragraph with words, not paragraph 0 (code review).
    @Test func theStyleComesFromTheFirstWrittenParagraph() throws {
        let text = "\n[[mirror-photo-0]]\nRough day.\nThen it got better."
        let lines = ["Rough day.", "Then it got better."]
        func data(_ styles: [NoteParagraphTextStyle]) throws -> Data {
            try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles, indentLevels: nil, fontChoices: nil))
        }
        #expect(EntryRowText.firstWordsParagraph(in: text) == 2)
        let headingThere = try data([.body, .body, .heading, .body])
        #expect(EntryRowText.split(lines, text: text, styleData: { headingThere }).title == "Rough day.")
        // An empty Heading line before it doesn't make the next paragraph a title.
        let emptyHeading = try data([.heading, .body, .body, .body])
        #expect(EntryRowText.split(lines, text: text, styleData: { emptyHeading }).title == nil)
        #expect(EntryRowText.split(lines, text: text, styleData: { nil }).title == nil)
        // A short line that already reads as a title never needs the stored style.
        #expect(EntryRowText.split(["Weekend plan", "Groceries"], text: "Weekend plan\nGroceries", styleData: {
            Issue.record("style read when it couldn't change the answer"); return nil
        }).title == "Weekend plan")
    }
}
