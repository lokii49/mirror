import Testing
import SwiftUI
import UIKit
@testable import mirror

/// What a full editor re-render costs in an entry with real-size photos: a paragraph-style
/// command (re-renders the whole document, like list Return or a checklist tap) followed by the
/// draw that decodes the photo attachments. `KeystrokeCostTests` uses 1-pixel photos and can't
/// see this. Synthetic images and text only. Timings are attached to the result; the only
/// assertion is a generous ceiling.
@MainActor
struct PhotoRenderCostTests {
    /// A 4032×3024 JPEG (a 12 MP phone photo) with noise, so it compresses like a real one.
    private static let photo: Data = {
        let size = CGSize(width: 4032, height: 3024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            var generator = SystemRandomNumberGenerator()
            for y in stride(from: 0, to: Int(size.height), by: 48) {
                for x in stride(from: 0, to: Int(size.width), by: 48) {
                    UIColor(hue: CGFloat.random(in: 0...1, using: &generator), saturation: 0.5,
                            brightness: CGFloat.random(in: 0.3...0.9, using: &generator), alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 48, height: 48))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.85)!
    }()

    @Test func reRenderWithThreeFullSizePhotos() throws {
        let lines = ["Morning walk by the river.", inlinePhotoToken(at: 0), "Lunch with the team.",
                     inlinePhotoToken(at: 1), "Evening, finally some quiet.", inlinePhotoToken(at: 2), "Notes for tomorrow."]
        var text = lines.joined(separator: "\n")
        var styles: Data? = nil, inline: Data? = nil, photos = Array(repeating: Self.photo, count: 3)
        var command: NoteTextCommand?, revision = 0, focused = false, active: NoteParagraphTextStyle = .body
        var activeInline = InlineStyleSet(), panel = false, canUndo = false, canRedo = false, font = WritingFontChoice.system.rawValue
        let editor = NoteEditorTextView(
            text: Binding(get: { text }, set: { text = $0 }),
            textStyleData: Binding(get: { styles }, set: { styles = $0 }),
            inlineStyleData: Binding(get: { inline }, set: { inline = $0 }),
            photoDataArray: Binding(get: { photos }, set: { photos = $0 }),
            command: Binding(get: { command }, set: { command = $0 }),
            commandRevision: Binding(get: { revision }, set: { revision = $0 }),
            isFocused: Binding(get: { focused }, set: { focused = $0 }),
            activeParagraphStyle: Binding(get: { active }, set: { active = $0 }),
            activeInlineStyles: Binding(get: { activeInline }, set: { activeInline = $0 }),
            showFormattingPanel: Binding(get: { panel }, set: { panel = $0 }),
            canUndo: Binding(get: { canUndo }, set: { canUndo = $0 }),
            canRedo: Binding(get: { canRedo }, set: { canRedo = $0 }),
            fontChoiceRaw: Binding(get: { font }, set: { font = $0 }),
            panelState: FormattingPanelState(),
            displayMode: .classic
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 2400))
        coordinator.applyStyledText(to: textView, preservingSelection: false)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: textView.bounds, format: format)
        func draw() { _ = renderer.image { ctx in textView.layer.render(in: ctx.cgContext) } }
        draw()   // first draw: decoding is expected once

        func now() -> Double { CFAbsoluteTimeGetCurrent() * 1000 }
        var command_ms = 0.0, draw_ms = 0.0
        let rounds = 6
        for n in 0..<rounds {
            textView.selectedRange = NSRange(location: 2, length: 0)   // first line
            var mark = now()
            coordinator.apply(n % 2 == 0 ? .heading : .body, to: textView)
            command_ms += now() - mark
            mark = now()
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            draw()
            draw_ms += now() - mark
        }
        // Control: the same draw with nothing re-rendered (attachments already decoded).
        var control_ms = 0.0
        for _ in 0..<rounds {
            let mark = now()
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            draw()
            control_ms += now() - mark
        }
        let line = String(format: "re-render with 3 × 12 MP photos: command %.1f ms + layout/draw %.1f ms = %.1f ms per re-render; control draw without re-render %.1f ms; re-render cost over control %.1f ms (avg of %d)\n",
                          command_ms / Double(rounds), draw_ms / Double(rounds), (command_ms + draw_ms) / Double(rounds),
                          control_ms / Double(rounds), (command_ms + draw_ms - control_ms) / Double(rounds), rounds)
        print("PHOTO_RENDER_COST " + line)
        Attachment.record(line, named: "photo-render-cost.txt")
        #expect((command_ms + draw_ms) / Double(rounds) < 5_000)
    }
}
