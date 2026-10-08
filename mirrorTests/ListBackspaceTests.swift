import Testing
import SwiftUI
import UIKit
@testable import mirror

// Backspace at the start of a list item, checklist bulk ops, and inline ranges after list edits.
// Synthetic text only.

@MainActor
private func makeListHarness(
    text: String = "",
    textStyleData: Data? = nil,
    inlineStyleData: Data? = nil,
    photos: [Data] = [],
    fontChoiceRaw: String = WritingFontChoice.system.rawValue
) -> (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, getText: () -> String, getStyleData: () -> Data?, getInlineData: () -> Data?) {
    var text = text
    var textStyleData = textStyleData
    var inlineStyleData = inlineStyleData
    var photos = photos
    var command: NoteTextCommand?
    var commandRevision = 0
    var isFocused = false
    var activeParagraphStyle: NoteParagraphTextStyle = .body
    var activeInlineStyles = InlineStyleSet()
    var showFormattingPanel = false
    var canUndo = false
    var canRedo = false
    var fontChoiceRawValue = fontChoiceRaw
    let panelState = FormattingPanelState()

    let editor = NoteEditorTextView(
        text: Binding(get: { text }, set: { text = $0 }),
        textStyleData: Binding(get: { textStyleData }, set: { textStyleData = $0 }),
        inlineStyleData: Binding(get: { inlineStyleData }, set: { inlineStyleData = $0 }),
        photoDataArray: Binding(get: { photos }, set: { photos = $0 }),
        command: Binding(get: { command }, set: { command = $0 }),
        commandRevision: Binding(get: { commandRevision }, set: { commandRevision = $0 }),
        isFocused: Binding(get: { isFocused }, set: { isFocused = $0 }),
        activeParagraphStyle: Binding(get: { activeParagraphStyle }, set: { activeParagraphStyle = $0 }),
        activeInlineStyles: Binding(get: { activeInlineStyles }, set: { activeInlineStyles = $0 }),
        showFormattingPanel: Binding(get: { showFormattingPanel }, set: { showFormattingPanel = $0 }),
        canUndo: Binding(get: { canUndo }, set: { canUndo = $0 }),
        canRedo: Binding(get: { canRedo }, set: { canRedo = $0 }),
        fontChoiceRaw: Binding(get: { fontChoiceRawValue }, set: { fontChoiceRawValue = $0 }),
        panelState: panelState,
        displayMode: .classic
    )
    let coordinator = editor.makeCoordinator()
    let textView = UITextView()
    coordinator.applyStyledText(to: textView, preservingSelection: false)
    return (coordinator, textView, { text }, { textStyleData }, { inlineStyleData })
}

private func listStyle(_ styles: [NoteParagraphTextStyle]) -> Data {
    try! JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles))
}

@MainActor
struct ListBackspaceAtMarkerTests {
    private let markers: [(NoteParagraphTextStyle, String)] = [
        (.bulletedList, "\u{2022}"), (.dashedList, "\u{2013}"), (.checklistUnchecked, "\u{25CB}"), (.numberedList, "1."),
    ]

    @Test func backspaceRightAfterTheMarkerTurnsTheItemIntoBodyAndKeepsItsText() {
        for (style, glyph) in markers {
            let h = makeListHarness(text: "alpha\nbeta", textStyleData: listStyle([style, style]))
            let display = h.textView.text as NSString
            let second = display.paragraphRange(for: NSRange(location: display.length - 1, length: 0))
            // The marker is rendered text; content starts after it. Delete its last character.
            let markerEnd = second.location + (display.substring(with: second) as NSString).range(of: "beta").location
            let allowed = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: markerEnd - 1, length: 1), replacementText: "")
            #expect(!allowed, "\(style): the delete is handled, not passed to UIKit")
            let after = h.textView.text ?? ""
            let lastLine = after.components(separatedBy: "\n").last ?? ""
            #expect(lastLine == "beta", "\(style): second item becomes plain 'beta', got: \(lastLine)")
            #expect(after.components(separatedBy: "\n").first?.contains(glyph) == true, "\(style): the first item keeps its marker")
            #expect(h.getText().hasSuffix("beta") && !h.getText().contains(glyph), "\(style): no marker glyph is stored in the text, got: \(h.getText())")
        }
    }

    @Test func aSelectionReachingIntoTheTextKeepsItsNormalBehavior() {
        let h = makeListHarness(text: "alpha", textStyleData: listStyle([.bulletedList]))
        let display = h.textView.text as NSString
        let contentStart = (display as String as NSString).range(of: "alpha").location
        let allowed = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: contentStart - 1, length: 3), replacementText: "")
        #expect(allowed, "a delete that spans marker and text is left to UIKit")
    }
}

private func inline(_ ranges: [InlineStyleRange]) -> Data {
    try! JSONEncoder().encode(InlineStyleDocument(ranges: ranges))
}

private func bold(_ location: Int, _ length: Int) -> InlineStyleRange {
    InlineStyleRange(location: location, length: length, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
}

private func link(_ location: Int, _ length: Int, _ url: String) -> InlineStyleRange {
    InlineStyleRange(location: location, length: length, bold: false, italic: false, underline: false, strikethrough: false,
                     highlightIndex: nil, linkURL: url)
}

/// Delete Done and Sort Done used to set inlineStyleData to nil, wiping every bold, link and
/// highlight in the entry (audit item 3).
@MainActor
struct ChecklistBulkOpsKeepInlineTests {
    @Test func deleteDoneKeepsFormattingOnTheRowsThatStay() {
        // "done" (checked) is removed; "milk" is bold and "Notes" below is bold.
        let h = makeListHarness(
            text: "done\nmilk\nNotes",
            textStyleData: listStyle([.checklistChecked, .checklistUnchecked, .body]),
            inlineStyleData: inline([bold(5, 4), bold(10, 5)])
        )
        h.coordinator.deleteCheckedChecklistItems(in: h.textView)
        #expect(h.getText() == "milk\nNotes")
        let ranges = (try? JSONDecoder().decode(InlineStyleDocument.self, from: h.getInlineData() ?? Data()))?.ranges
        #expect(ranges == [bold(0, 4), bold(5, 5)], "got \(String(describing: ranges))")
    }

    @Test func sortDoneMovesALinkWithItsRow() {
        let h = makeListHarness(
            text: "paid\nshop",
            textStyleData: listStyle([.checklistChecked, .checklistUnchecked]),
            inlineStyleData: inline([link(0, 4, "https://example.com")])
        )
        h.coordinator.sortCheckedToBottom(in: h.textView)
        #expect(h.getText() == "shop\npaid")
        let ranges = (try? JSONDecoder().decode(InlineStyleDocument.self, from: h.getInlineData() ?? Data()))?.ranges
        #expect(ranges == [link(5, 4, "https://example.com")], "got \(String(describing: ranges))")
    }
}

private func inlineRanges(_ data: Data?) -> [InlineStyleRange]? {
    data.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges
}

/// Edits that move the logical text outside UIKit's typing path used to leave inlineStyleData at
/// the old offsets; the re-render then drew bold one or more characters off and the next
/// keystroke saved it (audit item 4). Each test checks the stored ranges and what the view shows.
@MainActor
struct InlineOffsetsAfterListEditsTests {
    private func displayLocation(of needle: String, in textView: UITextView) -> Int {
        ((textView.text ?? "") as NSString).range(of: needle).location
    }

    @Test func returnInAListKeepsBoldBelowInPlace() {
        let h = makeListHarness(text: "alpha\nNotes", textStyleData: listStyle([.bulletedList, .body]),
                                inlineStyleData: inline([bold(6, 5)]))
        let end = displayLocation(of: "alpha", in: h.textView) + 5
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: end, length: 0), replacementText: "\n")
        #expect(h.getText() == "alpha\n\nNotes")
        #expect(inlineRanges(h.getInlineData()) == [bold(7, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(7, 5)], "the view shows bold on \"Notes\"")
    }

    @Test func typingIntoAMarkerKeepsBoldBelowInPlace() {
        let h = makeListHarness(text: "alpha\nNotes", textStyleData: listStyle([.bulletedList, .body]),
                                inlineStyleData: inline([bold(6, 5)]))
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "x")
        #expect(h.getText() == "xalpha\nNotes")
        #expect(inlineRanges(h.getInlineData()) == [bold(7, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
    }

    @Test func numberedShortcutKeepsBoldBelowInPlace() {
        let h = makeListHarness(text: "1.go\nNotes", inlineStyleData: inline([bold(5, 5)]))
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementText: " ")
        #expect(h.getText() == "go\nNotes")
        #expect(inlineRanges(h.getInlineData()) == [bold(3, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(3, 5)], "the view shows bold on \"Notes\"")
    }

    @Test func makingAParagraphAListKeepsBoldBelowInPlace() {
        // The style is set before the re-render inserts the marker; the offset map must not
        // count a marker that isn't there yet.
        let h = makeListHarness(text: "alpha\nNotes", inlineStyleData: inline([bold(6, 5)]))
        h.coordinator.apply(.bulletedList, to: h.textView)
        #expect(h.getText() == "alpha\nNotes")
        #expect(inlineRanges(h.getInlineData()) == [bold(6, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(6, 5)], "the view shows bold on \"Notes\"")
    }

    @Test func appendingABlockKeepsLeadingLineBreaks() {
        #expect(trimmingTrailingNewlines("\nfirst\n\n") == "\nfirst")
        #expect(textWithInlinePhotoToken("\nfirst\n", at: 0) == "\nfirst\n[[mirror-photo-0]]\n")
    }

    // A style change replaces the paragraph's font; bold inside that paragraph must survive.

    @Test func boldInsideAParagraphSurvivesMakingItAList() {
        let h = makeListHarness(text: "alpha\nNotes", inlineStyleData: inline([bold(0, 5)]))
        h.coordinator.apply(.bulletedList, to: h.textView)
        #expect(inlineRanges(h.getInlineData()) == [bold(0, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(0, 5)], "the view shows bold on \"alpha\"")
    }

    @Test func boldInsideAParagraphSurvivesLeavingAList() {
        let h = makeListHarness(text: "alpha", textStyleData: listStyle([.bulletedList]), inlineStyleData: inline([bold(0, 5)]))
        h.coordinator.apply(.bulletedList, to: h.textView)
        #expect(h.getStyleData() == nil || (try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData()!))?.paragraphStyles == [.body])
        #expect(inlineRanges(h.getInlineData()) == [bold(0, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(0, 5)], "the view shows bold on \"alpha\"")
    }

    @Test func boldInsideAParagraphSurvivesSwitchingListType() {
        let h = makeListHarness(text: "alpha", textStyleData: listStyle([.bulletedList]), inlineStyleData: inline([bold(0, 5)]))
        h.coordinator.apply(.checklist, to: h.textView)
        #expect(inlineRanges(h.getInlineData()) == [bold(0, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(0, 5)], "the view shows bold on \"alpha\"")
    }

    // Inline ranges count a photo as one character, not its [[mirror-photo-N]] token.

    private static let onePixelPNG: Data = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }.pngData()!

    @Test func deletingAPhotoKeepsBoldBelowInPlace() {
        // Display "ab\n<photo>\nNotes": "Notes" starts at 5 in inline coordinates.
        let h = makeListHarness(text: "ab\n[[mirror-photo-0]]\nNotes", inlineStyleData: inline([bold(5, 5)]), photos: [Self.onePixelPNG])
        let attachment = ((h.textView.text ?? "") as NSString).range(of: "\u{FFFC}").location
        #expect(attachment == 3, "the photo renders as one attachment character")
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: attachment, length: 1), replacementText: "")
        #expect(h.getText() == "ab\nNotes")
        #expect(inlineRanges(h.getInlineData()) == [bold(3, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(3, 5)], "the view shows bold on \"Notes\"")
    }

    @Test func deleteDoneBelowAPhotoKeepsBoldInPlace() {
        // Rows: "ab", photo, "done" (checked), "milk" (bold). "milk" is at 10 in inline coordinates.
        let h = makeListHarness(text: "ab\n[[mirror-photo-0]]\ndone\nmilk",
                                textStyleData: listStyle([.body, .body, .checklistChecked, .checklistUnchecked]),
                                inlineStyleData: inline([bold(10, 4)]), photos: [Self.onePixelPNG])
        h.coordinator.deleteCheckedChecklistItems(in: h.textView)
        #expect(h.getText() == "ab\n[[mirror-photo-0]]\nmilk")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(5, 4)],
                "the view shows bold on \"milk\": \(String(describing: inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView))))")
    }

    // The subheading font is semibold. Its bold is the style's, not the user's.

    @Test func subheadingBoldIsNotStoredAsInline() {
        let h = makeListHarness(text: "alpha\nNotes", textStyleData: listStyle([.subheading, .body]))
        #expect(h.coordinator.extractedInlineStyleData(from: h.textView) == nil)
    }

    @Test func leavingSubheadingDropsItsStoredBoldButKeepsBoldElsewhere() {
        // Entries saved by older builds carry the subheading's bold as an inline range.
        let h = makeListHarness(text: "alpha\nNotes", textStyleData: listStyle([.subheading, .body]),
                                inlineStyleData: inline([bold(0, 5), bold(6, 5)]))
        h.coordinator.apply(.body, to: h.textView)
        #expect(inlineRanges(h.getInlineData()) == [bold(6, 5)], "stored: \(String(describing: inlineRanges(h.getInlineData())))")
        #expect(inlineRanges(h.coordinator.extractedInlineStyleData(from: h.textView)) == [bold(6, 5)], "the view shows \"alpha\" plain")
    }
}

/// A photo line is one paragraph in the stored style document, as the encoder and the Mac codec
/// count it. The renderer used to give it two slots, so styles below a mid-text photo read the
/// next paragraph's entry and the next keystroke saved the shift (audit item 2).
@MainActor
struct PhotoParagraphStyleTests {
    private static let onePixelPNG: Data = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }.pngData()!

    private func styles(_ data: Data?) -> [NoteParagraphTextStyle]? {
        data.flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }?.paragraphStyles
    }

    @Test func aHeadingBelowAPhotoSurvivesAKeystroke() {
        let text = "ab\n[[mirror-photo-0]]\nNotes"
        let h = makeListHarness(text: text, textStyleData: listStyle([.body, .body, .heading]), photos: [Self.onePixelPNG])
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == text)
        #expect(styles(h.getStyleData()) == [.body, .body, .heading], "got \(String(describing: styles(h.getStyleData())))")
    }

    @Test func aListBelowAPhotoKeepsItsMarkerOutOfTheText() {
        // The paragraph after the list item is long enough that an offset inflated by the photo
        // token lands inside it.
        let text = "ab\n[[mirror-photo-0]]\nmilk\nsome longer body paragraph here"
        let h = makeListHarness(text: text, textStyleData: listStyle([.body, .body, .bulletedList, .body]), photos: [Self.onePixelPNG])
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == text, "got \(h.getText().debugDescription)")
        #expect(styles(h.getStyleData()) == [.body, .body, .bulletedList, .body], "got \(String(describing: styles(h.getStyleData())))")
    }

    @Test func twoPhotosAndStylesAroundThem() {
        let text = "Title\n[[mirror-photo-0]]\nmiddle\n[[mirror-photo-1]]\nend"
        let stored: [NoteParagraphTextStyle] = [.title, .body, .heading, .body, .blockQuote]
        let h = makeListHarness(text: text, textStyleData: listStyle(stored), photos: [Self.onePixelPNG, Self.onePixelPNG])
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == text)
        #expect(styles(h.getStyleData()) == stored, "got \(String(describing: styles(h.getStyleData())))")
    }
}
