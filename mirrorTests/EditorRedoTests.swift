import Testing
import SwiftUI
import UIKit
@testable import mirror

/// Redo after Undo (2026-11-14): inside Undo a value written to SwiftUI state can still read as
/// the old one, so the editor recorded the old document, took the restored one for an outside
/// change on the next update and cleared Redo. The store here holds writes back the same way.
@MainActor
struct EditorRedoTests {
    private final class Store {
        var text: String
        var styles: Data?
        var inline: Data?
        var photos: [Data] = []
        /// While set, writes land only on `flush()`, as SwiftUI state written during an update.
        var holdWrites = false
        private var pending: [() -> Void] = []
        init(text: String, inline: Data? = nil) { self.text = text; self.inline = inline }
        func write(_ apply: @escaping () -> Void) { if holdWrites { pending.append(apply) } else { apply() } }
        func flush() { pending.forEach { $0() }; pending.removeAll(); holdWrites = false }
    }

    private func harness(_ store: Store) -> (NoteEditorTextView.Coordinator, UITextView) {
        let editor = NoteEditorTextView(
            text: Binding(get: { store.text }, set: { v in store.write { store.text = v } }),
            textStyleData: Binding(get: { store.styles }, set: { v in store.write { store.styles = v } }),
            inlineStyleData: Binding(get: { store.inline }, set: { v in store.write { store.inline = v } }),
            photoDataArray: Binding(get: { store.photos }, set: { v in store.write { store.photos = v } }),
            command: .constant(nil), commandRevision: .constant(0), isFocused: .constant(false),
            activeParagraphStyle: .constant(.body), activeInlineStyles: .constant(InlineStyleSet()),
            showFormattingPanel: .constant(false), canUndo: .constant(false), canRedo: .constant(false),
            fontChoiceRaw: .constant(WritingFontChoice.system.rawValue), panelState: FormattingPanelState(),
            displayMode: .classic
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        textView.delegate = coordinator
        coordinator.applyStyledText(to: textView, preservingSelection: false)
        coordinator.noteOutsideChange(in: textView)
        return (coordinator, textView)
    }

    private func type(_ s: String, in textView: UITextView, _ coordinator: NoteEditorTextView.Coordinator) {
        let location = (textView.text as NSString).length
        let range = NSRange(location: location, length: 0)
        textView.selectedRange = range
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: s) {
            textView.textStorage.replaceCharacters(in: range, with: s)
            textView.selectedRange = NSRange(location: location + (s as NSString).length, length: 0)
            coordinator.textViewDidChange(textView)
        }
    }

    @Test func redoSurvivesTheUpdateAfterUndo() {
        let store = Store(text: "Walk")
        let (coordinator, textView) = harness(store)
        type(" home", in: textView, coordinator)
        #expect(store.text == "Walk home")
        #expect(coordinator.canUndoEdit)

        store.holdWrites = true
        coordinator.undoEdit(in: textView)
        store.flush()
        coordinator.noteOutsideChange(in: textView)   // the next updateUIView
        #expect(store.text == "Walk")
        #expect(coordinator.canRedoEdit, "Redo is still there after the update that follows Undo")

        store.holdWrites = true
        coordinator.redoEdit(in: textView)
        store.flush()
        coordinator.noteOutsideChange(in: textView)
        #expect(store.text == "Walk home")
        #expect(coordinator.canUndoEdit)
    }

    @Test func redoOfAPhotoSizeSurvivesToo() {
        let small = PhotoSizes.setting(stored: "small", atInlineOffset: 0, in: nil)
        let store = Store(text: inlinePhotoToken(at: 0))
        store.photos = [UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 70, height: 100))
        }.pngData()!]
        let (coordinator, textView) = harness(store)
        type("\n", in: textView, coordinator)          // the person has edited
        store.inline = small                            // a size chosen (an outside change)
        coordinator.noteOutsideChange(in: textView)

        store.holdWrites = true
        coordinator.undoEdit(in: textView)
        store.flush()
        coordinator.noteOutsideChange(in: textView)
        #expect(store.inline == nil)
        #expect(coordinator.canRedoEdit)

        store.holdWrites = true
        coordinator.redoEdit(in: textView)
        store.flush()
        coordinator.noteOutsideChange(in: textView)
        #expect(store.inline == small)
    }
    /// Backspace deletes a row's photo and the one left stores "thumbnail" (`keepingTiles`):
    /// Undo brings back both photos and no size, Redo the delete and the size.
    @Test func undoAndRedoOfAPhotoDeleteThatKeptATile() {
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 70, height: 100))
        }.pngData()!
        let start = "\(inlinePhotoToken(at: 0))\n\(inlinePhotoToken(at: 1))"
        let store = Store(text: start)
        store.photos = [portrait, portrait]
        let (coordinator, textView) = harness(store)
        let end = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: end, length: 0)
        let range = NSRange(location: end - 1, length: 1)
        #expect(!coordinator.textView(textView, shouldChangeTextIn: range, replacementText: ""), "the editor deletes the photo itself")
        coordinator.noteOutsideChange(in: textView)   // the update after the delete
        #expect(store.photos.count == 1)
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail])
        #expect(coordinator.canUndoEdit)

        store.holdWrites = true
        coordinator.undoEdit(in: textView)
        store.flush()
        coordinator.noteOutsideChange(in: textView)
        #expect(store.text == start)
        #expect(store.photos.count == 2)
        #expect(store.inline == nil)
        #expect(coordinator.canRedoEdit)
        #expect(!coordinator.canUndoEdit, "Undo added no step of its own")

        store.holdWrites = true
        coordinator.redoEdit(in: textView)
        store.flush()
        coordinator.noteOutsideChange(in: textView)
        #expect(store.photos.count == 1)
        #expect(PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline) == [0: PhotoSizes.thumbnail])
        #expect(coordinator.canUndoEdit)
    }
}
