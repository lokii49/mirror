import Testing
import UIKit
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
}
