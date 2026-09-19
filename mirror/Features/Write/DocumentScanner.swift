import SwiftUI
import VisionKit
import Vision

/// Writing-roadmap.md 1.1 — "scan a page" quick capture. VisionKit's document scanner does the
/// capture (auto edge-detection/perspective correction), Vision's on-device text recognition
/// does the OCR. Both frameworks run entirely on-device — no network call, same privacy
/// guarantee as everything else in CLAUDE.md. Returns raw pages; recognizedText(from:) is a
/// separate step so WriteView (not this picker) owns the isScanningText loading state, matching
/// how WriteView+Photos.swift owns isAttachingPhoto around NativePhotoPicker/CameraPickerController.
struct DocumentScannerController: UIViewControllerRepresentable {
    let onScanned: (Result<[UIImage], Error>) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScanned: onScanned) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScanned: (Result<[UIImage], Error>) -> Void

        init(onScanned: @escaping (Result<[UIImage], Error>) -> Void) {
            self.onScanned = onScanned
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            controller.dismiss(animated: true)
            guard scan.pageCount > 0 else {
                onScanned(.failure(TextScanError.noPages))
                return
            }
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScanned(.success(images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onScanned(.failure(error))
        }
    }
}

enum TextScanError: LocalizedError {
    case noPages
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .noPages:
            return String(localized: "No pages were scanned.")
        case .noTextFound:
            return String(localized: "No text was found in that scan. Try again with better lighting or hold the page flatter.")
        }
    }
}

/// Runs Vision's on-device text recognition over each scanned page and joins the results.
/// `.accurate` (vs. `.fast`) trades a little latency for materially better recognition on
/// handwriting and low-contrast photos — acceptable here since this already runs off the main
/// thread (see WriteView+TextScan.swift's `Task.detached`), not on a live camera feed.
///
/// `preferredLanguage`: an SFSpeechRecognizer-style BCP-47 tag (e.g. "de-DE") — reuses the
/// user's existing `transcriptionLanguage` Settings choice (`ProtocolSettingsView`) rather than
/// inventing a second language preference. Vision's own `recognitionLanguages` uses the same
/// tag format. Empty string (the setting's "Automatic" value) falls back to the system's
/// preferred languages, filtered to what this request actually supports — passing an
/// unsupported tag straight through would make `VNImageRequestHandler.perform` throw.
nonisolated func recognizedText(from images: [UIImage], preferredLanguage: String = "") throws -> String {
    var pageTexts: [String] = []
    for image in images {
        guard let cgImage = image.cgImage else { continue }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        if !preferredLanguage.isEmpty, supported.contains(preferredLanguage) {
            // Only Vision's own supported-languages list is authoritative here.
            // `preferredLanguage` comes from ProtocolSettingsView's `transcriptionLanguage`,
            // which is populated from SFSpeechRecognizer.supportedLocales() — a different,
            // wider list than Vision OCR supports. A tag valid for speech but not OCR passed
            // straight to recognitionLanguages would make VNImageRequestHandler.perform throw,
            // so an unmatched explicit choice falls through to the same preferred-languages
            // fallback as "Automatic" rather than being trusted blindly.
            request.recognitionLanguages = [preferredLanguage]
        } else if !supported.isEmpty {
            let matched = Locale.preferredLanguages.filter { supported.contains($0) }
            if !matched.isEmpty { request.recognitionLanguages = matched }
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        if !lines.isEmpty {
            pageTexts.append(lines.joined(separator: "\n"))
        }
    }
    let combined = pageTexts.joined(separator: "\n\n")
    guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TextScanError.noTextFound
    }
    return combined
}
