import Testing
import SwiftUI
import UIKit
@testable import mirror

/// What one keystroke costs in a long, styled entry, stage by stage: the delegate check, UIKit's
/// insert, `textViewDidChange` (reads the text and both style documents back), the SwiftUI update
/// pass (`updateUIView`: outside-change check, logical/display comparison, cached render), and
/// `WriteViewModel`'s word count. Synthetic text only. The breakdown is attached to the test
/// result (`xcresulttool export attachments`); the only assertion is a generous ceiling.
@MainActor
struct KeystrokeCostTests {
    private static let onePixelPNG: Data = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
        UIColor.gray.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }.pngData()!

    private struct Entry {
        var text: String
        var styles: Data?
        var inline: Data?
        var photos: [Data]
    }

    /// Headings, body, bulleted and checklist items, bold every few paragraphs, three photos.
    private func makeEntry(approximateChars: Int) -> Entry {
        let sentences = [
            "Walked to the market early and the bread was still warm from the oven.",
            "Called about the lease again and nobody picked up the phone.",
            "Finished the second chapter and made notes on what to change.",
            "Tired after the long meeting but glad the plan finally holds together.",
        ]
        let cycle: [NoteParagraphTextStyle] = [.heading, .body, .body, .bulletedList, .bulletedList, .checklistUnchecked, .body]
        var paragraphs: [String] = []
        var styles: [NoteParagraphTextStyle] = []
        var length = 0
        var i = 0
        while length < approximateChars {
            let line = sentences[i % sentences.count]
            paragraphs.append(line)
            styles.append(cycle[i % cycle.count])
            length += line.count + 1
            i += 1
        }
        // Three photo lines at 1/4, 1/2, 3/4 (each takes one paragraph slot).
        for (n, fraction) in [0.75, 0.5, 0.25].enumerated() {
            let at = Int(Double(paragraphs.count) * fraction)
            paragraphs.insert(inlinePhotoToken(at: 2 - n), at: at)
            styles.insert(.body, at: at)
        }
        let text = paragraphs.joined(separator: "\n")
        // Inline ranges count a photo as one character: bold on the first word of every fifth paragraph.
        var ranges: [InlineStyleRange] = []
        var offset = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let isPhoto = inlinePhotoIndex(from: paragraph) != nil
            if !isPhoto, index % 5 == 1 {
                ranges.append(InlineStyleRange(location: offset, length: 4, bold: true, italic: false, underline: false,
                                               strikethrough: false, highlightIndex: nil))
            }
            offset += (isPhoto ? 1 : (paragraph as NSString).length) + 1
        }
        return Entry(
            text: text,
            styles: try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles)),
            inline: try? JSONEncoder().encode(InlineStyleDocument(ranges: ranges)),
            photos: Array(repeating: Self.onePixelPNG, count: 3)
        )
    }

    private struct Timings {
        var shouldChange = 0.0, insert = 0.0, didChange = 0.0, updatePass = 0.0, wordCount = 0.0
        var total: Double { shouldChange + insert + didChange + updatePass + wordCount }
        mutating func add(_ other: Timings) {
            shouldChange += other.shouldChange; insert += other.insert; didChange += other.didChange
            updatePass += other.updatePass; wordCount += other.wordCount
        }
        func scaled(_ factor: Double) -> Timings {
            Timings(shouldChange: shouldChange * factor, insert: insert * factor, didChange: didChange * factor,
                    updatePass: updatePass * factor, wordCount: wordCount * factor)
        }
        var summary: String {
            String(format: "total %.2f ms = shouldChange %.2f + insert %.2f + didChange %.2f + updatePass %.2f + wordCount %.2f",
                   total, shouldChange, insert, didChange, updatePass, wordCount)
        }
    }

    /// Average per-keystroke cost of typing `keystrokes` letters in the middle of the entry.
    private func measure(approximateChars: Int, keystrokes: Int = 20) -> (Timings, Int, String) {
        let entry = makeEntry(approximateChars: approximateChars)
        var text = entry.text, styles = entry.styles, inline = entry.inline, photos = entry.photos
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
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        coordinator.applyStyledText(to: textView, preservingSelection: false)

        // Type in a body paragraph near the middle (after its first word).
        let display = (textView.text ?? "") as NSString
        let middle = display.range(of: "Called about", range: NSRange(location: display.length / 2, length: display.length / 2))
        textView.selectedRange = NSRange(location: middle.location + 6, length: 0)

        var sum = Timings()
        var wordCounter = ParagraphWordCounter()   // what WriteViewModel uses
        _ = wordCounter.count(text)
        func now() -> Double { CFAbsoluteTimeGetCurrent() * 1000 }
        for n in 0..<keystrokes {
            var t = Timings()
            let caret = textView.selectedRange
            let letter = n % 5 == 4 ? " " : "x"
            var mark = now()
            _ = coordinator.textView(textView, shouldChangeTextIn: caret, replacementText: letter)
            t.shouldChange = now() - mark
            mark = now()
            textView.textStorage.replaceCharacters(in: caret, with: NSAttributedString(string: letter, attributes: textView.typingAttributes))
            textView.selectedRange = NSRange(location: caret.location + 1, length: 0)
            t.insert = now() - mark
            mark = now()
            coordinator.textViewDidChange(textView)
            t.didChange = now() - mark
            // updateUIView's body, as SwiftUI runs it after the binding changes.
            mark = now()
            coordinator.noteOutsideChange(in: textView)
            let mismatch = !coordinator.isShowing(text)
                && coordinator.logicalText(from: textView) != coordinator.displayTextEquivalent(for: text)
            coordinator.applyStyledText(to: textView, preservingSelection: !mismatch)
            coordinator.updatePlaceholder(in: textView)
            t.updatePass = now() - mark
            mark = now()
            _ = wordCounter.count(text)
            t.wordCount = now() - mark
            sum.add(t)
        }
        // Pieces of textViewDidChange, timed on their own after the run.
        var pieces: [String] = []
        func time(_ name: String, _ body: () -> Void) {
            let start = now()
            for _ in 0..<5 { body() }
            pieces.append(String(format: "%@ %.2f", name, (now() - start) / 5))
        }
        time("logicalText") { _ = coordinator.logicalText(from: textView) }
        time("extractInline") { _ = coordinator.extractedInlineStyleData(from: textView) }
        time("displayTextEquivalent") { _ = coordinator.displayTextEquivalent(for: text) }
        time("snapshot") { _ = coordinator.currentSnapshot(of: textView) }
        return (sum.scaled(1 / Double(keystrokes)), (text as NSString).length, pieces.joined(separator: ", "))
    }

    private func report(_ name: String, _ timings: Timings, length: Int, pieces: String) {
        let line = "\(name) (\(length) UTF-16 units, 3 photos, styled): \(timings.summary) | pieces (ms): \(pieces)\n"
        Attachment.record(line, named: "\(name).txt")
    }

    @Test func keystrokeAt10kChars() {
        let (timings, length, pieces) = measure(approximateChars: 10_000)
        report("keystroke-10k", timings, length: length, pieces: pieces)
        #expect(timings.total < 200, "\(timings.summary)")
    }

    @Test func keystrokeAt50kChars() {
        let (timings, length, pieces) = measure(approximateChars: 50_000, keystrokes: 10)
        report("keystroke-50k", timings, length: length, pieces: pieces)
        #expect(timings.total < 1000, "\(timings.summary)")
    }
}
