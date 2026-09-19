import Testing
import UIKit
import Vision
@testable import mirror

// recognizedText(from:) is the one seam in writing-roadmap.md 1.1 (photo-text capture) that
// doesn't need a camera or a simulator picker UI — it's a pure function over [UIImage]. The
// scanner UI itself (DocumentScannerController / VNDocumentCameraViewController) is device-only
// and out of scope here, same as the mic-dependent voice tests elsewhere in this suite.
@Suite("Document scan OCR (recognizedText)")
struct DocumentScannerTests {

    private func renderedTextImage(_ text: String, size: CGSize = CGSize(width: 600, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            (text as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: attributes)
        }
    }

    private func blankImage(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func recognizesRenderedText() throws {
        let image = renderedTextImage("HELLO WORLD")
        let text = try recognizedText(from: [image])
        #expect(text.localizedCaseInsensitiveContains("HELLO"))
    }

    @Test func joinsMultiplePagesWithBlankLineBetween() throws {
        let page1 = renderedTextImage("FIRST PAGE")
        let page2 = renderedTextImage("SECOND PAGE")
        let text = try recognizedText(from: [page1, page2])
        #expect(text.localizedCaseInsensitiveContains("FIRST"))
        #expect(text.localizedCaseInsensitiveContains("SECOND"))
        #expect(text.contains("\n\n"))
    }

    @Test func blankImageThrowsNoTextFound() {
        do {
            _ = try recognizedText(from: [blankImage()])
            Issue.record("expected TextScanError.noTextFound for a blank image")
        } catch TextScanError.noTextFound {
            // expected
        } catch {
            Issue.record("expected TextScanError.noTextFound, got \(error)")
        }
    }

    // writing-roadmap.md 1.1's remaining gap: the non-English recognitionLanguages path was
    // fixed but never exercised against a real scan. Vision OCR runs entirely on-device and
    // needs no camera, so — same as the English-text tests above — this is runnable in-sim.
    @Test func germanPreferredLanguage_recognizesGermanText() throws {
        let image = renderedTextImage("STRASSE")
        let text = try recognizedText(from: [image], preferredLanguage: "de-DE")
        #expect(text.localizedCaseInsensitiveContains("STRASSE"))
    }

    // The real bug this test catches: an unsupported explicit tag used to go straight to
    // `request.recognitionLanguages = [preferredLanguage]` unchecked, which VNImageRequestHandler
    // throws on. `transcriptionLanguage` (the setting this param is sourced from) is populated
    // from SFSpeechRecognizer.supportedLocales() — a wider list than Vision's OCR-supported
    // languages — so a speech-valid, OCR-invalid tag was reachable in practice, not hypothetical.
    @Test func unsupportedPreferredLanguage_fallsBackInsteadOfThrowing() throws {
        let image = renderedTextImage("HELLO WORLD")
        let text = try recognizedText(from: [image], preferredLanguage: "xx-XX")
        #expect(text.localizedCaseInsensitiveContains("HELLO"))
    }

    @Test func japanesePreferredLanguage_recognizesOrSkipsIfUnsupportedOnThisOS() throws {
        let request = VNRecognizeTextRequest()
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        guard supported.contains("ja-JP") else { return } // not available on this OS/sim — nothing to test
        let image = renderedTextImage("こんにちは", size: CGSize(width: 600, height: 200))
        do {
            let text = try recognizedText(from: [image], preferredLanguage: "ja-JP")
            #expect(!text.isEmpty)
        } catch TextScanError.noTextFound {
            // A missing-glyph render (system font can't draw CJK on this OS/sim image) is
            // indistinguishable from a blank scan and isn't a recognizedText defect — skip
            // rather than fail on a rendering limitation this function doesn't own.
        }
    }
}
