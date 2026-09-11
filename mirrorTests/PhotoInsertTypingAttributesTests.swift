import Testing
import SwiftUI
import UIKit
@testable import mirror

/// A real bug, found live (not from the audit doc): attach a photo, then
/// keep typing — the newly typed text rendered small and black instead of
/// the entry's real body style, until the next full re-render papered over
/// it. Root cause: `insertPhotoToken(at:in:)` called `applyStyledText`
/// (which recomputes typing attributes at its end) *before* moving the
/// cursor to its post-insert position — so typing attributes were computed
/// against the stale, pre-insert cursor location and never recomputed after
/// the move. `photoAttachmentString`'s attachment run carries no `.font` /
/// `.foregroundColor` of its own, so with nothing ever computed correctly
/// for the real position, UIKit fell back to its own default typing
/// attributes instead of this entry's themed body style.
///
/// `encodedTextStyleData(from:)` (checked, not assumed) derives everything
/// from the custom `paragraphStyleAttribute`/`fontChoiceAttribute` keys, not
/// raw `.font`/`.foregroundColor` — so this was cosmetic, not a data
/// integrity bug: the paragraph still persisted as `.body` correctly. Still
/// a real, visible defect worth a direct test, since the manual UI-test
/// route (mirrorUITests) was unusable when this was found — the simulator's
/// XCTRunner launch was failing under machine load in the 100s.
struct PhotoInsertTypingAttributesTests {
    /// A tiny (1x1) but genuinely decodable PNG — `photoAttachmentString`
    /// guards on `UIImage(data:)` succeeding, so empty `Data()` wouldn't
    /// exercise the real path.
    private static let onePixelPNG: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.pngData()!
    }()

    private func makeCoordinator(text: String, photoData: [Data]) -> (coordinator: NoteEditorTextView.Coordinator, textView: UITextView) {
        let view = NoteEditorTextView(
            text: .constant(text),
            textStyleData: .constant(nil),
            inlineStyleData: .constant(nil),
            photoDataArray: .constant(photoData),
            command: .constant(nil),
            commandRevision: .constant(0),
            isFocused: .constant(false),
            activeParagraphStyle: .constant(.body),
            activeInlineStyles: .constant(InlineStyleSet()),
            showFormattingPanel: .constant(false),
            canUndo: .constant(false),
            canRedo: .constant(false),
            fontChoiceRaw: .constant(WritingFontChoice.system.rawValue),
            panelState: FormattingPanelState(),
            displayMode: .classic,
            onPhotoTapped: nil
        )
        let coordinator = NoteEditorTextView.Coordinator(parent: view)
        let textView = UITextView()
        textView.attributedText = NSAttributedString(string: text)
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        return (coordinator, textView)
    }

    @Test @MainActor func typingAttributesAfterPhotoAppendedAtEndMatchBodyStyle() {
        let text = "Some journal text"
        let (coordinator, textView) = makeCoordinator(text: text, photoData: [Self.onePixelPNG])

        coordinator.apply(.photo(index: 0), to: textView)

        let body = coordinator.bodyAttributes
        let typing = textView.typingAttributes
        #expect((typing[.foregroundColor] as? UIColor) == (body[.foregroundColor] as? UIColor),
                "Typing color after an appended photo must match the entry's body style, not UIKit's black-text default")
        #expect((typing[.font] as? UIFont)?.pointSize == (body[.font] as? UIFont)?.pointSize,
                "Typing font size after an appended photo must match the entry's body size, not UIKit's small default")
    }
}
