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
    final class Box {
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

    static func makeEditor(_ box: Box) -> (NoteEditorTextView.Coordinator, UITextView) {
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
        let (coordinator, textView) = Self.makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        #expect(typingIsBold(textView))
        #expect(box.activeInlineStyles.bold, "the bar's state must show B on")
        #expect(box.panelState.activeInlineStyles.bold, "the Aa panel's state must show B on")
    }

    @Test func boldOnAnEmptyEntrySurvivesARerender() {
        let box = Box()
        let (coordinator, textView) = Self.makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        // Every SwiftUI update re-renders the editor; this used to rebuild the empty entry's
        // typing attributes without the bold.
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        #expect(typingIsBold(textView), "the first character typed must still come out bold")
        #expect(box.activeInlineStyles.bold == box.panelState.activeInlineStyles.bold)
    }

    @Test func turningBoldOffOnAnEmptyEntryShowsOffInBoth() {
        let box = Box()
        let (coordinator, textView) = Self.makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        coordinator.toggleInlineStyle(.bold, in: textView)
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        #expect(!typingIsBold(textView))
        #expect(!box.activeInlineStyles.bold)
        #expect(!box.panelState.activeInlineStyles.bold)
    }

    @Test func italicAndBoldTogetherOnAnEmptyEntry() {
        let box = Box()
        let (coordinator, textView) = Self.makeEditor(box)
        coordinator.toggleInlineStyle(.bold, in: textView)
        coordinator.toggleInlineStyle(.italic, in: textView)
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        #expect(box.panelState.activeInlineStyles.bold && box.panelState.activeInlineStyles.italic)
        #expect(box.activeInlineStyles == box.panelState.activeInlineStyles)
    }
}

/// Checklist sorting: a checked item moves to the bottom of its own list and the caret goes with it.
@MainActor
struct ChecklistSortCaretTests {
    @Test func sortKeepsTheCaretInTheRowThatMoved() throws {
        let box = FormattingActiveStateTests.Box()
        box.text = "Milk\nEggs\nBread"
        box.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.checklistChecked, .checklistUnchecked, .checklistUnchecked]))
        let (coordinator, textView) = FormattingActiveStateTests.makeEditor(box)
        // Caret inside "Milk" (the checked first row), after its marker.
        let shown = textView.text as NSString
        let milk = shown.range(of: "Milk")
        textView.selectedRange = NSRange(location: milk.location + 2, length: 0)
        coordinator.sortCheckedToBottom(in: textView)
        #expect(box.text == "Eggs\nBread\nMilk")
        let after = textView.text as NSString
        let moved = after.range(of: "Milk")
        #expect(textView.selectedRange.location == moved.location + 2, "the caret must stay in Milk, now the last row")
    }
}

/// The checklist marker's spacer is kerned so text clears the drawn circle; nothing else may be.
/// Typed text inherited the kern once ("t e s t").
@MainActor
struct ChecklistMarkerSpacingTests {
    @Test func onlyTheMarkerSpacerIsKerned() throws {
        let box = FormattingActiveStateTests.Box()
        box.text = "test"
        box.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.checklistUnchecked]))
        let (_, rendered) = FormattingActiveStateTests.makeEditor(box)
        let spacing = ChecklistMarkerSpacing()
        let storage = NSTextStorage()
        storage.delegate = spacing
        storage.setAttributedString(rendered.attributedText)
        // A character typed with the spacer's kern in its typing attributes.
        let typed = NSAttributedString(string: "s", attributes: [.kern: 14.0, .font: UIFont.preferredFont(forTextStyle: .body)])
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: typed)
        let marker = 3   // "○  "
        #expect(storage.attribute(.kern, at: marker - 1, effectiveRange: nil) != nil, "the marker's spacer is kerned")
        for i in marker..<storage.length {
            #expect(storage.attribute(.kern, at: i, effectiveRange: nil) == nil, "text at \(i) must not be kerned")
        }
    }
}

/// Return and the checklist button behave as in Notes.
@MainActor
struct ChecklistNotesBehaviourTests {
    private func editor(_ rows: [(String, NoteParagraphTextStyle)]) throws -> (FormattingActiveStateTests.Box, NoteEditorTextView.Coordinator, UITextView) {
        let box = FormattingActiveStateTests.Box()
        box.text = rows.map(\.0).joined(separator: "\n")
        box.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: rows.map(\.1)))
        let (c, tv) = FormattingActiveStateTests.makeEditor(box)
        return (box, c, tv)
    }

    private func styles(_ box: FormattingActiveStateTests.Box) -> [NoteParagraphTextStyle] {
        (try? JSONDecoder().decode(NoteTextStyleDocument.self, from: box.textStyleData ?? Data()))?.paragraphStyles ?? []
    }

    private func pressReturn(at location: Int, _ c: NoteEditorTextView.Coordinator, _ tv: UITextView) {
        tv.selectedRange = NSRange(location: location, length: 0)
        if c.textView(tv, shouldChangeTextIn: NSRange(location: location, length: 0), replacementText: "\n") {
            tv.textStorage.replaceCharacters(in: NSRange(location: location, length: 0), with: "\n")
            c.textViewDidChange(tv)
        }
    }

    @Test func returnAtTheStartOfACheckedItemAddsAnEmptyItemAboveAndKeepsTheCheck() throws {
        let (box, c, tv) = try editor([("Milk", .checklistUnchecked), ("Bread", .checklistChecked)])
        let bread = (tv.text as NSString).range(of: "Bread")
        pressReturn(at: bread.location, c, tv)
        #expect(box.text == "Milk\n\nBread")
        #expect(styles(box) == [.checklistUnchecked, .checklistUnchecked, .checklistChecked])
        let after = (tv.text as NSString).range(of: "Bread")
        #expect(tv.selectedRange.location == after.location, "the caret stays at the start of Bread")
    }

    @Test func returnAtTheEndOfACheckedItemAddsAnUncheckedItemBelow() throws {
        let (box, c, tv) = try editor([("Bread", .checklistChecked)])
        let bread = (tv.text as NSString).range(of: "Bread")
        pressReturn(at: NSMaxRange(bread), c, tv)
        #expect(box.text == "Bread\n")
        #expect(styles(box).prefix(2) == [.checklistChecked, .checklistUnchecked])
    }

    @Test func returnOnAnEmptyItemEndsTheList() throws {
        let (box, c, tv) = try editor([("Milk", .checklistUnchecked), ("", .checklistUnchecked)])
        pressReturn(at: (tv.text as NSString).length, c, tv)
        // The stored styles may drop a trailing body row; what matters is that no second item is left.
        #expect(styles(box).filter { $0 == .checklistUnchecked || $0 == .checklistChecked }.count == 1, "the empty item becomes body text")
        #expect(!(tv.text ?? "").hasSuffix("○  "), "no empty circle is left")
    }

    /// A body line typed after leaving a list, between two lists: the button turns it into an
    /// item (its line break still carried a checklist style, so it read as one and turned off).
    @Test func checklistButtonOnABodyLineBetweenListsMakesItAnItem() throws {
        let (box, c, tv) = try editor([("Item 4", .checklistUnchecked), ("Hello here", .body), ("Item 2", .checklistChecked)])
        let hello = (tv.text as NSString).range(of: "Hello here")
        // The line break of "Hello here" carrying the next row's style, as Return leaves it.
        if let key = tv.textStorage.attributes(at: 0, effectiveRange: nil).keys.first(where: { $0.rawValue == "mirror.paragraphStyle" }) {
            tv.textStorage.addAttribute(key, value: NoteParagraphTextStyle.checklistChecked.rawValue, range: NSRange(location: NSMaxRange(hello), length: 1))
        }
        c.lastKnownCursorLocation = NSMaxRange(hello)
        c.apply(.checklist, to: tv)
        #expect(styles(box) == [.checklistUnchecked, .checklistUnchecked, .checklistChecked])
        let after = (tv.text as NSString).range(of: "Hello here")
        #expect(tv.selectedRange.location == NSMaxRange(after), "the caret stays at the end of Hello here")
    }
}

@MainActor
struct ChecklistBackspaceTests {
    /// Deleting the last letter keeps the empty item; a Backspace on the empty item makes it body.
    @Test func deletingTheLastLetterKeepsTheCircle() throws {
        let box = FormattingActiveStateTests.Box()
        box.text = "Milk\nA"
        box.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.checklistUnchecked, .checklistUnchecked]))
        let (c, tv) = FormattingActiveStateTests.makeEditor(box)
        let a = (tv.text as NSString).range(of: "A", options: .backwards)
        let delete = NSRange(location: a.location, length: 1)
        if c.textView(tv, shouldChangeTextIn: delete, replacementText: "") {
            tv.textStorage.replaceCharacters(in: delete, with: "")
            c.textViewDidChange(tv)
        }
        #expect((tv.text ?? "").hasSuffix("○  "), "the empty item keeps its circle. Got: \(tv.text ?? "")")
    }
}
