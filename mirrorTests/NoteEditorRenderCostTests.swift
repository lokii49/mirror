import Testing
import SwiftUI
import UIKit
@testable import mirror

/// Measures the specific cost the audit (3.6) flagged as "the thing to
/// profile if typing feels heavy on long entries": `updateUIView` (`:75`)
/// unconditionally recomputes `logicalText(from:)` (rebuilds the whole
/// document char-by-char, plus an `allPhotoTokens` sort) and
/// `displayTextEquivalent(for:)` (a full paragraph enumeration) on *every*
/// SwiftUI update pass — not gated behind `applyStyledText`'s own
/// change-detection cache, which only protects the render step downstream of
/// this comparison.
///
/// No Instruments access in this environment, so this substitutes a real
/// wall-clock measurement on this hardware for a guess. It calls
/// `Coordinator.logicalText(from:)` / `.displayTextEquivalent(for:)`
/// directly — the same functions `updateUIView` calls — bypassing
/// `UIViewRepresentable`'s `Context`, which isn't independently constructible
/// outside of live SwiftUI rendering.
///
/// Caveats, stated rather than hidden behind a clean number: this is Debug
/// config in Simulator on Apple Silicon, not a slow real device — the
/// absolute numbers here are a floor, not a device-representative figure.
/// The populated `UITextView` carries plain (unstyled) attributed text
/// matching the raw string, so `textStyle(at:)`/`indentLevelValue(at:)` take
/// their early-return paths on every paragraph rather than reading real
/// attributes — an honest approximation for a length-driven cost, not a
/// claim that styling is free.
struct NoteEditorRenderCostTests {
    private func makeCoordinator(text: String, photoCount: Int = 0) -> (coordinator: NoteEditorTextView.Coordinator, textView: UITextView) {
        let view = NoteEditorTextView(
            text: .constant(text),
            textStyleData: .constant(nil),
            inlineStyleData: .constant(nil),
            photoDataArray: .constant(Array(repeating: Data(), count: photoCount)),
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
        return (coordinator, textView)
    }

    /// `text` with `photoCount` inline photo tokens spread through it, plus
    /// matching 0xFFFC attachment chars in the populated `UITextView` — the
    /// path `logicalText`'s `allPhotoTokens` sort + attachment-char rebuild
    /// loop actually exercises, which the no-photo tests above never touch.
    private func makeCoordinatorWithPhotos(text: String, photoCount: Int) -> (coordinator: NoteEditorTextView.Coordinator, textView: UITextView, textWithTokens: String) {
        var paragraphs = text.components(separatedBy: "\n")
        let stride = max(1, paragraphs.count / max(1, photoCount))
        var inserted = 0
        var i = stride
        while inserted < photoCount && i < paragraphs.count {
            paragraphs.insert(inlinePhotoToken(at: inserted), at: i)
            inserted += 1
            i += stride + 1
        }
        while inserted < photoCount {
            paragraphs.append(inlinePhotoToken(at: inserted))
            inserted += 1
        }
        let textWithTokens = paragraphs.joined(separator: "\n")

        let (coordinator, _) = makeCoordinator(text: textWithTokens, photoCount: photoCount)
        let attributed = NSMutableAttributedString(string: textWithTokens)
        // Replace each token's characters with a single 0xFFFC attachment char,
        // right-to-left so earlier ranges don't shift.
        for (range, _) in allPhotoTokens(in: textWithTokens).sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let nsRange = NSRange(range, in: textWithTokens)
            attributed.replaceCharacters(in: nsRange, with: "\u{fffc}")
        }
        let textView = UITextView()
        textView.attributedText = attributed
        return (coordinator, textView, textWithTokens)
    }

    /// Paragraphs of ~15 words each, `\n`-separated — the same shape
    /// `logicalText`/`displayTextEquivalent` paragraph-enumerate over.
    private func makeLongEntry(approximateChars: Int) -> String {
        let paragraph = "The quick brown fox jumps over the lazy dog again and once more for good measure today."
        let paragraphsNeeded = max(1, approximateChars / (paragraph.count + 1))
        return Array(repeating: paragraph, count: paragraphsNeeded).joined(separator: "\n")
    }

    /// Runs `logicalText` + `displayTextEquivalent` together — the exact pair
    /// `updateUIView:75` calls on every SwiftUI update pass — `iterations`
    /// times, and returns the average wall-clock cost of one pass in
    /// milliseconds.
    private func averageMillisecondsPerPass(text: String, iterations: Int = 20) -> Double {
        let (coordinator, textView) = makeCoordinator(text: text)
        let start = Date()
        for _ in 0..<iterations {
            _ = coordinator.logicalText(from: textView)
            _ = coordinator.displayTextEquivalent(for: text)
        }
        let elapsed = Date().timeIntervalSince(start)
        return (elapsed / Double(iterations)) * 1000
    }

    /// Same measurement, with `photoCount` inline photos actually present —
    /// exercises the `allPhotoTokens` sort + attachment-char rebuild loop
    /// the no-photo tests above skip entirely.
    private func averageMillisecondsPerPassWithPhotos(text: String, photoCount: Int, iterations: Int = 20) -> Double {
        let (coordinator, textView, textWithTokens) = makeCoordinatorWithPhotos(text: text, photoCount: photoCount)
        let start = Date()
        for _ in 0..<iterations {
            _ = coordinator.logicalText(from: textView)
            _ = coordinator.displayTextEquivalent(for: textWithTokens)
        }
        let elapsed = Date().timeIntervalSince(start)
        return (elapsed / Double(iterations)) * 1000
    }

    @Test func costAt5kCharsStaysWellUnderAFrameBudget() {
        let text = makeLongEntry(approximateChars: 5_000)
        let ms = averageMillisecondsPerPass(text: text)
        // Measured 1.34ms on this hardware (Simulator, Debug config) when
        // this test was written — 16.67ms is one frame at 60fps, the budget
        // for the *whole* update pass, not just this comparison. The 4ms
        // bound is ~3x that measurement: headroom for machine variance while
        // still catching a real regression (e.g. an accidental O(n²)
        // reintroduction would blow well past it). If this trips, the "not a
        // Group 1 bug" verdict in the audit doc needs revisiting, not just
        // this bound.
        #expect(ms < 4, "logicalText + displayTextEquivalent averaged \(ms)ms at ~5k chars — was assumed cheap, wasn't measured until now")
    }

    @Test func costAt10kCharsStaysWellUnderAFrameBudget() {
        let text = makeLongEntry(approximateChars: 10_000)
        let ms = averageMillisecondsPerPass(text: text)
        // Measured 1.98ms on this hardware when this test was written.
        #expect(ms < 8, "logicalText + displayTextEquivalent averaged \(ms)ms at ~10k chars — was assumed cheap, wasn't measured until now")
    }

    @Test func costAt5kCharsWithThreePhotosStaysWellUnderAFrameBudget() {
        let text = makeLongEntry(approximateChars: 5_000)
        let ms = averageMillisecondsPerPassWithPhotos(text: text, photoCount: 3)
        // The no-photo tests above never exercise allPhotoTokens' sort or the
        // attachment-char rebuild loop in logicalText (an empty photoDataArray
        // means the 0xFFFC branch never fires) — this does, at a typical
        // photo count for a single entry. Measured 0.85ms on this hardware —
        // no meaningfully higher than the no-photo case at the same size.
        #expect(ms < 4, "logicalText + displayTextEquivalent averaged \(ms)ms at ~5k chars with 3 photos")
    }
}
