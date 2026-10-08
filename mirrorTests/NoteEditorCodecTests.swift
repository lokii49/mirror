import Testing
import SwiftUI
import UIKit
@testable import mirror

/// The Mac editor reads and writes the same stored documents as the iOS editor. These tests pin
/// `NoteEditorCodec` (what the Mac editor uses) to the iOS coordinator's own output, so an entry
/// edited on Mac cannot drift on iPhone or iPad. The codec is platform-neutral, so it is checked
/// here on the simulator against the real iOS editor.
struct NoteEditorCodecTests {

    // MARK: - Fixtures

    private struct Fixture {
        var name: String
        var text: String
        var paragraphs: [NoteEditorCodec.ParagraphModel]
        var inline: [InlineStyleRange] = []
        var entryFont: WritingFontChoice = .system
    }

    private func p(_ style: NoteParagraphTextStyle, indent: Int = 0, font: WritingFontChoice? = nil) -> NoteEditorCodec.ParagraphModel {
        NoteEditorCodec.ParagraphModel(style: style, indent: indent, fontChoice: font)
    }

    private func range(_ location: Int, _ length: Int, bold: Bool = false, italic: Bool = false, underline: Bool = false,
                       strike: Bool = false, highlight: Int? = nil, color: Int? = nil, link: String? = nil) -> InlineStyleRange {
        InlineStyleRange(location: location, length: length, bold: bold, italic: italic, underline: underline,
                         strikethrough: strike, highlightIndex: highlight, linkURL: link, textColorIndex: color)
    }

    private var fixtures: [Fixture] {
        [
            Fixture(
                name: "mixed styles with inline ranges",
                text: "Trip notes\nWe left early and it rained\nPack umbrella\nCharger\nBook hotel\nCall mum\nFirst step\nSecond step\nA nested step\nBack to outer\nDone",
                paragraphs: [p(.title), .init(), p(.bulletedList), p(.bulletedList), p(.checklistUnchecked), p(.checklistChecked),
                             p(.numberedList), p(.numberedList), p(.numberedList, indent: 1), p(.numberedList), .init()],
                inline: [range(11, 2, bold: true), range(14, 5, italic: true, underline: true), range(37, 8, highlight: 1),
                         range(46, 7, color: 2, link: "https://example.com")]
            ),
            Fixture(
                name: "headings quote and monospace",
                text: "Heading\nSub\nA quote\ncode line\nplain",
                paragraphs: [p(.heading), p(.subheading), p(.blockQuote), p(.monospaced), p(.body)],
                inline: [range(0, 7, underline: true), range(8, 3, strike: true)]
            ),
            Fixture(
                name: "empty last list item",
                text: "item one\n",
                paragraphs: [p(.bulletedList), p(.bulletedList)]
            ),
            Fixture(
                name: "empty last checklist item after two",
                text: "a\nb\n",
                paragraphs: [p(.checklistUnchecked), p(.checklistChecked), p(.checklistUnchecked)]
            ),
            Fixture(
                name: "blank paragraphs in the middle",
                text: "one\n\n\ntwo",
                paragraphs: [p(.heading), .init(), p(.bulletedList), .init()]
            ),
            Fixture(
                name: "per-paragraph fonts",
                text: "serif para\nrounded para\ndefault para",
                paragraphs: [p(.body, font: .serif), p(.body, font: .rounded), p(.body)],
                entryFont: .system
            ),
            Fixture(
                name: "inline only",
                text: "just some words here",
                paragraphs: [],
                inline: [range(5, 4, bold: true, italic: true)]
            ),
            Fixture(
                name: "inline spanning paragraphs",
                text: "first line\nsecond line",
                paragraphs: [p(.bulletedList), p(.bulletedList)],
                inline: [range(6, 10, underline: true)]
            ),
        ]
    }

    // MARK: - Helpers

    private func styleData(_ fixture: Fixture) -> Data? {
        guard !fixture.paragraphs.isEmpty else { return nil }
        let hasIndent = fixture.paragraphs.contains { $0.indent > 0 }
        return try? JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: fixture.paragraphs.map(\.style),
            indentLevels: hasIndent ? fixture.paragraphs.map(\.indent) : nil,
            fontChoices: fixture.paragraphs.map { ($0.fontChoice ?? fixture.entryFont).rawValue }
        ))
    }

    private func inlineData(_ fixture: Fixture) -> Data? {
        fixture.inline.isEmpty ? nil : try? JSONEncoder().encode(InlineStyleDocument(ranges: fixture.inline))
    }

    private final class Box {
        var text: String
        var textStyleData: Data?
        var inlineStyleData: Data?
        init(text: String, textStyleData: Data?, inlineStyleData: Data?) {
            self.text = text; self.textStyleData = textStyleData; self.inlineStyleData = inlineStyleData
        }
    }

    /// Loads the fixture into the real iOS editor and reads back what it would save.
    @MainActor
    private func iosRoundTrip(_ fixture: Fixture) -> (text: String, style: Data?, inline: Data?) {
        let box = Box(text: fixture.text, textStyleData: styleData(fixture), inlineStyleData: inlineData(fixture))
        let view = NoteEditorTextView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            textStyleData: Binding(get: { box.textStyleData }, set: { box.textStyleData = $0 }),
            inlineStyleData: Binding(get: { box.inlineStyleData }, set: { box.inlineStyleData = $0 }),
            photoDataArray: .constant([]),
            command: .constant(nil),
            commandRevision: .constant(0),
            isFocused: .constant(false),
            activeParagraphStyle: .constant(.body),
            activeInlineStyles: .constant(InlineStyleSet()),
            showFormattingPanel: .constant(false),
            canUndo: .constant(false),
            canRedo: .constant(false),
            fontChoiceRaw: .constant(fixture.entryFont.rawValue),
            panelState: FormattingPanelState(),
            displayMode: .classic,
            onPhotoTapped: nil
        )
        let coordinator = NoteEditorTextView.Coordinator(parent: view)
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        coordinator.applyStyledText(to: textView, preservingSelection: false)
        coordinator.textViewDidChange(textView)
        return (box.text, box.textStyleData, box.inlineStyleData)
    }

    private func codecRoundTrip(_ fixture: Fixture) -> (style: Data?, inline: Data?) {
        let rendered = NoteEditorCodec.render(text: fixture.text, textStyleData: styleData(fixture),
                                              inlineStyleData: inlineData(fixture), entryFont: fixture.entryFont)
        return (
            NoteEditorCodec.extractTextStyleData(from: rendered.attributed, trailing: rendered.trailing, entryFont: fixture.entryFont),
            NoteEditorCodec.extractInlineStyleData(from: rendered.attributed)
        )
    }

    private func decodedStyle(_ data: Data?) -> NoteTextStyleDocument? { NoteEditorCodec.decodeTextStyleDocument(data) }
    private func decodedInline(_ data: Data?) -> [InlineStyleRange]? { NoteEditorCodec.decodeInlineStyleDocument(data)?.ranges }

    // MARK: - Tests

    @Test @MainActor func codecMatchesTheIOSEditorOnEveryFixture() {
        for fixture in fixtures {
            let ios = iosRoundTrip(fixture)
            let codec = codecRoundTrip(fixture)

            #expect(ios.text == fixture.text, "iOS changed the text for: \(fixture.name)")

            let iosStyle = decodedStyle(ios.style)
            let codecStyle = decodedStyle(codec.style)
            #expect(iosStyle?.paragraphStyles == codecStyle?.paragraphStyles, "paragraph styles differ for: \(fixture.name)")
            #expect((iosStyle?.indentLevels ?? []) == (codecStyle?.indentLevels ?? []), "indent levels differ for: \(fixture.name)")
            #expect(iosStyle?.fontChoices == codecStyle?.fontChoices, "font choices differ for: \(fixture.name)")
            // Includes a subheading: neither editor stores the subheading font's own bold.
            #expect(decodedInline(ios.inline) == decodedInline(codec.inline), "inline ranges differ for: \(fixture.name)")
        }
    }

    @Test func codecRoundTripLeavesStoredDocumentsUnchanged() {
        for fixture in fixtures {
            #expect(
                NoteEditorCodec.canEditOnMac(text: fixture.text, textStyleData: styleData(fixture),
                                             inlineStyleData: inlineData(fixture), entryFont: fixture.entryFont, photoCount: 0),
                "round trip changed: \(fixture.name)"
            )
        }
    }

    @Test func photosAtTheEndAreEditableAndOtherPhotoCasesAreNot() {
        // What attaching photos produces: tokens at the end.
        let two = "Some words\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n"
        #expect(NoteEditorCodec.canEditOnMac(text: two, textStyleData: nil, inlineStyleData: nil, entryFont: .system, photoCount: 2))
        #expect(NoteEditorCodec.canEditOnMac(text: "[[mirror-photo-0]]", textStyleData: nil, inlineStyleData: nil, entryFont: .system, photoCount: 1))
        // A photo in the middle of the text: iOS placed it inline, the Mac editor cannot.
        #expect(!NoteEditorCodec.canEditOnMac(text: "a\n[[mirror-photo-0]]\nb", textStyleData: nil, inlineStyleData: nil, entryFont: .system, photoCount: 1))
        // Photos stored without a matching token, or tokens without photos.
        #expect(!NoteEditorCodec.canEditOnMac(text: "plain", textStyleData: nil, inlineStyleData: nil, entryFont: .system, photoCount: 1))
        #expect(!NoteEditorCodec.canEditOnMac(text: "a\n[[mirror-photo-0]]\n", textStyleData: nil, inlineStyleData: nil, entryFont: .system, photoCount: 0))
    }

    @Test func trailingPhotoTokensSplitAndRebuild() {
        for text in ["Some words\n[[mirror-photo-0]]\n", "Some words\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n", "[[mirror-photo-0]]", "no photos here"] {
            let (body, count) = NoteEditorCodec.splitTrailingPhotoTokens(text)
            #expect(NoteEditorCodec.appendingPhotoTokens(to: body, count: count) == text, "round trip of \(text.debugDescription)")
            #expect(allPhotoTokens(in: body).isEmpty)
        }
        let (body, count) = NoteEditorCodec.splitTrailingPhotoTokens("Some words\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n")
        #expect(body == "Some words" && count == 2)
        // A newline typed at the end of the body survives the round trip.
        let typed = NoteEditorCodec.appendingPhotoTokens(to: "Some words\n", count: 1)
        #expect(NoteEditorCodec.splitTrailingPhotoTokens(typed).body == "Some words\n")
    }

    @Test func legacyPrefixesStayReadOnlyOnMac() {
        #expect(!NoteEditorCodec.canEditOnMac(text: "# Old heading\nbody", textStyleData: nil, inlineStyleData: nil,
                                              entryFont: .system, photoCount: 0))
        #expect(!NoteEditorCodec.canEditOnMac(text: "○ old todo", textStyleData: nil, inlineStyleData: nil,
                                              entryFont: .system, photoCount: 0))
        // With a style document the prefix is literal text typed by the user, not a marker.
        let doc = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.body, .heading], indentLevels: nil,
                                                                   fontChoices: ["system", "system"]))
        #expect(NoteEditorCodec.canEditOnMac(text: "# hash\ntitle", textStyleData: doc, inlineStyleData: nil,
                                             entryFont: .system, photoCount: 0))
    }

    @Test func plainEntriesProduceNoDocuments() {
        let rendered = NoteEditorCodec.render(text: "just words\nmore words", textStyleData: nil, inlineStyleData: nil, entryFont: .system)
        #expect(NoteEditorCodec.extractTextStyleData(from: rendered.attributed, trailing: rendered.trailing, entryFont: .system) == nil)
        #expect(NoteEditorCodec.extractInlineStyleData(from: rendered.attributed) == nil)
    }

    @Test func numberedListsRestartPerLevel() {
        let models: [NoteEditorCodec.ParagraphModel] = [
            p(.numberedList), p(.numberedList), p(.numberedList, indent: 1), p(.numberedList, indent: 1),
            p(.numberedList), p(.body), p(.numberedList),
        ]
        #expect(NoteEditorCodec.numberedIndices(for: models) == [1, 2, 1, 2, 3, nil, 1])
    }

    @Test func boldOnTitleAndHeadingIsParagraphStyleNotInline() {
        let rendered = NoteEditorCodec.render(text: "Title\nbody", textStyleData: styleData(
            Fixture(name: "t", text: "Title\nbody", paragraphs: [p(.title), .init()])), inlineStyleData: nil, entryFont: .system)
        rendered.attributed.addAttribute(NoteEditorCodec.boldKey, value: true, range: NSRange(location: 0, length: 5))
        rendered.attributed.addAttribute(NoteEditorCodec.boldKey, value: true, range: NSRange(location: 6, length: 4))
        let ranges = decodedInline(NoteEditorCodec.extractInlineStyleData(from: rendered.attributed))
        #expect(ranges?.count == 1)
        #expect(ranges?.first?.location == 6)
    }

    // MARK: - Remapping inline ranges when rows move (checklist Sort Done / Delete Done)

    private func remapped(_ ranges: [InlineStyleRange], _ text: String, _ order: [Int]) -> [InlineStyleRange]? {
        decodedInline(NoteEditorCodec.remapInlineStyles(try? JSONEncoder().encode(InlineStyleDocument(ranges: ranges)),
                                                        in: text, rowOrder: order))
    }

    @Test func remapDropsDeletedRowsAndShiftsTheRest() {
        // rows: "aa" "bbb" "cc"; delete row 0.
        #expect(remapped([range(3, 3, bold: true), range(7, 2, italic: true)], "aa\nbbb\ncc", [1, 2])
                == [range(0, 3, bold: true), range(4, 2, italic: true)])
    }

    @Test func remapMovesARangeWithItsRow() {
        #expect(remapped([range(0, 2, link: "https://example.com")], "aa\nbbb", [1, 0]) == [range(4, 2, link: "https://example.com")])
    }

    @Test func remapClipsARangeThatSpansAKeptAndADeletedRow() {
        // Bold over "a\nbbb" (0..<5); row 0 is deleted, so only "bbb" keeps it.
        #expect(remapped([range(0, 5, bold: true)], "a\nbbb", [1]) == [range(0, 3, bold: true)])
    }

    @Test func remapCountsUTF16NotCharacters() {
        // The emoji row is 2 UTF-16 units; deleting it moves "xy" from 3 to 0.
        #expect(remapped([range(3, 2, underline: true)], "\u{1F600}\nxy", [1]) == [range(0, 2, underline: true)])
        // Moving the emoji row below: "xy" goes to 0, a highlight on the emoji goes to 3.
        #expect(remapped([range(0, 2, highlight: 1)], "\u{1F600}\nxy", [1, 0]) == [range(3, 2, highlight: 1)])
    }

    @Test func remapOfNothingOrEverythingDeletedIsNil() {
        #expect(NoteEditorCodec.remapInlineStyles(nil, in: "a\nb", rowOrder: [1, 0]) == nil)
        #expect(remapped([range(0, 1, bold: true)], "a\nb", [1]) == nil)
    }

    // MARK: - Adjusting inline ranges for a text edit (photo removal)

    private func adjusted(_ ranges: [InlineStyleRange], _ location: Int, _ length: Int, _ newLength: Int) -> [InlineStyleRange]? {
        decodedInline(NoteEditorCodec.adjustInlineStyles(try? JSONEncoder().encode(InlineStyleDocument(ranges: ranges)),
                                                         replacing: NSRange(location: location, length: length), withLength: newLength))
    }

    @Test func adjustShiftsRangesAfterADeletion() {
        // "ab\n<photo>\nNotes" (a photo is one character in inline coordinates): deleting "\n" + photo
        // (2 units at 2) moves "Notes" from 5 to 3.
        #expect(adjusted([range(0, 2, bold: true), range(5, 5, italic: true)], 2, 2, 0)
                == [range(0, 2, bold: true), range(3, 5, italic: true)])
    }

    @Test func adjustClipsRangesThatOverlapTheEdit() {
        #expect(adjusted([range(0, 5, bold: true)], 3, 4, 0) == [range(0, 3, bold: true)])
        #expect(adjusted([range(4, 4, bold: true)], 2, 4, 0) == [range(2, 2, bold: true)])
        #expect(adjusted([range(3, 2, bold: true)], 2, 4, 0) == nil)
    }

    @Test func adjustFollowsAReplacementOfADifferentLength() {
        #expect(adjusted([range(30, 3, underline: true)], 5, 4, 3) == [range(29, 3, underline: true)])
    }

    @Test func clearingBoldKeepsOtherFormattingAndBoldOutside() {
        // Bold+underline over 0..<10; clear bold in 2..<5.
        #expect(decodedInline(NoteEditorCodec.clearingBold(try? JSONEncoder().encode(InlineStyleDocument(ranges: [range(0, 10, bold: true, underline: true)])),
                                                           in: NSRange(location: 2, length: 3)))
                == [range(0, 2, bold: true, underline: true), range(2, 3, underline: true), range(5, 5, bold: true, underline: true)])
        // Plain bold inside the cleared span disappears.
        #expect(NoteEditorCodec.clearingBold(try? JSONEncoder().encode(InlineStyleDocument(ranges: [range(0, 3, bold: true)])),
                                             in: NSRange(location: 0, length: 5)) == nil)
    }

    @Test func inlineRangesMoveToTextOffsetsAfterPhotos() {
        // Editor coordinates: "ab\n" + photo(1) + "\nNotes" + photo(1) + "\nend".
        let text = "ab\n[[mirror-photo-0]]\nNotes\n[[mirror-photo-1]]\nend"
        let ranges = [range(0, 2, bold: true), range(5, 5, italic: true), range(13, 3, underline: true)]
        #expect(NoteEditorCodec.inlineRangesInTextCoordinates(ranges, text: text)
                == [range(0, 2, bold: true), range(22, 5, italic: true), range(47, 3, underline: true)])
        // No photos: unchanged.
        #expect(NoteEditorCodec.inlineRangesInTextCoordinates(ranges, text: "plain") == ranges)
    }
}
