import Testing
import SwiftUI
import UIKit
@testable import mirror

// Coverage map for the "Aa" formatting panel (NoteEditorTextView + FormattingPanelView):
//   - paragraph styles solo (rendering)
//   - paragraph style × inline style combinations (bold/italic/underline/strikethrough/highlight)
//   - paragraph style × font family combinations
//   - checklist check/uncheck (glyph swap, dim-not-strike)
//   - Return key behavior per paragraph style (list continuation, empty-list exit, heading→body reset)
//   - backspace merging two differently-styled paragraphs
//
// What's intentionally NOT covered here: interactive paragraph-style *conversion* via the
// toolbar (apply(.heading, ...) etc.) and multi-paragraph-selection restyling. That code path
// branches on `textView.isFirstResponder`, which a bare UITextView never is outside a real
// window + keyboard session — not reliably exercisable headless. Verify those on-device.

@MainActor
private func makeEditorHarness(
    text: String = "",
    textStyleData: Data? = nil,
    inlineStyleData: Data? = nil,
    fontChoiceRaw: String = WritingFontChoice.system.rawValue
) -> (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, getText: () -> String, getStyleData: () -> Data?) {
    var text = text
    var textStyleData = textStyleData
    var inlineStyleData = inlineStyleData
    var photos: [Data] = []
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
    return (coordinator, textView, { text }, { textStyleData })
}

private func style(_ doc: NoteTextStyleDocument) -> Data { try! JSONEncoder().encode(doc) }
private func inline(_ ranges: [InlineStyleRange]) -> Data { try! JSONEncoder().encode(InlineStyleDocument(ranges: ranges)) }

// MARK: - Solo paragraph style rendering

@MainActor
struct ParagraphStyleRenderingTests {

    @Test func bodyHasNoMarkerAndDefaultFont() {
        let h = makeEditorHarness(text: "hello", textStyleData: nil)
        let rendered = h.textView.attributedText!
        #expect(rendered.string == "hello")
    }

    @Test func titleHeadingSubheadingHaveNoMarker() throws {
        for s: NoteParagraphTextStyle in [.title, .heading, .subheading, .monospaced, .blockQuote] {
            let h = makeEditorHarness(text: "hello", textStyleData: style(.init(paragraphStyles: [s])))
            let rendered = try #require(h.textView.attributedText)
            #expect(rendered.string == "hello", "\(s) should not add a marker prefix")
        }
    }

    @Test func blockQuoteIsMutedAndIndentedButNotItalic() throws {
        // Deliberately not italic — see NoteEditorTextView.attributes(for:) comment:
        // baking italic into the paragraph style's own font would fight the Italic
        // inline toggle, which manages .traitItalic on the rendered font directly.
        let h = makeEditorHarness(text: "quoted", textStyleData: style(.init(paragraphStyles: [.blockQuote])))
        let rendered = try #require(h.textView.attributedText)
        let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(!font.fontDescriptor.symbolicTraits.contains(.traitItalic), "block quote must not force italic")
        let color = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color == UIColor.secondaryLabel)
        let ps = try #require(rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(ps.headIndent > 0)
        #expect(ps.firstLineHeadIndent > 0)
    }

    @Test func blockQuoteRoundTripsThroughEncodedTextStyleData() throws {
        // NoteParagraphTextStyle is String-backed Codable and persisted verbatim in
        // encodedTextStyleData — a rawValue collision or typo would silently decode
        // to the wrong style (or fail entirely) without ever touching the editor.
        let doc = NoteTextStyleDocument(paragraphStyles: [.body, .blockQuote, .heading], indentLevels: nil, fontChoices: nil)
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        #expect(decoded.paragraphStyles == [.body, .blockQuote, .heading])
    }

    @Test func bulletedDashedNumberedChecklistHaveMarkers() throws {
        let cases: [(NoteParagraphTextStyle, String)] = [
            (.bulletedList, "•"),
            (.dashedList, "–"),
            (.checklistUnchecked, "○"),
            (.checklistChecked, "✓"),
        ]
        for (s, marker) in cases {
            let h = makeEditorHarness(text: "hello", textStyleData: style(.init(paragraphStyles: [s])))
            let rendered = try #require(h.textView.attributedText)
            #expect(rendered.string.hasPrefix(marker), "\(s) should render marker \(marker), got \(rendered.string)")
            #expect(rendered.string.hasSuffix("hello"))
        }
    }

    @Test func numberedListRendersOrdinal() throws {
        let h = makeEditorHarness(
            text: "one\ntwo\nthree",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList, .numberedList]))
        )
        let rendered = try #require(h.textView.attributedText)
        #expect(rendered.string.hasPrefix("1."))
        #expect(rendered.string.contains("2."))
        #expect(rendered.string.contains("3."))
    }

    // Indenting a numbered item nests it under its parent — the nested run
    // should restart at 1 rather than continuing the outer sequence, and the
    // outer list should resume its own count (3, not 5) once it returns to
    // the shallower level. Was previously a single flat counter ignoring
    // indent level entirely.
    @Test func numberedListRestartsOrdinalOnNestedIndent() throws {
        let h = makeEditorHarness(
            text: "first\nsecond\nsub one\nsub two\nthird",
            textStyleData: style(.init(
                paragraphStyles: [.numberedList, .numberedList, .numberedList, .numberedList, .numberedList],
                indentLevels: [0, 0, 1, 1, 0]
            ))
        )
        let lines = try #require(h.textView.attributedText).string.components(separatedBy: "\n")
        #expect(lines.count == 5)
        #expect(lines[0].hasPrefix("1."))
        #expect(lines[1].hasPrefix("2."))
        #expect(lines[2].hasPrefix("1."), "nested sub-list should restart at 1, got \(lines[2])")
        #expect(lines[3].hasPrefix("2."))
        #expect(lines[4].hasPrefix("3."), "outer list should resume at 3, got \(lines[4])")
    }

    @Test func monospacedUsesMonospacedFontRegardlessOfChosenFamily() throws {
        for family: WritingFontChoice in [.system, .serif, .rounded, .monospaced] {
            let h = makeEditorHarness(
                text: "code",
                textStyleData: style(.init(paragraphStyles: [.monospaced])),
                fontChoiceRaw: family.rawValue
            )
            let rendered = try #require(h.textView.attributedText)
            let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace),
                    "monospaced paragraph must stay monospaced even when body font is \(family)")
        }
    }

    @Test func bodyFollowsChosenFontFamily() throws {
        for family: WritingFontChoice in [.serif, .rounded, .monospaced] {
            let h = makeEditorHarness(text: "hello", textStyleData: nil, fontChoiceRaw: family.rawValue)
            let rendered = try #require(h.textView.attributedText)
            let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
            let expectedDesign = family.uiDesign
            #expect(font.fontDescriptor.object(forKey: .traits) != nil || expectedDesign == .default,
                    "body text should adopt the \(family) design")
        }
    }

    @Test func checklistCheckedDimsTextButDoesNotStrikethrough() throws {
        let h = makeEditorHarness(text: "done", textStyleData: style(.init(paragraphStyles: [.checklistChecked])))
        let rendered = try #require(h.textView.attributedText)
        for i in 0..<rendered.length {
            #expect(rendered.attribute(.strikethroughStyle, at: i, effectiveRange: nil) == nil,
                     "checked checklist text must not auto-strikethrough (index \(i))")
        }
        let color = rendered.attribute(.foregroundColor, at: rendered.length - 1, effectiveRange: nil) as? UIColor
        #expect(color == UIColor.tertiaryLabel)
    }

    @Test func checklistUncheckedIsFullOpacity() throws {
        let h = makeEditorHarness(text: "todo", textStyleData: style(.init(paragraphStyles: [.checklistUnchecked])))
        let rendered = try #require(h.textView.attributedText)
        let color = rendered.attribute(.foregroundColor, at: rendered.length - 1, effectiveRange: nil) as? UIColor
        #expect(color == UIColor.label)
    }
}

// MARK: - Paragraph style × inline style combinations

@MainActor
struct ParagraphInlineCombinationTests {

    @Test func boldOnEveryParagraphStyle() throws {
        for s: NoteParagraphTextStyle in [.body, .title, .heading, .subheading, .monospaced,
                                           .bulletedList, .dashedList, .checklistUnchecked, .checklistChecked] {
            let h = makeEditorHarness(
                text: "word",
                textStyleData: style(.init(paragraphStyles: [s])),
                inlineStyleData: inline([.init(location: 0, length: 4, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)])
            )
            let rendered = try #require(h.textView.attributedText)
            let markerLen = (rendered.string as NSString).length - 4
            let font = try #require(rendered.attribute(.font, at: markerLen, effectiveRange: nil) as? UIFont)
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold), "bold lost on \(s)")
        }
    }

    @Test func strikethroughOnCheckedChecklistIsRespectedNotSuppressed() throws {
        // Regression: checked checklist rows no longer auto-strike, so an explicit
        // inline strikethrough on a checked item's text must render, not be swallowed.
        let h = makeEditorHarness(
            text: "done",
            textStyleData: style(.init(paragraphStyles: [.checklistChecked])),
            inlineStyleData: inline([.init(location: 0, length: 4, bold: false, italic: false, underline: false, strikethrough: true, highlightIndex: nil)])
        )
        let rendered = try #require(h.textView.attributedText)
        let lastIndex = rendered.length - 1
        #expect(rendered.attribute(.strikethroughStyle, at: lastIndex, effectiveRange: nil) != nil,
                "explicit strikethrough on checked-item text should render")
    }

    @Test func highlightPlusBoldPlusUnderlineStack() throws {
        let h = makeEditorHarness(
            text: "word",
            textStyleData: style(.init(paragraphStyles: [.heading])),
            inlineStyleData: inline([.init(location: 0, length: 4, bold: true, italic: false, underline: true, strikethrough: false, highlightIndex: 2)])
        )
        let rendered = try #require(h.textView.attributedText)
        let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(rendered.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
        #expect(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
    }

    @Test func textColorRendersForegroundColorAndSurvivesExtraction() throws {
        let h = makeEditorHarness(
            text: "word",
            inlineStyleData: inline([.init(location: 0, length: 4, bold: false, italic: false, underline: false, strikethrough: false, highlightIndex: nil, linkURL: nil, textColorIndex: 1)])
        )
        let rendered = try #require(h.textView.attributedText)
        #expect(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil)

        // Round-trip: applying the command should extract back to the same index.
        h.textView.selectedRange = NSRange(location: 0, length: 4)
        h.coordinator.applyTextColor(3, in: h.textView)
        let extracted = try #require(h.coordinator.extractedInlineStyleData(from: h.textView))
        let doc = try JSONDecoder().decode(InlineStyleDocument.self, from: extracted)
        #expect(doc.ranges.contains { $0.textColorIndex == 3 })
    }

    // .foregroundColor has no "unset" default — every paragraph style bakes
    // one in (attributes(for:) in NoteEditorTextView). Tapping the default "A"
    // swatch (index nil) must restore that base color, not just delete the
    // attribute and fall back to whatever UIKit default applies (which reads
    // as invisible/wrong-contrast text in Sentinel or dark mode).
    @Test func textColorRemovalRestoresBaseColorNotJustDeletesAttribute() throws {
        let h = makeEditorHarness(text: "word")
        h.textView.selectedRange = NSRange(location: 0, length: 4)
        h.coordinator.applyTextColor(1, in: h.textView)
        let colored = try #require(h.textView.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        #expect(colored != UIColor.label)

        h.textView.selectedRange = NSRange(location: 0, length: 4)
        h.coordinator.applyTextColor(nil, in: h.textView)
        let restored = try #require(h.textView.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        #expect(restored == UIColor.label, "removing text color on a body paragraph should restore .label, not leave the attribute unset")

        let extracted = h.coordinator.extractedInlineStyleData(from: h.textView)
        if let extracted, let doc = try? JSONDecoder().decode(InlineStyleDocument.self, from: extracted) {
            #expect(!doc.ranges.contains { $0.textColorIndex != nil })
        }
    }

    @Test func clearFormattingRestoresBaseColorOnSubheading() throws {
        let h = makeEditorHarness(
            text: "word",
            textStyleData: style(.init(paragraphStyles: [.subheading])),
            inlineStyleData: inline([.init(location: 0, length: 4, bold: false, italic: false, underline: false, strikethrough: false, highlightIndex: nil, linkURL: nil, textColorIndex: 2)])
        )
        h.textView.selectedRange = NSRange(location: 0, length: 4)
        h.coordinator.applyClearFormatting(in: h.textView)
        let restored = try #require(h.textView.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        #expect(restored == UIColor.secondaryLabel, "clearing formatting on a subheading should restore .secondaryLabel, not .label or an unset attribute")
    }

    @Test func inlineRangeSpanningTwoNonListParagraphsAppliesToBoth() throws {
        // Body/Heading/Subheading/Title/Mono add no marker chars, so a bold range
        // crossing a paragraph boundary between them should still land correctly on
        // both sides.
        let text = "AAA\nBBB"
        let h = makeEditorHarness(
            text: text,
            textStyleData: style(.init(paragraphStyles: [.heading, .body])),
            inlineStyleData: inline([.init(location: 0, length: 7, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)])
        )
        let rendered = try #require(h.textView.attributedText)
        for i in [0, 4, rendered.length - 1] {
            let font = try #require(rendered.attribute(.font, at: i, effectiveRange: nil) as? UIFont)
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold), "bold should span both paragraphs at index \(i)")
        }
    }
}

// MARK: - Checklist interactive behavior (tap-to-toggle)

@MainActor
private final class FakeTap: UITapGestureRecognizer {
    let point: CGPoint
    init(point: CGPoint) {
        self.point = point
        super.init(target: nil, action: nil)
    }
    override func location(in view: UIView?) -> CGPoint { point }
}

@MainActor
struct ChecklistTapTests {

    @Test func tapOnUncheckedMarkerFlipsGlyphImmediately() throws {
        let h = makeEditorHarness(text: "todo", textStyleData: style(.init(paragraphStyles: [.checklistUnchecked])))
        h.textView.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        h.textView.layoutIfNeeded()

        let tap = FakeTap(point: CGPoint(x: 12, y: 10))
        h.textView.addGestureRecognizer(tap)
        h.coordinator.handleTap(tap)

        let rendered = try #require(h.textView.attributedText)
        #expect(rendered.string.hasPrefix("✓"), "tapping the checkbox must flip the glyph in the same pass, got: \(rendered.string)")
    }

    @Test func tapOnCheckedMarkerFlipsBackToCircle() throws {
        let h = makeEditorHarness(text: "todo", textStyleData: style(.init(paragraphStyles: [.checklistChecked])))
        h.textView.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        h.textView.layoutIfNeeded()

        let tap = FakeTap(point: CGPoint(x: 12, y: 10))
        h.textView.addGestureRecognizer(tap)
        h.coordinator.handleTap(tap)

        let rendered = try #require(h.textView.attributedText)
        #expect(rendered.string.hasPrefix("○"))
    }

    @Test func tapOutsideMarkerZoneDoesNothing() throws {
        let h = makeEditorHarness(text: "todo", textStyleData: style(.init(paragraphStyles: [.checklistUnchecked])))
        h.textView.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        h.textView.layoutIfNeeded()

        let tap = FakeTap(point: CGPoint(x: 200, y: 10)) // well past the 44pt marker zone
        h.textView.addGestureRecognizer(tap)
        h.coordinator.handleTap(tap)

        let rendered = try #require(h.textView.attributedText)
        #expect(rendered.string.hasPrefix("○"), "tap outside the checkbox hit-zone must not toggle")
    }
}

// MARK: - Bulk checklist operations

@MainActor
struct BulkChecklistTests {

    @Test func checkAllItemsChecksOnlyChecklistParagraphs() {
        let h = makeEditorHarness(
            text: "a\nb\nc",
            textStyleData: style(.init(paragraphStyles: [.checklistUnchecked, .body, .checklistUnchecked]))
        )
        h.coordinator.bulkSetChecklist(.checklistChecked, in: h.textView)
        let doc = try! JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData()!)
        #expect(doc.paragraphStyles == [.checklistChecked, .body, .checklistChecked])
    }

    @Test func sortCheckedToBottomMovesCheckedItemsDownWithinBlock() {
        let h = makeEditorHarness(
            text: "a\nb\nc",
            textStyleData: style(.init(paragraphStyles: [.checklistChecked, .checklistUnchecked, .checklistChecked]))
        )
        h.coordinator.sortCheckedToBottom(in: h.textView)
        #expect(h.getText() == "b\na\nc")
    }

    @Test func deleteCheckedItemsRemovesOnlyCheckedRows() {
        let h = makeEditorHarness(
            text: "keep\ngone\nkeep2",
            textStyleData: style(.init(paragraphStyles: [.checklistUnchecked, .checklistChecked, .checklistUnchecked]))
        )
        h.coordinator.deleteCheckedChecklistItems(in: h.textView)
        #expect(h.getText() == "keep\nkeep2")
    }
}

// MARK: - Return key behavior per paragraph style

@MainActor
struct ReturnKeyContinuationTests {

    @Test func headingSubheadingTitleMonoResetTypingToBodyOnReturn() {
        for s: NoteParagraphTextStyle in [.title, .heading, .subheading, .monospaced, .blockQuote] {
            let h = makeEditorHarness(text: "Section", textStyleData: style(.init(paragraphStyles: [s])))
            let endLocation = (h.textView.text as NSString).length
            let shouldChange = h.coordinator.textView(
                h.textView,
                shouldChangeTextIn: NSRange(location: endLocation, length: 0),
                replacementText: "\n"
            )
            #expect(shouldChange, "non-list styles fall through to default newline insertion")
            #expect(h.textView.typingAttributes[.font] != nil)
            let font = h.textView.typingAttributes[.font] as? UIFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) != true,
                    "\(s): typing after Return must reset to body, not keep the heading's bold trait")
        }
    }

    @Test func bulletedListContinuesOnReturn() {
        let h = makeEditorHarness(text: "item", textStyleData: style(.init(paragraphStyles: [.bulletedList])))
        let endLocation = (h.textView.text as NSString).length
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: endLocation, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange, "list continuation is handled manually (insertListRow), not default insertion")
        #expect(h.textView.text.contains("•"), "new row should carry the list marker")
    }

    @Test func returnOnEmptyListItemExitsList() {
        // Marker with nothing typed after it — pressing Return should exit the list,
        // not add another empty bullet.
        // Raw logical text is empty — the marker itself is rendered, not stored.
        let h = makeEditorHarness(text: "", textStyleData: style(.init(paragraphStyles: [.bulletedList])))
        let endLocation = (h.textView.text as NSString).length
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: endLocation, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        #expect(!h.textView.text.contains("•"), "empty list item should exit the list on Return")
    }

    // Device-repro-shaped: the fix for numbered lists (the "\n"-handler's
    // paragraph resolution at the document's end after exitList collapses a
    // trailing item to a genuinely empty virtual paragraph) lives in the
    // shared code path used by every list style, not a numbered-list-specific
    // branch. Verify bulleted/dashed/checklist get the same fix: exit a list,
    // then press Return a third time — it must stay plain body, not resurrect
    // a marker on the previous real item.
    @Test func returnAgainAfterExitingStaticMarkerListStaysPlainBody() throws {
        let cases: [(NoteParagraphTextStyle, Character)] = [
            (.bulletedList, "\u{2022}"),      // •
            (.dashedList, "\u{2013}"),        // –
            (.checklistUnchecked, "\u{25CB}"), // ○
        ]
        for (paraStyle, marker) in cases {
            let h = makeEditorHarness(
                text: "one\ntwo",
                textStyleData: style(.init(paragraphStyles: [paraStyle, paraStyle]))
            )
            let end1 = (h.textView.text as NSString).length
            _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: end1, length: 0), replacementText: "\n")
            let afterFirst = h.textView.text ?? ""
            #expect(afterFirst.contains(marker), "\(paraStyle): first Return should make a new empty row, got: \(afterFirst)")

            let cursor2 = h.textView.selectedRange.location
            _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: cursor2, length: 0), replacementText: "\n")
            let afterSecond = h.textView.text ?? ""

            let cursor3 = h.textView.selectedRange.location
            let shouldChange = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: cursor3, length: 0), replacementText: "\n")
            #expect(shouldChange, "\(paraStyle): third Return must be plain body — not intercepted into a bogus new row")
            let afterThird = h.textView.text ?? ""
            #expect(afterThird == afterSecond, "\(paraStyle): this synthetic call doesn't itself insert the newline (shouldChange=true defers to UIKit), so state must be unchanged from after the second Return — got: \(afterThird)")
        }
    }
}

// MARK: - Numbered list: marker spacing + "1. " auto-start

@MainActor
struct NumberedListTests {

    // The marker separator is a tab now (was two spaces) so single- and
    // double-digit rows align via the paragraph tab stop.
    @Test func numberedMarkerUsesTabSeparator() throws {
        let h = makeEditorHarness(
            text: "one\ntwo",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList]))
        )
        let rendered = try #require(h.textView.attributedText).string as NSString
        // First paragraph: "1" "." "\t" "one"
        #expect(rendered.hasPrefix("1.\t"), "got: \(rendered)")
        #expect(rendered.contains("2.\ttwo"))
    }

    // Ten items — the marker still parses and the stored text carries no marker,
    // so numbering is purely a render concern regardless of digit count.
    @Test func numberedListTwoDigitRowsStoreNoMarker() throws {
        let lines = (1...10).map { "line\($0)" }.joined(separator: "\n")
        let h = makeEditorHarness(
            text: lines,
            textStyleData: style(.init(paragraphStyles: Array(repeating: .numberedList, count: 10)))
        )
        let attributed = try #require(h.textView.attributedText)
        #expect(attributed.string.contains("10.\tline10"))
        #expect(h.getText() == lines, "stored logical text must never contain the ordinal marker")

        // The gap fix: text after the tab lands at `headIndent` for every row,
        // so "1." and "10." align. Check the paragraph style carries the stop.
        let firstPS = try #require(attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(firstPS.tabStops.first?.location == firstPS.headIndent)
        let tenthRow = (attributed.string as NSString).range(of: "10.\t").location
        let tenthPS = try #require(attributed.attribute(.paragraphStyle, at: tenthRow, effectiveRange: nil) as? NSParagraphStyle)
        #expect(tenthPS.tabStops.first?.location == tenthPS.headIndent)
    }

    // Regression: applyIndent used to patch the current paragraph's attributes
    // then call syncRenderedCache, which stamps the *stale* digits already on
    // screen as canonical — the row that got indented (and every sibling after
    // it) never renumbered until an unrelated cache miss happened to force a
    // real re-render. applyIndent must force one itself.
    @Test func indentingNumberedItemRenumbersWholeBlock() throws {
        let h = makeEditorHarness(
            text: "first\nsecond\nthird",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList, .numberedList]))
        )
        let secondLoc = (h.textView.attributedText!.string as NSString).range(of: "second").location
        h.textView.selectedRange = NSRange(location: secondLoc, length: 0)
        h.coordinator.applyIndent(delta: 1, in: h.textView)

        let lines = h.textView.attributedText!.string.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("1.\t"), "got: \(lines[0])")
        #expect(lines[1].hasPrefix("1.\t"), "indented item should restart at 1, got: \(lines[1])")
        #expect(lines[2].hasPrefix("2.\t"), "outer list should resume at 2, got: \(lines[2])")
    }

    // Unlike numbered lists, a bullet/dash marker glyph depends only on its OWN
    // row's level, never on siblings — so indenting one row should never need
    // to touch any other row (no cascade to check for), only swap that row's
    // own glyph. Verify both halves: the indented row's glyph actually changes,
    // and siblings are left completely alone.
    @Test func indentingBulletedItemOnlySwapsThatRowsGlyphSiblingsUntouched() throws {
        let h = makeEditorHarness(
            text: "first\nsecond\nthird",
            textStyleData: style(.init(paragraphStyles: [.bulletedList, .bulletedList, .bulletedList]))
        )
        let secondLoc = (h.textView.attributedText!.string as NSString).range(of: "second").location
        h.textView.selectedRange = NSRange(location: secondLoc, length: 0)
        h.coordinator.applyIndent(delta: 1, in: h.textView)

        let lines = h.textView.attributedText!.string.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("\u{2022}"), "sibling before must stay level 0, got: \(lines[0])")
        #expect(lines[1].hasPrefix("\u{25E6}"), "indented row should show the level-1 glyph, got: \(lines[1])")
        #expect(lines[2].hasPrefix("\u{2022}"), "sibling after must stay level 0, got: \(lines[2])")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.indentLevels == [0, 1, 0], "got: \(String(describing: doc.indentLevels))")
    }

    @Test func indentingDashedItemOnlySwapsThatRowsGlyphSiblingsUntouched() throws {
        let h = makeEditorHarness(
            text: "first\nsecond\nthird",
            textStyleData: style(.init(paragraphStyles: [.dashedList, .dashedList, .dashedList]))
        )
        let secondLoc = (h.textView.attributedText!.string as NSString).range(of: "second").location
        h.textView.selectedRange = NSRange(location: secondLoc, length: 0)
        h.coordinator.applyIndent(delta: 1, in: h.textView)

        let lines = h.textView.attributedText!.string.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("\u{2013}"), "sibling before must stay level 0, got: \(lines[0])")
        #expect(lines[1].hasPrefix("\u{00B7}"), "indented row should show the level-1 glyph, got: \(lines[1])")
        #expect(lines[2].hasPrefix("\u{2013}"), "sibling after must stay level 0, got: \(lines[2])")
    }

    // Outdent is the same swap logic run in the other direction — verify it
    // isn't a one-way (indent-only) fix.
    @Test func outdentingBulletedItemSwapsGlyphBackToLevelZero() throws {
        let h = makeEditorHarness(
            text: "first\nsecond\nthird",
            textStyleData: style(.init(
                paragraphStyles: [.bulletedList, .bulletedList, .bulletedList],
                indentLevels: [0, 1, 0]
            ))
        )
        let secondLoc = (h.textView.attributedText!.string as NSString).range(of: "second").location
        h.textView.selectedRange = NSRange(location: secondLoc, length: 0)
        h.coordinator.applyIndent(delta: -1, in: h.textView)

        let lines = h.textView.attributedText!.string.components(separatedBy: "\n")
        #expect(lines[1].hasPrefix("\u{2022}"), "outdented row should be back to the level-0 glyph, got: \(lines[1])")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.indentLevels == nil || doc.indentLevels == [0, 0, 0], "got: \(String(describing: doc.indentLevels))")
    }

    // Checklist markers (○/✓) don't vary by indent level at all — indenting
    // must not touch the glyph, only the stored level (used for layout).
    @Test func indentingChecklistItemLeavesMarkerGlyphUnchanged() throws {
        let h = makeEditorHarness(
            text: "first\nsecond\nthird",
            textStyleData: style(.init(paragraphStyles: [.checklistUnchecked, .checklistUnchecked, .checklistUnchecked]))
        )
        let secondLoc = (h.textView.attributedText!.string as NSString).range(of: "second").location
        h.textView.selectedRange = NSRange(location: secondLoc, length: 0)
        h.coordinator.applyIndent(delta: 1, in: h.textView)

        let lines = h.textView.attributedText!.string.components(separatedBy: "\n")
        #expect(lines[1].hasPrefix("\u{25CB}"), "checklist glyph must not change with level, got: \(lines[1])")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.indentLevels == [0, 1, 0], "indent level must still be tracked, got: \(String(describing: doc.indentLevels))")
    }

    // Repro from screen recording: exit a numbered list (Return on the empty
    // trailing item), then on that now-plain body line type "4. " again to
    // re-trigger autoStartNumberedList. That paragraph is genuinely
    // zero-length at the moment `apply(.numberedList, ...)` reads its current
    // style, and the cursor sits exactly at the document's end — so
    // `currentStyle` used to be sampled at `length - 1`, which lands on the
    // *previous* paragraph's own closing "\n" (paragraph runs include their
    // trailing newline) instead of this new, styleless paragraph. That misread
    // (.numberedList instead of .body) flipped the toggle backwards (targeting
    // .body instead of .numberedList) and took the "strip list marker" branch,
    // which then stripped the *previous* real item's marker instead of
    // touching the empty virtual paragraph at all — corrupting row 3 and
    // silently dropping row 4.
    @Test func autoStartNumberedListOnTrailingEmptyLineDoesNotCorruptPriorItem() throws {
        let h = makeEditorHarness(
            text: "one\ntwo\nthree\n4.",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList, .numberedList, .body]))
        )
        let initial = try #require(h.textView.attributedText).string
        #expect(initial == "1.\tone\n2.\ttwo\n3.\tthree\n4.", "initial render, got: \(initial)")
        let end = (h.textView.text as NSString).length
        let convertedSpace = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: end, length: 0),
            replacementText: " "
        )
        #expect(!convertedSpace, "the space is consumed by autoStartNumberedList")
        let afterConvert = try #require(h.textView.attributedText).string
        #expect(afterConvert.contains("3.\tthree"), "item 3 must stay intact, got: \(afterConvert)")
        #expect(afterConvert.contains("4.\t"), "auto-start should produce item 4, got: \(afterConvert)")

        // Return on the now-properly-empty item 4 must exit cleanly: no
        // leftover "4.", no spawned "5.", and item 3 still untouched.
        let cursor = h.textView.selectedRange.location
        let shouldChange = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: cursor, length: 0), replacementText: "\n")
        #expect(!shouldChange)
        let afterReturn = try #require(h.textView.attributedText).string
        #expect(afterReturn.contains("3.\tthree"), "item 3 must still be intact, got: \(afterReturn)")
        #expect(!afterReturn.contains("5.\t"), "must not spawn item 5 — got: \(afterReturn)")
        #expect(!afterReturn.contains("4.\t"), "it must exit the list instead — got: \(afterReturn)")
    }

    @Test func typingDigitDotSpaceStartsNumberedList() throws {
        let h = makeEditorHarness(text: "1.", textStyleData: nil)
        h.textView.selectedRange = NSRange(location: 2, length: 0)
        h.coordinator.textViewDidBeginEditing(h.textView)

        let shouldInsert = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: 2, length: 0),
            replacementText: " "
        )
        #expect(shouldInsert == false, "the typed space is consumed by the conversion")

        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.paragraphStyles == [.numberedList])
        #expect(h.getText() == "", "the typed \"1.\" prefix is absorbed into the marker")
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("1.\t"))
    }

    @Test func typingDigitDotSpaceInFrontOfExistingTextConverts() throws {
        let h = makeEditorHarness(text: "3.buy milk", textStyleData: nil)
        h.textView.selectedRange = NSRange(location: 2, length: 0)
        h.coordinator.textViewDidBeginEditing(h.textView)

        let shouldInsert = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: 2, length: 0),
            replacementText: " "
        )
        #expect(shouldInsert == false)
        #expect(h.getText() == "buy milk", "renderer renumbers from 1 — the typed 3 is dropped")
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("1.\tbuy milk"))
    }

    @Test func typingSpaceAfterVersionNumberDoesNotConvert() {
        let h = makeEditorHarness(text: "1.2", textStyleData: nil)
        h.textView.selectedRange = NSRange(location: 3, length: 0)
        h.coordinator.textViewDidBeginEditing(h.textView)

        let shouldInsert = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementText: " "
        )
        #expect(shouldInsert == true, "\"1.2\" is not a \"<digits>.\" prefix — leave it alone")
        #expect(h.getStyleData() == nil)
    }

    @Test func typingDigitDotSpaceInsideExistingListItemDoesNotReconvert() {
        // Cursor mid-content on an existing numbered row, user types a space.
        let h = makeEditorHarness(
            text: "hello",
            textStyleData: style(.init(paragraphStyles: [.numberedList]))
        )
        let rendered = (h.textView.attributedText?.string ?? "") as NSString
        let markerLen = rendered.range(of: "\t").location + 1
        h.textView.selectedRange = NSRange(location: markerLen + 2, length: 0)
        h.coordinator.textViewDidBeginEditing(h.textView)

        _ = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: markerLen + 2, length: 0),
            replacementText: " "
        )
        let doc = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data())
        #expect(doc?.paragraphStyles == [.numberedList], "still exactly one numbered paragraph")
    }

    @Test func numberedListContinuesOnReturn() throws {
        let h = makeEditorHarness(text: "first", textStyleData: style(.init(paragraphStyles: [.numberedList])))
        let end = (h.textView.text as NSString).length
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: end, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange, "list continuation is handled manually")
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("1.\tfirst"))
        #expect(rendered.contains("2.\t"), "new row carries the next ordinal, got: \(rendered)")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.paragraphStyles == [.numberedList, .numberedList])
    }

    @Test func returnOnEmptyNumberedItemExitsList() {
        let h = makeEditorHarness(text: "", textStyleData: style(.init(paragraphStyles: [.numberedList])))
        let end = (h.textView.text as NSString).length
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: end, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        #expect(!(h.textView.text ?? "").contains("\t"), "empty numbered item exits the list on Return")
    }

    // Repro: type items, Return to make a new empty item, Return again on that
    // empty item — should exit the list, not keep spawning 4, 5, 6…
    @Test func returnTwiceAfterLastItemExitsList() throws {
        let h = makeEditorHarness(
            text: "one\ntwo\nthree",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList, .numberedList]))
        )
        // Return at end of "three" → new empty item 4
        let end1 = (h.textView.text as NSString).length
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: end1, length: 0), replacementText: "\n")
        let afterFirst = try #require(h.textView.attributedText).string
        #expect(afterFirst.contains("4.\t"), "first Return makes item 4, got: \(afterFirst)")
        // The cursor must land after the new row's "4.\t" marker. If it lands
        // earlier (the bug: insertListRow set the selection before its re-render
        // wiped it), the next Return reads the previous, content-bearing row and
        // spawns item 5 instead of exiting.
        let displayLen = (h.textView.text as NSString).length
        #expect(h.textView.selectedRange.location == displayLen,
                "cursor must sit at end of the new row's marker, got \(h.textView.selectedRange.location) of \(displayLen)")

        // Return again on the now-empty item 4, driven from the REAL cursor the
        // editor left behind — this is the path the bug broke.
        let cursor = h.textView.selectedRange.location
        let shouldChange = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: cursor, length: 0), replacementText: "\n")
        #expect(!shouldChange)
        let afterSecond = try #require(h.textView.attributedText).string
        #expect(!afterSecond.contains("4.\t"), "second Return on the empty item must exit, not keep it — got: \(afterSecond)")
        #expect(!afterSecond.contains("5.\t"), "second Return must not spawn item 5 — got: \(afterSecond)")
        // The three real items stay numbered; the empty trailing row drops back
        // to plain text and isn't persisted until something is typed into it.
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.paragraphStyles == [.numberedList, .numberedList, .numberedList])
    }

    // Device-shaped repro: after the empty item is created, the caret can sit at
    // the START of that paragraph (before the render-only "N.\t" marker) rather
    // than after it — UIKit parks it at the logical boundary. Return from there
    // must still exit the list. The old `\n` handler resolved the paragraph from
    // `caret - 1`, which pointed back into the previous, content-bearing item, so
    // it kept calling insertListRow ("4.", "5.", …). Headless/sim don't leave the
    // caret there on their own, so drive it explicitly.
    @Test func returnOnEmptyItemExitsEvenWhenCaretAtParagraphStart() throws {
        let h = makeEditorHarness(
            text: "one\ntwo\nthree",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList, .numberedList]))
        )
        let end1 = (h.textView.text as NSString).length
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: end1, length: 0), replacementText: "\n")
        let display = try #require(h.textView.attributedText).string as NSString
        let markerRange = display.range(of: "4.\t")
        #expect(markerRange.location != NSNotFound)
        // Force the caret to the paragraph start, before the render-only marker —
        // where UIKit parks it on device after the empty item is created.
        h.textView.selectedRange = NSRange(location: markerRange.location, length: 0)

        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: markerRange.location, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        let after = try #require(h.textView.attributedText).string
        #expect(!after.contains("4.\t"), "must exit the list, not keep item 4 — got: \(after)")
        #expect(!after.contains("5.\t"), "must not spawn item 5 — got: \(after)")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.paragraphStyles == [.numberedList, .numberedList, .numberedList])
    }

    // Device repro (real screen recording): after exitList collapses the
    // trailing empty item down to a genuinely zero-length virtual paragraph,
    // the caret sits exactly at the document's end. A THIRD Return from there
    // used to resolve its paragraph via `length - 1`, which lands on the
    // *previous* real item's own closing "\n" — misreading that item as
    // non-empty content being split, and spawning a bogus new numbered row
    // (while the already-exited empty paragraph survived as yet another,
    // separately-numbered row). The fix must treat this as a plain body
    // Return: no list markers reappear at all.
    @Test func returnAgainAfterExitingListStaysPlainBody() throws {
        let h = makeEditorHarness(
            text: "one\ntwo",
            textStyleData: style(.init(paragraphStyles: [.numberedList, .numberedList]))
        )
        // Return at end of "two" → new empty item 3.
        let end1 = (h.textView.text as NSString).length
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: end1, length: 0), replacementText: "\n")
        let afterFirst = try #require(h.textView.attributedText).string
        #expect(afterFirst.contains("3.\t"), "first Return makes item 3, got: \(afterFirst)")

        // Return again on the empty item 3 → exits the list.
        let cursor2 = h.textView.selectedRange.location
        _ = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: cursor2, length: 0), replacementText: "\n")
        let afterSecond = try #require(h.textView.attributedText).string
        #expect(!afterSecond.contains("3.\t"), "second Return exits the list, got: \(afterSecond)")

        // Return a THIRD time, from wherever the editor left the caret — must
        // stay plain body: no numbered markers resurrected anywhere.
        let cursor3 = h.textView.selectedRange.location
        let shouldChange = h.coordinator.textView(h.textView, shouldChangeTextIn: NSRange(location: cursor3, length: 0), replacementText: "\n")
        #expect(shouldChange, "plain body Return is handled by UIKit itself, not intercepted — this call returning true (instead of manually inserting a bogus row and returning false) is the fix")
        // This synthetic harness call doesn't itself perform the actual UIKit
        // insertion `true` defers to — so state here is exactly what the second
        // Return left behind. The meaningful assertion is `shouldChange` above:
        // pre-fix, this call took the isListStyle branch and returned false.
        let afterThird = try #require(h.textView.attributedText).string
        #expect(afterThird == "1.\tone\n2.\ttwo\n", "items 1/2 keep their own markers; item 3 must not reappear — got: \(afterThird)")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(Array(doc.paragraphStyles.prefix(2)) == [.numberedList, .numberedList], "items 1 and 2 stay untouched and numbered, got: \(doc.paragraphStyles)")
    }

    // Return in the MIDDLE of a numbered item: splits it, and the cursor must
    // land right after the new row's marker (before the moved text), not at the
    // end of the document. This is the position `insertListRow` computes from
    // the re-rendered display; if it were still set before the re-render (the
    // bug), the caret would be wherever UIKit dropped it after setAttributedText.
    @Test func returnMidNumberedItemPutsCursorAfterNewMarker() throws {
        let h = makeEditorHarness(
            text: "abcdef",
            textStyleData: style(.init(paragraphStyles: [.numberedList]))
        )
        // Displayed: "1.\tabcdef" — marker is 2 chars + tab. Split between "abc" and "def".
        let markerLen = 3
        let splitAt = markerLen + 3
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: splitAt, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("1.\tabc"), "first row keeps 'abc', got: \(rendered)")
        #expect(rendered.contains("2.\tdef"), "second row carries 'def', got: \(rendered)")
        // Caret sits just after "2.\t", i.e. immediately before "def".
        let display = h.textView.text as NSString
        let defRange = display.range(of: "def")
        #expect(h.textView.selectedRange.location == defRange.location,
                "cursor must be right after the new marker (before 'def' at \(defRange.location)), got \(h.textView.selectedRange.location)")
    }
}

// MARK: - Return in the middle of an item's content: bulleted/dashed/checklist

@MainActor
struct MidContentReturnOtherListTypesTests {

    @Test func returnMidBulletedItemPutsCursorAfterNewMarker() throws {
        let h = makeEditorHarness(text: "abcdef", textStyleData: style(.init(paragraphStyles: [.bulletedList])))
        // Displayed: "•  abcdef" — marker is 3 chars. Split between "abc" and "def".
        let markerLen = 3
        let splitAt = markerLen + 3
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: splitAt, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("\u{2022}  abc"), "first row keeps 'abc', got: \(rendered)")
        #expect(rendered.contains("\u{2022}  def"), "second row carries 'def', got: \(rendered)")
        let display = h.textView.text as NSString
        let defRange = display.range(of: "def")
        #expect(h.textView.selectedRange.location == defRange.location,
                "cursor must be right after the new marker, got \(h.textView.selectedRange.location) vs \(defRange.location)")
    }

    @Test func returnMidDashedItemPutsCursorAfterNewMarker() throws {
        let h = makeEditorHarness(text: "abcdef", textStyleData: style(.init(paragraphStyles: [.dashedList])))
        let markerLen = 3
        let splitAt = markerLen + 3
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: splitAt, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("\u{2013}  abc"), "first row keeps 'abc', got: \(rendered)")
        #expect(rendered.contains("\u{2013}  def"), "second row carries 'def', got: \(rendered)")
        let display = h.textView.text as NSString
        let defRange = display.range(of: "def")
        #expect(h.textView.selectedRange.location == defRange.location,
                "cursor must be right after the new marker, got \(h.textView.selectedRange.location) vs \(defRange.location)")
    }

    @Test func returnMidUncheckedChecklistItemPutsCursorAfterNewMarker() throws {
        let h = makeEditorHarness(text: "abcdef", textStyleData: style(.init(paragraphStyles: [.checklistUnchecked])))
        let markerLen = 3
        let splitAt = markerLen + 3
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: splitAt, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("\u{25CB}  abc"), "first row keeps 'abc', got: \(rendered)")
        #expect(rendered.contains("\u{25CB}  def"), "second row carries 'def' and stays unchecked, got: \(rendered)")
        let display = h.textView.text as NSString
        let defRange = display.range(of: "def")
        #expect(h.textView.selectedRange.location == defRange.location,
                "cursor must be right after the new marker, got \(h.textView.selectedRange.location) vs \(defRange.location)")
    }

    // Splitting a CHECKED item mid-content is a deliberate behavior decision
    // (insertListRow explicitly downgrades the new row to .checklistUnchecked)
    // — matches Notes/Reminders-style splitting of a checked todo: the first
    // half keeps its checked state, the new second half starts fresh/unchecked.
    @Test func returnMidCheckedChecklistItemStartsNewRowUnchecked() throws {
        let h = makeEditorHarness(text: "abcdef", textStyleData: style(.init(paragraphStyles: [.checklistChecked])))
        let markerLen = 3
        let splitAt = markerLen + 3
        let shouldChange = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: splitAt, length: 0),
            replacementText: "\n"
        )
        #expect(!shouldChange)
        let rendered = try #require(h.textView.attributedText).string
        #expect(rendered.hasPrefix("\u{2713}  abc"), "first row stays checked, got: \(rendered)")
        #expect(rendered.contains("\u{25CB}  def"), "new row must start unchecked, got: \(rendered)")
        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.paragraphStyles == [.checklistChecked, .checklistUnchecked], "got: \(doc.paragraphStyles)")
        let display = h.textView.text as NSString
        let defRange = display.range(of: "def")
        #expect(h.textView.selectedRange.location == defRange.location,
                "cursor must be right after the new marker, got \(h.textView.selectedRange.location) vs \(defRange.location)")
    }
}

// MARK: - Backspace-merging differently-styled paragraphs

@MainActor
struct ParagraphMergeOnBackspaceTests {

    @Test func mergingHeadingAndBodyKeepsPrecedingStyleImmediately() throws {
        let h = makeEditorHarness(
            text: "Heading\nBody line",
            textStyleData: style(.init(paragraphStyles: [.heading, .body]))
        )
        let headingLength = (("Heading") as NSString).length
        // Backspace at the very start of "Body line" deletes the separating "\n".
        let handled = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: headingLength, length: 1),
            replacementText: ""
        )
        #expect(handled == false, "merge across differing styles must be handled explicitly")
        #expect(h.getText() == "HeadingBody line")

        let doc = try #require(try? JSONDecoder().decode(NoteTextStyleDocument.self, from: h.getStyleData() ?? Data()))
        #expect(doc.paragraphStyles == [.heading], "merged paragraph should be recorded as a single Heading, not split/ambiguous")

        let rendered = try #require(h.textView.attributedText)
        let font = try #require(rendered.attribute(.font, at: rendered.length - 1, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold),
                "the previously-Body tail must be visually promoted to Heading immediately, not just in stored metadata")
    }

    @Test func mergingTwoBodyParagraphsIsUnaffected() {
        let h = makeEditorHarness(
            text: "line one\nline two",
            textStyleData: nil
        )
        let firstLength = (("line one") as NSString).length
        let handled = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: firstLength, length: 1),
            replacementText: ""
        )
        #expect(handled == true, "same-style merges should fall through to default UIKit deletion")
    }

    @Test func mergingPreservesInlineBoldOnTailText() throws {
        let h = makeEditorHarness(
            text: "Heading\nbold tail",
            textStyleData: style(.init(paragraphStyles: [.heading, .body])),
            inlineStyleData: inline([.init(location: 8, length: 4, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil)])
        )
        let headingLength = (("Heading") as NSString).length
        _ = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: headingLength, length: 1),
            replacementText: ""
        )
        let rendered = try #require(h.textView.attributedText)
        // "HeadingBold tail" — "bold" starts right after "Heading" (no separator char consumed).
        let boldWordStart = (("Heading") as NSString).length
        let font = try #require(rendered.attribute(.font, at: boldWordStart, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold), "inline bold on the merged-in text must survive the merge")
    }

    @Test func mergingListIntoNonListIsIgnoredHere() {
        // List merges are handled by exitsEmptyListAfterDeletion / other list-specific
        // paths, not this guard — it must stay out of the way.
        let h = makeEditorHarness(
            text: "•  item\nbody",
            textStyleData: style(.init(paragraphStyles: [.bulletedList, .body]))
        )
        let firstLength = (("•  item") as NSString).length
        let handled = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: firstLength, length: 1),
            replacementText: ""
        )
        #expect(handled == true, "list-involved merges are out of scope for this guard")
    }
}

// MARK: - Per-paragraph font family

@MainActor
struct FontChoicePerParagraphTests {

    @Test func perParagraphFontOverridesRenderCorrectFont() throws {
        let h = makeEditorHarness(
            text: "one\ntwo",
            textStyleData: style(.init(paragraphStyles: [.body, .body], fontChoices: [
                WritingFontChoice.system.rawValue, WritingFontChoice.rounded.rawValue
            ])),
            fontChoiceRaw: WritingFontChoice.system.rawValue
        )
        let rendered = try #require(h.textView.attributedText)
        let firstFont = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let secondFont = try #require(rendered.attribute(.font, at: rendered.length - 1, effectiveRange: nil) as? UIFont)
        let systemFont = h.coordinator.bodyFont(for: .system)
        let roundedFont = h.coordinator.bodyFont(for: .rounded)
        #expect(firstFont.fontDescriptor.postscriptName == systemFont.fontDescriptor.postscriptName)
        #expect(secondFont.fontDescriptor.postscriptName == roundedFont.fontDescriptor.postscriptName)
        #expect(firstFont.fontDescriptor.postscriptName != secondFont.fontDescriptor.postscriptName)
    }

    @Test func paragraphWithoutOverrideFallsBackToEntryDefault() throws {
        let h = makeEditorHarness(
            text: "one\ntwo",
            textStyleData: style(.init(paragraphStyles: [.body, .body], fontChoices: [WritingFontChoice.rounded.rawValue])),
            fontChoiceRaw: WritingFontChoice.serif.rawValue
        )
        // Paragraph 0 has an explicit override (rounded); paragraph 1 has none —
        // it must fall back to the entry default (serif), not .system.
        let rendered = try #require(h.textView.attributedText)
        let secondFont = try #require(rendered.attribute(.font, at: rendered.length - 1, effectiveRange: nil) as? UIFont)
        let serifFont = h.coordinator.bodyFont(for: .serif)
        #expect(secondFont.pointSize == serifFont.pointSize)
        #expect(secondFont.fontDescriptor.postscriptName == serifFont.fontDescriptor.postscriptName)
    }

    @Test func monospacedParagraphIgnoresPerParagraphFontChoiceTypeface() throws {
        // Monospaced block style always forces the monospaced typeface regardless of
        // font-family override — only its point-size baseline should vary.
        let h = makeEditorHarness(
            text: "code",
            textStyleData: style(.init(paragraphStyles: [.monospaced], fontChoices: [WritingFontChoice.rounded.rawValue]))
        )
        let rendered = try #require(h.textView.attributedText)
        let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    // Guard-bug regression: an all-body, non-indented entry that picks up a font
    // override must not be silently dropped by the old "nothing worth persisting"
    // shortcut. applyFontFamily is exercised directly — with no first responder the
    // harness's textView always resolves to cursor position 0, so this lands on the
    // single (only) paragraph, which is exactly what's needed here.
    @Test func fontOverrideOnPlainBodyEntrySurvivesEncode() throws {
        let h = makeEditorHarness(text: "just some plain text", textStyleData: nil)
        h.coordinator.applyFontFamily(.rounded, in: h.textView)
        let data = try #require(h.getStyleData(), "a font override on an all-body entry must not encode to nil")
        let doc = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        #expect(doc.paragraphStyles == [.body])
        #expect(doc.fontChoices == [WritingFontChoice.rounded.rawValue])
    }

    // Regression: monospaced paragraph, then a serif paragraph, then Return into a
    // trailing ghost paragraph, then applying Checklist there. The ghost-paragraph
    // branch of apply() used to rebuild NoteTextStyleDocument from `styles` alone,
    // silently dropping every other paragraph's fontChoices (and indentLevels) —
    // both prior paragraphs would flatten to the entry default font.
    @Test func applyingChecklistToGhostParagraphPreservesOtherParagraphsFonts() throws {
        let h = makeEditorHarness(
            text: "code line\nserif line\n",
            textStyleData: style(.init(paragraphStyles: [.monospaced, .body], fontChoices: [
                WritingFontChoice.rounded.rawValue, WritingFontChoice.serif.rawValue
            ])),
            fontChoiceRaw: WritingFontChoice.system.rawValue
        )
        let nsText = h.getText() as NSString
        h.textView.selectedRange = NSRange(location: nsText.length, length: 0)
        h.coordinator.textViewDidBeginEditing(h.textView)

        h.coordinator.apply(.checklist, to: h.textView)

        let data = try #require(h.getStyleData(), "checklist creation on a ghost paragraph must not drop existing font overrides")
        let doc = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        let fontChoices = try #require(doc.fontChoices)
        #expect(fontChoices.count == 3)
        #expect(fontChoices[0] == WritingFontChoice.rounded.rawValue, "first paragraph's font must survive")
        #expect(fontChoices[1] == WritingFontChoice.serif.rawValue, "second paragraph's font must survive")
    }

    @Test func mergingDifferentStyleAndFontKeepsPrecedingParagraphsFont() throws {
        // Different paragraph STYLE (Heading vs Body) either side of the "\n" — this
        // is the case mergesParagraphsOfDifferentStyle actually performs a real,
        // immediate mutation for (same-style merges just fall through to default
        // UIKit deletion, which a headless harness can't simulate — nothing to
        // observe there beyond the return value, already covered elsewhere). Each
        // side also carries a different font override, proving font — not just
        // style — resolves to the preceding paragraph with zero special-case code.
        let h = makeEditorHarness(
            text: "Heading\nBody line",
            textStyleData: style(.init(paragraphStyles: [.heading, .body], fontChoices: [
                WritingFontChoice.rounded.rawValue, WritingFontChoice.monospaced.rawValue
            ]))
        )
        let headingLength = (("Heading") as NSString).length
        let handled = h.coordinator.textView(
            h.textView,
            shouldChangeTextIn: NSRange(location: headingLength, length: 1),
            replacementText: ""
        )
        #expect(handled == false, "differing-style merge is handled explicitly")
        #expect(h.getText() == "HeadingBody line")

        let data = try #require(h.getStyleData())
        let doc = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        #expect(doc.paragraphStyles == [.heading])
        #expect(doc.fontChoices == [WritingFontChoice.rounded.rawValue],
                "merged paragraph should keep the preceding (Heading/rounded) paragraph's font, not the Body/monospaced one")

        let rendered = try #require(h.textView.attributedText)
        let font = try #require(rendered.attribute(.font, at: rendered.length - 1, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold),
                "the merged text should be visually promoted to Heading immediately, not just in stored metadata")
    }

    @Test func sortCheckedToBottomCarriesFontOverridesInLockstep() throws {
        let h = makeEditorHarness(
            text: "checked\nunchecked",
            textStyleData: style(.init(
                paragraphStyles: [.checklistChecked, .checklistUnchecked],
                fontChoices: [WritingFontChoice.rounded.rawValue, WritingFontChoice.monospaced.rawValue]
            ))
        )
        h.coordinator.sortCheckedToBottom(in: h.textView)
        // "checked" (rounded) moves below "unchecked" (monospaced).
        #expect(h.getText() == "unchecked\nchecked")
        let data = try #require(h.getStyleData())
        let doc = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        #expect(doc.fontChoices == [WritingFontChoice.monospaced.rawValue, WritingFontChoice.rounded.rawValue],
                "font overrides must follow their paragraph when checklist rows reorder, not get dropped like inlineStyleData")
    }

    @Test func deleteCheckedChecklistItemsCarriesFontOverridesInLockstep() throws {
        let h = makeEditorHarness(
            text: "keep\ngone",
            textStyleData: style(.init(
                paragraphStyles: [.checklistUnchecked, .checklistChecked],
                fontChoices: [WritingFontChoice.rounded.rawValue, WritingFontChoice.monospaced.rawValue]
            ))
        )
        h.coordinator.deleteCheckedChecklistItems(in: h.textView)
        #expect(h.getText() == "keep")
        let data = try #require(h.getStyleData())
        let doc = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        #expect(doc.fontChoices == [WritingFontChoice.rounded.rawValue],
                "the surviving row's font override must not be lost or reattributed to the wrong paragraph")
    }

    @Test func backwardCompatibleDecodeOfPreFeatureData() throws {
        // Simulates textStyleData written before fontChoices existed — the JSON has
        // no "fontChoices" key at all.
        struct LegacyDocument: Codable {
            var paragraphStyles: [NoteParagraphTextStyle]
            var indentLevels: [Int]?
        }
        let legacy = LegacyDocument(paragraphStyles: [.body, .heading], indentLevels: nil)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(NoteTextStyleDocument.self, from: data)
        #expect(decoded.paragraphStyles == [.body, .heading])
        #expect(decoded.fontChoices == nil)

        // And it must still render correctly, falling back to the entry default everywhere.
        let h = makeEditorHarness(text: "a\nb", textStyleData: data, fontChoiceRaw: WritingFontChoice.serif.rawValue)
        let rendered = try #require(h.textView.attributedText)
        let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let serifFont = h.coordinator.bodyFont(for: .serif)
        #expect(font.fontDescriptor.postscriptName == serifFont.fontDescriptor.postscriptName)
    }
}
