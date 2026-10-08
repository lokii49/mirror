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
) -> (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, getText: () -> String, getStyleData: () -> Data?, getInlineData: () -> Data?, panel: FormattingPanelState) {
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
    return (coordinator, textView, { text }, { textStyleData }, { inlineStyleData }, panelState)
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

    /// A list item, Return (which stores a trailing empty item), then a photo: the photo line holds a
    /// list slot. Its marker must be drawn once, so nothing is saved after the token.
    @Test func aPhotoOnAListSlotGetsNoMarkerSavedAfterIt() {
        for style in [NoteParagraphTextStyle.bulletedList, .checklistUnchecked, .numberedList] {
            for text in ["milk\n[[mirror-photo-0]]\n", "[[mirror-photo-0]]\nmilk"] {
                let h = makeListHarness(text: text, textStyleData: listStyle([style, style]), photos: [Self.onePixelPNG])
                let display = (h.textView.text ?? "") as NSString
                let photoLine = display.paragraphRange(for: NSRange(location: display.range(of: "\u{FFFC}").location, length: 0))
                let afterPhoto = display.substring(with: photoLine).components(separatedBy: "\u{FFFC}").last ?? ""
                #expect(afterPhoto.trimmingCharacters(in: .newlines).isEmpty, "\(style) \(text.debugDescription): nothing drawn after the photo, got \(afterPhoto.debugDescription)")
                h.coordinator.textViewDidChange(h.textView)
                #expect(h.getText() == text, "\(style): got \(h.getText().debugDescription)")
                // A second render and keystroke must not add one either.
                h.coordinator.applyStyledText(to: h.textView, preservingSelection: false)
                h.coordinator.textViewDidChange(h.textView)
                #expect(h.getText() == text, "\(style) after re-render: got \(h.getText().debugDescription)")
            }
        }
    }

    /// The one-time cleanup's result must stay clean once the editor renders it and saves again.
    @Test func aRepairedEntryStaysCleanInTheEditor() {
        let styles = listStyle([.bulletedList, .bulletedList])
        let fixed = NoteEditorCodec.repairPhotoMarkerDamage(text: "milk\n[[mirror-photo-0]]•  \n", textStyleData: styles, inlineStyleData: nil)
        #expect(fixed?.text == "milk\n[[mirror-photo-0]]\n")
        let h = makeListHarness(text: fixed?.text ?? "", textStyleData: styles, photos: [Self.onePixelPNG])
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == "milk\n[[mirror-photo-0]]\n", "got \(h.getText().debugDescription)")
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

/// A photo whose data is missing or won't decode used to render as nothing, so there was no
/// attachment character to turn back into its token: the next keystroke saved the text without it,
/// and every later photo was matched to the wrong token (audit item 5).
@MainActor
struct UnreadablePhotoTests {
    private static let onePixelPNG: Data = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }.pngData()!
    private static let junk = Data("not an image".utf8)

    @Test func anUndecodablePhotoKeepsItsTokenThroughAKeystroke() {
        let text = "ab\n[[mirror-photo-0]]\nNotes"
        let h = makeListHarness(text: text, photos: [Self.junk])
        #expect(((h.textView.text ?? "") as NSString).range(of: "\u{FFFC}").location != NSNotFound, "a placeholder is drawn")
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == text, "got \(h.getText().debugDescription)")
    }

    @Test func aMissingPhotoKeepsItsTokenThroughAKeystroke() {
        // The token points past the photo array (a photo that failed to save or sync).
        let text = "ab\n[[mirror-photo-0]]\nNotes"
        let h = makeListHarness(text: text, photos: [])
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == text, "got \(h.getText().debugDescription)")
    }

    @Test func deletingAPhotoAfterAnUnreadableOneDeletesTheRightPhoto() {
        let h = makeListHarness(text: "a\n[[mirror-photo-0]]\nb\n[[mirror-photo-1]]\nc", photos: [Self.junk, Self.onePixelPNG])
        let display = (h.textView.text ?? "") as NSString
        let first = display.range(of: "\u{FFFC}").location
        let second = display.range(of: "\u{FFFC}", range: NSRange(location: first + 1, length: display.length - first - 1)).location
        #expect(second != NSNotFound, "both photos are drawn")
        guard second != NSNotFound else { return }
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: second, length: 1), replacementText: "")
        #expect(h.getText() == "a\n[[mirror-photo-0]]\nb\nc", "got \(h.getText().debugDescription)")
    }
}

/// Formatting chosen with nothing selected must survive render passes, show in the panel, and
/// apply to what is typed next; typing after formatted text continues it (audit item 9).
@MainActor
struct TypingFormattingTests {
    private func isBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
    }

    /// Types `string` at the caret the way UIKit does (with the typing attributes), then reports it.
    private func type(_ string: String, into h: ReturnType) {
        let caret = h.textView.selectedRange.location
        h.textView.textStorage.replaceCharacters(in: NSRange(location: caret, length: 0),
                                                 with: NSAttributedString(string: string, attributes: h.textView.typingAttributes))
        h.textView.selectedRange = NSRange(location: caret + (string as NSString).length, length: 0)
        h.coordinator.textViewDidChange(h.textView)
    }
    typealias ReturnType = (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, getText: () -> String,
                            getStyleData: () -> Data?, getInlineData: () -> Data?, panel: FormattingPanelState)

    @Test func boldWithNoSelectionSurvivesARenderPassAndShowsInThePanel() {
        let h = makeListHarness(text: "hello world")
        h.textView.selectedRange = NSRange(location: 5, length: 0)
        h.coordinator.apply(.bold, to: h.textView)
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)   // an updateUIView pass
        #expect(isBold(h.textView.typingAttributes), "typing stays bold after a render pass")
        #expect(h.panel.activeInlineStyles.bold, "the B button shows on")
    }

    @Test func textTypedAfterBoldWithNoSelectionIsBoldAndStaysBold() {
        let h = makeListHarness(text: "hello world")
        h.textView.selectedRange = NSRange(location: 5, length: 0)
        h.coordinator.apply(.bold, to: h.textView)
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)
        type("X", into: h)
        type("Y", into: h)
        let ranges = h.getInlineData().flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges
        #expect(ranges?.count == 1 && ranges?.first?.location == 5 && ranges?.first?.length == 2 && ranges?.first?.bold == true,
                "both typed characters are bold: \(String(describing: ranges))")
    }

    @Test func typingAfterABoldWordContinuesBold() {
        let bold = InlineStyleRange(location: 0, length: 5, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        let h = makeListHarness(text: "hello world", inlineStyleData: try? JSONEncoder().encode(InlineStyleDocument(ranges: [bold])))
        h.textView.selectedRange = NSRange(location: 5, length: 0)
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)
        type("X", into: h)
        type("Y", into: h)
        let ranges = h.getInlineData().flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges
        #expect(ranges?.first?.length == 7, "the bold run grows to cover both: \(String(describing: ranges))")
    }

    @Test func turningBoldOffInsideABoldWordTypesPlain() {
        let bold = InlineStyleRange(location: 0, length: 5, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        let h = makeListHarness(text: "hello world", inlineStyleData: try? JSONEncoder().encode(InlineStyleDocument(ranges: [bold])))
        h.textView.selectedRange = NSRange(location: 5, length: 0)
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)
        h.coordinator.apply(.bold, to: h.textView)
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)
        #expect(!isBold(h.textView.typingAttributes))
        type("X", into: h)
        let ranges = h.getInlineData().flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges
        #expect(ranges?.count == 1 && ranges?.first?.length == 5, "X is not bold: \(String(describing: ranges))")
    }

    @Test func aListMarkerIsNotInherited() {
        // The caret right after "•  " must not pick up anything from the marker.
        let h = makeListHarness(text: "milk", textStyleData: try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.bulletedList])))
        h.textView.selectedRange = NSRange(location: 3, length: 0)
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)
        #expect(!isBold(h.textView.typingAttributes))
    }
}

/// UITextView's own undo stack is cleared whenever `attributedText` is set, so list Return,
/// formatting and checklist commands wiped all undo history. The editor keeps its own (audit item 7).
@MainActor
struct EditorUndoTests {
    typealias Harness = (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, getText: () -> String,
                         getStyleData: () -> Data?, getInlineData: () -> Data?, panel: FormattingPanelState)

    /// Types the way UIKit does: ask the delegate, insert with the typing attributes, report the change.
    private func type(_ string: String, into h: Harness) {
        let caret = h.textView.selectedRange.location
        let range = NSRange(location: caret, length: 0)
        guard h.coordinator.textView(h.textView, shouldChangeTextIn: range, replacementText: string) else { return }
        h.textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: h.textView.typingAttributes))
        h.textView.selectedRange = NSRange(location: caret + (string as NSString).length, length: 0)
        h.coordinator.textViewDidChange(h.textView)
    }

    private func inline(_ h: Harness) -> [InlineStyleRange] {
        h.getInlineData().flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? []
    }

    @Test func listReturnCanBeUndoneAndRedone() {
        let h = makeListHarness(text: "milk", textStyleData: listStyle([.bulletedList]))
        let end = ((h.textView.text ?? "") as NSString).length
        h.textView.selectedRange = NSRange(location: end, length: 0)
        type("\n", into: h)
        #expect(h.getText() == "milk\n")
        #expect(h.coordinator.canUndoEdit)
        h.coordinator.apply(.undo, to: h.textView)
        #expect(h.getText() == "milk")
        #expect(h.coordinator.canRedoEdit)
        h.coordinator.apply(.redo, to: h.textView)
        #expect(h.getText() == "milk\n")
    }

    @Test func boldCanBeUndone() {
        let h = makeListHarness(text: "hello world")
        h.textView.selectedRange = NSRange(location: 0, length: 5)
        h.coordinator.apply(.bold, to: h.textView)
        #expect(inline(h).first?.bold == true)
        h.coordinator.apply(.undo, to: h.textView)
        #expect(inline(h).isEmpty)
    }

    @Test func typingBeforeACommandIsStillUndoableAfterIt() {
        // The command used to clear UIKit's stack, losing the typing undo.
        let h = makeListHarness(text: "hello")
        h.textView.selectedRange = NSRange(location: 5, length: 0)
        type(" there", into: h)
        h.textView.selectedRange = NSRange(location: 0, length: 5)
        h.coordinator.apply(.italic, to: h.textView)
        h.coordinator.apply(.undo, to: h.textView)   // the italic
        #expect(inline(h).isEmpty && h.getText() == "hello there")
        h.coordinator.apply(.undo, to: h.textView)   // the typing
        #expect(h.getText() == "hello")
    }

    @Test func aRunOfTypingIsOneStepAndALineBreakStartsAnother() {
        let h = makeListHarness(text: "a")
        h.textView.selectedRange = NSRange(location: 1, length: 0)
        for ch in ["b", "c", "d"] { type(ch, into: h) }
        type("\n", into: h)
        for ch in ["e", "f"] { type(ch, into: h) }
        #expect(h.getText() == "abcd\nef")
        h.coordinator.apply(.undo, to: h.textView)
        #expect(h.getText() == "abcd\n")
        h.coordinator.apply(.undo, to: h.textView)
        #expect(h.getText() == "abcd")
        h.coordinator.apply(.undo, to: h.textView)
        #expect(h.getText() == "a")
        #expect(!h.coordinator.canUndoEdit)
    }

    @Test func loadingTheEntryIsNotUndoable() {
        let h = makeListHarness(text: "")
        h.coordinator.parent.text = "loaded entry text"   // WriteView sets the entry's text after the editor appears
        h.coordinator.noteOutsideChange(in: h.textView)
        #expect(!h.coordinator.canUndoEdit)
    }

    @Test func anAppendAfterEditingIsUndoable() {
        let h = makeListHarness(text: "note")
        h.textView.selectedRange = NSRange(location: 4, length: 0)
        type("s", into: h)
        h.coordinator.parent.text = "notes\n\nscanned text"   // a scan or Talk It Out append
        h.coordinator.noteOutsideChange(in: h.textView)
        h.coordinator.apply(.undo, to: h.textView)
        #expect(h.getText() == "notes")
    }

    /// The text view's own undo manager (what Cmd-Z, shake and the three-finger gesture use) is the
    /// editor's. No window or first responder here: keyboard state is shared across parallel tests.
    @Test func theEditorTextViewHandsUIKitTheEditorHistory() {
        let h = makeListHarness(text: "hello world")
        let tv = MirrorEditorTextView()
        tv.editorUndo = h.coordinator.editorUndoManager
        #expect(tv.undoManager === h.coordinator.editorUndoManager)
        h.coordinator.editorUndoManager.textView = h.textView
        h.textView.selectedRange = NSRange(location: 0, length: 5)
        h.coordinator.apply(.bold, to: h.textView)
        #expect(tv.undoManager?.canUndo == true)
        tv.undoManager?.undo()
        #expect(inline(h).isEmpty)
    }

    @Test func theTextViewUndoManagerUsesTheEditorHistory() {
        // Cmd-Z, shake and the three-finger gesture ask the text view's undo manager.
        let h = makeListHarness(text: "hello world")
        let um = h.coordinator.editorUndoManager
        um.textView = h.textView
        h.textView.selectedRange = NSRange(location: 0, length: 5)
        h.coordinator.apply(.bold, to: h.textView)
        #expect(um.canUndo)
        um.undo()
        #expect(inline(h).isEmpty)
        #expect(um.canRedo)
    }
}

/// An input method (Japanese, Chinese, Korean) keeps marked text while composing. Setting
/// `attributedText`, list handling or marker handling during it ended the composition mid-word
/// (audit item 8). Driven with UIKit's own `setMarkedText`.
@MainActor
struct CompositionTests {
    typealias Harness = (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, getText: () -> String,
                         getStyleData: () -> Data?, getInlineData: () -> Data?, panel: FormattingPanelState)

    /// What UIKit does for a composition keystroke: ask the delegate, mark the text, report it.
    private func compose(_ marked: String, into h: Harness) {
        let range = h.textView.markedTextRange.map { tr in
            NSRange(location: h.textView.offset(from: h.textView.beginningOfDocument, to: tr.start),
                    length: h.textView.offset(from: tr.start, to: tr.end))
        } ?? h.textView.selectedRange
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: range, replacementText: marked)
        h.textView.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0))
        h.coordinator.textViewDidChange(h.textView)
    }

    private func styles(_ h: Harness) -> [NoteParagraphTextStyle]? {
        h.getStyleData().flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }?.paragraphStyles
    }

    @Test func aRenderPassDoesNotEndTheComposition() {
        let h = makeListHarness(text: "note")
        h.textView.selectedRange = NSRange(location: 4, length: 0)
        compose("か", into: h)
        // Something else changes the stored formatting (a cache miss would set attributedText).
        let bold = InlineStyleRange(location: 0, length: 4, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)
        h.coordinator.parent.inlineStyleData = try? JSONEncoder().encode(InlineStyleDocument(ranges: [bold]))
        h.coordinator.applyStyledText(to: h.textView, preservingSelection: true)
        #expect(h.textView.markedTextRange != nil, "still composing")
        // The postponed render runs once the composition is committed.
        h.textView.unmarkText()
        h.coordinator.textViewDidChange(h.textView)
        let font = h.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true, "the deferred render applied the bold")
        #expect(h.getText() == "noteか")
    }

    @Test func returnWhileComposingInAListCommitsThenAddsARow() {
        let h = makeListHarness(text: "milk", textStyleData: listStyle([.bulletedList]))
        let end = ((h.textView.text ?? "") as NSString).length
        h.textView.selectedRange = NSRange(location: end, length: 0)
        compose("한", into: h)
        let caret = h.textView.selectedRange
        let allowed = h.coordinator.textView(h.textView, shouldChangeTextIn: caret, replacementText: "\n")
        #expect(!allowed, "the list handles Return")
        #expect(h.textView.markedTextRange == nil)
        #expect(h.getText() == "milk한\n", "got \(h.getText().debugDescription)")
        #expect(styles(h) == [.bulletedList, .bulletedList], "got \(String(describing: styles(h)))")
    }

    @Test func deletingTheLastComposedLetterDoesNotLeaveTheList() {
        // Pinyin "n" typed into a new empty list item, then Backspace inside the composition.
        let h = makeListHarness(text: "milk\n", textStyleData: listStyle([.bulletedList, .bulletedList]))
        let end = ((h.textView.text ?? "") as NSString).length
        h.textView.selectedRange = NSRange(location: end, length: 0)
        compose("n", into: h)
        let marked = h.textView.markedTextRange!
        let range = NSRange(location: h.textView.offset(from: h.textView.beginningOfDocument, to: marked.start), length: 1)
        let allowed = h.coordinator.textView(h.textView, shouldChangeTextIn: range, replacementText: "")
        #expect(allowed, "the input method handles it; the list item stays")
        #expect(styles(h) == [.bulletedList, .bulletedList])
    }

    @Test func aCompositionIsOneUndoStep() {
        let h = makeListHarness(text: "note")
        h.textView.selectedRange = NSRange(location: 4, length: 0)
        for step in ["か", "かん", "かんじ"] { compose(step, into: h) }
        h.textView.unmarkText()
        h.coordinator.textViewDidChange(h.textView)
        #expect(h.getText() == "noteかんじ")
        h.coordinator.apply(.undo, to: h.textView)
        #expect(h.getText() == "note", "got \(h.getText().debugDescription)")
    }
}

/// Return on an empty list item that has rows below it ends the list there: the item becomes a body
/// line, the caret stays on it, and a numbered list below restarts at 1 (audit item 10).
@MainActor
struct ReturnOnEmptyMiddleItemTests {
    private func styles(_ data: Data?) -> [NoteParagraphTextStyle]? {
        data.flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }?.paragraphStyles
    }

    @Test func emptyMiddleBulletBecomesBodyAndTheCaretStaysThere() {
        let h = makeListHarness(text: "a\n\nb", textStyleData: listStyle([.bulletedList, .bulletedList, .bulletedList]))
        let display = (h.textView.text ?? "") as NSString
        let middle = display.paragraphRange(for: NSRange(location: display.range(of: "a").location + 2, length: 0))
        let caret = middle.location + 3   // after "•  "
        h.textView.selectedRange = NSRange(location: caret, length: 0)
        let allowed = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: caret, length: 0), replacementText: "\n")
        #expect(!allowed)
        #expect(h.getText() == "a\n\nb", "got \(h.getText().debugDescription)")
        #expect(styles(h.getStyleData()) == [.bulletedList, .body, .bulletedList], "got \(String(describing: styles(h.getStyleData())))")
        let now = (h.textView.text ?? "") as NSString
        let caretParagraph = now.paragraphRange(for: NSRange(location: h.textView.selectedRange.location, length: 0))
        #expect(caretParagraph.location == middle.location, "the caret stays on the emptied line")
    }

    @Test func numberingBelowRestartsAfterTheListEnds() {
        let h = makeListHarness(text: "one\n\ntwo\nthree", textStyleData: listStyle([.numberedList, .numberedList, .numberedList, .numberedList]))
        let display = (h.textView.text ?? "") as NSString
        let middle = display.paragraphRange(for: NSRange(location: NSMaxRange(display.paragraphRange(for: NSRange(location: 0, length: 0))), length: 0))
        let caret = middle.location + 3   // after "2.\t"
        h.textView.selectedRange = NSRange(location: caret, length: 0)
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: caret, length: 0), replacementText: "\n")
        let lines = (h.textView.text ?? "").components(separatedBy: "\n")
        #expect(lines.count == 4 && lines[2].hasPrefix("1.\t") && lines[3].hasPrefix("2.\t"),
                "numbering below restarts: \(lines.map(\.debugDescription))")
    }
}
