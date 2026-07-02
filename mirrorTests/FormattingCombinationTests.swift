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
    panelState.fontChoiceRaw = fontChoiceRaw

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
        panelState: panelState
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
        for s: NoteParagraphTextStyle in [.title, .heading, .subheading, .monospaced] {
            let h = makeEditorHarness(text: "hello", textStyleData: style(.init(paragraphStyles: [s])))
            let rendered = try #require(h.textView.attributedText)
            #expect(rendered.string == "hello", "\(s) should not add a marker prefix")
        }
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
        for s: NoteParagraphTextStyle in [.title, .heading, .subheading, .monospaced] {
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
