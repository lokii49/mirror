import Testing
import SwiftUI
import UIKit
@testable import mirror

/// Attaching a photo goes through `textWithInlinePhotoToken(_:at:)` (WriteView+Photos), and text
/// typed after it must keep the entry's body style. The editor's old `.photo(index:)` command,
/// which only tests ever sent, was removed as dead code (backlog E); its test went with it.
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

    // Real user report: attaching a photo to a BLANK entry. WriteView+Photos.handlePickedPhoto
    // calls the free function textWithInlinePhotoToken(_:at:) directly. On an empty entry that function returns *just* the
    // bare token with no trailing newline, so the photo attachment ends up
    // as the very last character with nothing typed after it. Neither UIKit's
    // own typing-attributes-on-selection-change inheritance nor our
    // updateTypingAttributes (which deliberately no-ops when the cursor sits
    // past the end of the text, to avoid stomping attrs the format panel just
    // set) has any real text run to read a font/color from — so whatever the
    // user types next silently falls back to UIKit's own tiny default.
    @Test @MainActor func blankEntryPhotoAttachLeavesAttachmentRunWithRealFontAndColor() throws {
        let index = 0
        let text = textWithInlinePhotoToken("", at: index)
        let (coordinator, textView) = makeCoordinator(text: text, photoData: [Self.onePixelPNG])

        coordinator.applyStyledText(to: textView, preservingSelection: false)

        let rendered = try #require(textView.attributedText)
        #expect(rendered.length == 1, "a bare-token blank-entry attach renders as a single attachment character, nothing after it")
        let body = coordinator.bodyAttributes
        let attachmentFont = rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let attachmentColor = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(attachmentFont?.pointSize == (body[.font] as? UIFont)?.pointSize,
                "the attachment run itself must carry a real font — it's the only thing a cursor placed right after it can inherit from")
        #expect(attachmentColor == (body[.foregroundColor] as? UIColor),
                "the attachment run itself must carry the real body color, not leave it unset")
    }
}
