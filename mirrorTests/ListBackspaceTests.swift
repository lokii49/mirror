import Testing
import SwiftUI
import UIKit
@testable import mirror

// Backspace at the start of a list item. Synthetic text only.

@MainActor
private func makeListHarness(
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
