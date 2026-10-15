import Testing
import SwiftUI
import UIKit
@testable import mirror

/// The keyboard bar and the Aa panel draw a style's on/off state from two places: the editor's
/// `activeInlineStyles` binding and `FormattingPanelState`. An empty entry used to break both: B
/// pressed before the first character was dropped by the next re-render, and the empty-entry
/// refresh reset the state to off, so the first word came out plain.
@MainActor
struct FormattingActiveStateTests {
    private final class Box {
        var text = ""
        var textStyleData: Data?
        var inlineStyleData: Data?
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
        let panelState = FormattingPanelState()
    }

    private func makeEditor(_ box: Box) -> (NoteEditorTextView.Coordinator, UITextView) {
        let editor = NoteEditorTextView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            textStyleData: Binding(get: { box.textStyleData }, set: { box.textStyleData = $0 }),
            inlineStyleData: Binding(get: { box.inlineStyleData }, set: { box.inlineStyleData = $0 }),
            photoDataArray: Binding(get: { box.photos }, set: { box.photos = $0 }),
            command: Binding(get: { box.command }, set: { box.command = $0 }),
            commandRevision: Binding(get: { box.commandRevision }, set: { box.commandRevision = $0 }),
            isFocused: Binding(get: { box.isFocused }, set: { box.isFocused = $0 }),
            activeParagraphStyle: Binding(get: { box.activeParagraphStyle }, set: { box.activeParagraphStyle = $0 }),
            activeInlineStyles: Binding(get: { box.activeInlineStyles }, set: { box.activeInlineStyles = $0 }),
            showFormattingPanel: Binding(get: { box.showFormattingPanel }, set: { box.showFormattingPanel = $0 }),
            canUndo: Binding(get: { box.canUndo }, set: { box.canUndo = $0 }),
            canRedo: Binding(get: { box.canRedo }, set: { box.canRedo = $0 }),
            fontChoiceRaw: Binding(get: { box.fontChoiceRaw }, set: { box.fontChoiceRaw = $0 }),
            panelState: box.panelState,
            displayMode: .classic
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()
        coordinator.applyStyledText(to: textView, preservingSelection: false)
        return (coordinator, textView)
    }

    private func typingIsBold(_ textView: UITextView) -> Bool {
        (textView.typingAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
    }

    @Test func boldOnAnEmptyEntryShowsInTheBarAndThePanel() {
        let box = Box()
        let (coordinator, textView) = makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        #expect(typingIsBold(textView))
        #expect(box.activeInlineStyles.bold, "the bar's state must show B on")
        #expect(box.panelState.activeInlineStyles.bold, "the Aa panel's state must show B on")
    }

    @Test func boldOnAnEmptyEntrySurvivesARerender() {
        let box = Box()
        let (coordinator, textView) = makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        // Every SwiftUI update re-renders the editor; this used to rebuild the empty entry's
        // typing attributes without the bold.
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        #expect(typingIsBold(textView), "the first character typed must still come out bold")
        #expect(box.activeInlineStyles.bold == box.panelState.activeInlineStyles.bold)
    }

    @Test func turningBoldOffOnAnEmptyEntryShowsOffInBoth() {
        let box = Box()
        let (coordinator, textView) = makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        coordinator.toggleInlineStyle(.bold, in: textView)
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        #expect(!typingIsBold(textView))
        #expect(!box.activeInlineStyles.bold)
        #expect(!box.panelState.activeInlineStyles.bold)
    }

    @Test func italicAndBoldTogetherOnAnEmptyEntry() {
        let box = Box()
        let (coordinator, textView) = makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        coordinator.toggleInlineStyle(.italic, in: textView)
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        #expect(box.panelState.activeInlineStyles.bold && box.panelState.activeInlineStyles.italic)
        #expect(box.activeInlineStyles == box.panelState.activeInlineStyles)
    }
}
