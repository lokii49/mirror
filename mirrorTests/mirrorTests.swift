import Testing
import SwiftUI
import UIKit
@testable import mirror

// MARK: - InlineStyleSet

struct InlineStyleSetTests {

    @Test func defaultIsEmpty() {
        let set = InlineStyleSet()
        #expect(set.isEmpty)
        #expect(!set.contains(.bold))
        #expect(!set.contains(.italic))
        #expect(!set.contains(.underline))
        #expect(!set.contains(.strikethrough))
    }

    @Test func setTrueContainsTrue() {
        var set = InlineStyleSet()
        set.set(.bold, true)
        #expect(set.contains(.bold))
        #expect(!set.isEmpty)
    }

    @Test func setFalseContainsFalse() {
        var set = InlineStyleSet()
        set.set(.bold, true)
        set.set(.bold, false)
        #expect(!set.contains(.bold))
        #expect(set.isEmpty)
    }

    @Test func multipleStylesIndependent() {
        var set = InlineStyleSet()
        set.set(.bold, true)
        set.set(.italic, true)
        #expect(set.contains(.bold))
        #expect(set.contains(.italic))
        #expect(!set.contains(.underline))
        #expect(!set.contains(.strikethrough))
        #expect(!set.isEmpty)
    }

    @Test func allStylesActive() {
        var set = InlineStyleSet()
        set.set(.bold, true)
        set.set(.italic, true)
        set.set(.underline, true)
        set.set(.strikethrough, true)
        #expect(set.contains(.bold))
        #expect(set.contains(.italic))
        #expect(set.contains(.underline))
        #expect(set.contains(.strikethrough))
        #expect(!set.isEmpty)
    }

    @Test func clearOnePreservesOthers() {
        var set = InlineStyleSet()
        set.set(.bold, true)
        set.set(.italic, true)
        set.set(.bold, false)
        #expect(!set.contains(.bold))
        #expect(set.contains(.italic))
        #expect(!set.isEmpty)
    }

    @Test func equalityOnDefaultValues() {
        let a = InlineStyleSet()
        let b = InlineStyleSet()
        #expect(a == b)
    }

    @Test func equalityDiffersByStyle() {
        var a = InlineStyleSet()
        var b = InlineStyleSet()
        a.set(.bold, true)
        b.set(.italic, true)
        #expect(a != b)
    }
}

// MARK: - Inline style rendering

@MainActor
struct InlineStyleRenderingTests {

    @Test func strikethroughEndingAtChecklistBoundaryDoesNotStyleMarker() throws {
        var text = "Hello\nTask"
        var textStyleData: Data? = try JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: [.body, .checklistUnchecked],
            indentLevels: nil
        ))
        var inlineStyleData: Data? = try JSONEncoder().encode(InlineStyleDocument(ranges: [
            InlineStyleRange(
                location: 0,
                length: 6,
                bold: false,
                italic: false,
                underline: false,
                strikethrough: true,
                highlightIndex: nil
            )
        ]))
        var photos: [Data] = []
        var command: NoteTextCommand?
        var commandRevision = 0
        var isFocused = false
        var activeParagraphStyle: NoteParagraphTextStyle = .body
        var activeInlineStyles = InlineStyleSet()
        var showFormattingPanel = false
        var canUndo = false
        var canRedo = false
        var fontChoiceRaw = WritingFontChoice.system.rawValue

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
            fontChoiceRaw: Binding(get: { fontChoiceRaw }, set: { fontChoiceRaw = $0 }),
            panelState: FormattingPanelState(),
            displayMode: .classic
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()

        coordinator.applyStyledText(to: textView, preservingSelection: false)

        let rendered = try #require(textView.attributedText)
        #expect(rendered.string == "Hello\n○  Task")
        #expect(rendered.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) != nil)
        #expect(rendered.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) == nil)
        #expect(rendered.attribute(.strikethroughStyle, at: 7, effectiveRange: nil) == nil)
        #expect(rendered.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) == nil)
        #expect(rendered.attribute(.strikethroughStyle, at: 9, effectiveRange: nil) == nil)
    }
}

// MARK: - NoteTextCommand

@MainActor
struct NoteTextCommandTests {

    @Test func simpleCommandsEqual() {
        #expect(NoteTextCommand.checklist == .checklist)
        #expect(NoteTextCommand.bold == .bold)
        #expect(NoteTextCommand.body == .body)
    }

    @Test func highlightSameIndexEqual() {
        #expect(NoteTextCommand.highlight(index: 0) == .highlight(index: 0))
        #expect(NoteTextCommand.highlight(index: 4) == .highlight(index: 4))
        #expect(NoteTextCommand.highlight(index: nil) == .highlight(index: nil))
    }

    @Test func highlightDifferentIndexNotEqual() {
        #expect(NoteTextCommand.highlight(index: 0) != .highlight(index: 1))
        #expect(NoteTextCommand.highlight(index: 0) != .highlight(index: nil))
        #expect(NoteTextCommand.highlight(index: nil) != .highlight(index: 2))
    }

    @Test func distinctCommandsNotEqual() {
        #expect(NoteTextCommand.bold != .italic)
        #expect(NoteTextCommand.checklist != .bulletedList)
        #expect(NoteTextCommand.checkAllItems != .uncheckAllItems)
        #expect(NoteTextCommand.deleteCheckedItems != .sortCheckedToBottom)
    }
}

// MARK: - FormattingPanelState

struct FormattingPanelStateTests {

    @Test func initialState() {
        let state = FormattingPanelState()
        #expect(state.activeParagraphStyle == .body)
        #expect(state.activeInlineStyles.isEmpty)
        #expect(state.activeHighlightIndex == nil)
        #expect(state.onCommand == nil)
        #expect(state.onDismiss == nil)
    }

    @Test func setParagraphStyle() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .heading
        #expect(state.activeParagraphStyle == .heading)
        state.activeParagraphStyle = .checklistUnchecked
        #expect(state.activeParagraphStyle == .checklistUnchecked)
    }

    @Test func setHighlightIndex() {
        let state = FormattingPanelState()
        state.activeHighlightIndex = 2
        #expect(state.activeHighlightIndex == 2)
        state.activeHighlightIndex = nil
        #expect(state.activeHighlightIndex == nil)
    }

    @Test func onCommandCalled() {
        let state = FormattingPanelState()
        var received: NoteTextCommand?
        state.onCommand = { received = $0 }
        state.onCommand?(.bold)
        #expect(received == .bold)
    }

    @Test func onCommandHighlightToggle_clearWhenSameIndex() {
        let state = FormattingPanelState()
        var received: NoteTextCommand?
        state.onCommand = { received = $0 }

        // Simulate the toggle logic in highlightButton:
        // state.onCommand?(.highlight(index: isActive ? nil : index))
        state.activeHighlightIndex = 2
        let isActive = state.activeHighlightIndex == 2
        state.onCommand?(.highlight(index: isActive ? nil : 2))
        #expect(received == .highlight(index: nil))
    }

    @Test func onCommandHighlightToggle_setWhenDifferentIndex() {
        let state = FormattingPanelState()
        var received: NoteTextCommand?
        state.onCommand = { received = $0 }

        state.activeHighlightIndex = 1
        let isActive = state.activeHighlightIndex == 3
        state.onCommand?(.highlight(index: isActive ? nil : 3))
        #expect(received == .highlight(index: 3))
    }

    @Test func onDismissCalled() {
        let state = FormattingPanelState()
        var dismissed = false
        state.onDismiss = { dismissed = true }
        state.onDismiss?()
        #expect(dismissed)
    }

    // Bulk ops row visibility condition
    @Test func bulkOpsCondition_trueForChecklistStyles() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .checklistUnchecked
        let shouldShow = state.activeParagraphStyle == .checklistUnchecked
            || state.activeParagraphStyle == .checklistChecked
        #expect(shouldShow)
    }

    @Test func bulkOpsCondition_trueForChecked() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .checklistChecked
        let shouldShow = state.activeParagraphStyle == .checklistUnchecked
            || state.activeParagraphStyle == .checklistChecked
        #expect(shouldShow)
    }

    @Test func bulkOpsCondition_falseForNonChecklist() {
        let state = FormattingPanelState()
        for style: NoteParagraphTextStyle in [.body, .title, .heading, .subheading, .monospaced, .bulletedList, .dashedList, .numberedList] {
            state.activeParagraphStyle = style
            let shouldShow = state.activeParagraphStyle == .checklistUnchecked
                || state.activeParagraphStyle == .checklistChecked
            #expect(!shouldShow, "bulk ops must not show for \(style)")
        }
    }

    // Checklist button active condition (toolRow)
    @Test func checklistButtonActive_unchecked() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .checklistUnchecked
        let isActive = state.activeParagraphStyle == .checklistUnchecked
            || state.activeParagraphStyle == .checklistChecked
        #expect(isActive)
    }

    @Test func checklistButtonActive_checked() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .checklistChecked
        let isActive = state.activeParagraphStyle == .checklistUnchecked
            || state.activeParagraphStyle == .checklistChecked
        #expect(isActive)
    }

    @Test func checklistButtonInactive_body() {
        let state = FormattingPanelState()
        let isActive = state.activeParagraphStyle == .checklistUnchecked
            || state.activeParagraphStyle == .checklistChecked
        #expect(!isActive)
    }

    // listIsActive equivalent logic for all list types
    @Test func listIsActive_bulletedList() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .bulletedList
        #expect(state.activeParagraphStyle == .bulletedList)
        #expect(state.activeParagraphStyle != .dashedList)
        #expect(state.activeParagraphStyle != .numberedList)
    }

    @Test func listIsActive_onlyOneListAtATime() {
        let state = FormattingPanelState()
        state.activeParagraphStyle = .numberedList
        let bulletActive = state.activeParagraphStyle == .bulletedList
        let dashedActive = state.activeParagraphStyle == .dashedList
        let numberedActive = state.activeParagraphStyle == .numberedList
        #expect(!bulletActive)
        #expect(!dashedActive)
        #expect(numberedActive)
    }
}

// MARK: - strippedWordCount

struct WordCountTests {

    @Test func emptyString() {
        #expect(strippedWordCount("") == 0)
    }

    @Test func singleWord() {
        #expect(strippedWordCount("hello") == 1)
    }

    @Test func multipleWords() {
        #expect(strippedWordCount("hello world today") == 3)
    }

    @Test func leadingAndTrailingSpaces() {
        #expect(strippedWordCount("  hello world  ") == 2)
    }

    @Test func multipleSpacesBetweenWords() {
        #expect(strippedWordCount("one   two   three") == 3)
    }

    @Test func newlineSeparatedWords() {
        #expect(strippedWordCount("line one\nline two") == 4)
    }

    @Test func stripsPhotoToken_countsSurroundingWords() {
        let text = "before [[mirror-photo-0]] after"
        #expect(strippedWordCount(text) == 2)
    }

    @Test func stripsMultiplePhotoTokens() {
        let text = "word [[mirror-photo-0]] another [[mirror-photo-1]] end"
        #expect(strippedWordCount(text) == 3)
    }

    @Test func photoTokenOnlyText_zeroWords() {
        let text = "[[mirror-photo-0]]"
        #expect(strippedWordCount(text) == 0)
    }

    @Test func legacyPhotoToken() {
        let text = "before [[mirror-photo]] after"
        #expect(strippedWordCount(text) == 2)
    }
}

// MARK: - inlinePhotoToken helpers

struct PhotoTokenTests {

    @Test func tokenAtIndex0() {
        #expect(inlinePhotoToken(at: 0) == "[[mirror-photo-0]]")
    }

    @Test func tokenAtIndex3() {
        #expect(inlinePhotoToken(at: 3) == "[[mirror-photo-3]]")
    }

    @Test func parseIndexFromToken() {
        #expect(inlinePhotoIndex(from: "[[mirror-photo-0]]") == 0)
        #expect(inlinePhotoIndex(from: "[[mirror-photo-2]]") == 2)
    }

    @Test func parseLegacyToken() {
        #expect(inlinePhotoIndex(from: "[[mirror-photo]]") == 0)
    }

    @Test func parseInvalidReturnsNil() {
        #expect(inlinePhotoIndex(from: "[[not-a-photo]]") == nil)
        #expect(inlinePhotoIndex(from: "") == nil)
        #expect(inlinePhotoIndex(from: "[[mirror-photo-abc]]") == nil)
    }

    @Test func allPhotoTokensFindsAll() {
        let text = "a [[mirror-photo-0]] b [[mirror-photo-1]] c"
        let tokens = allPhotoTokens(in: text)
        #expect(tokens.count == 2)
        #expect(tokens[0].index == 0)
        #expect(tokens[1].index == 1)
    }

    @Test func allPhotoTokensEmptyOnPlainText() {
        let tokens = allPhotoTokens(in: "no tokens here")
        #expect(tokens.isEmpty)
    }
}

// MARK: - NoteParagraphTextStyle raw values

struct ParagraphStyleRawValueTests {

    @Test func rawValuesMatchCaseNames() {
        #expect(NoteParagraphTextStyle.body.rawValue == "body")
        #expect(NoteParagraphTextStyle.title.rawValue == "title")
        #expect(NoteParagraphTextStyle.heading.rawValue == "heading")
        #expect(NoteParagraphTextStyle.subheading.rawValue == "subheading")
        #expect(NoteParagraphTextStyle.monospaced.rawValue == "monospaced")
        #expect(NoteParagraphTextStyle.checklistUnchecked.rawValue == "checklistUnchecked")
        #expect(NoteParagraphTextStyle.checklistChecked.rawValue == "checklistChecked")
        #expect(NoteParagraphTextStyle.bulletedList.rawValue == "bulletedList")
        #expect(NoteParagraphTextStyle.dashedList.rawValue == "dashedList")
        #expect(NoteParagraphTextStyle.numberedList.rawValue == "numberedList")
    }

    @Test func roundTripsViaRawValue() {
        for style: NoteParagraphTextStyle in [.body, .title, .heading, .subheading, .monospaced,
                                              .checklistUnchecked, .checklistChecked,
                                              .bulletedList, .dashedList, .numberedList] {
            let decoded = NoteParagraphTextStyle(rawValue: style.rawValue)
            #expect(decoded == style)
        }
    }
}
