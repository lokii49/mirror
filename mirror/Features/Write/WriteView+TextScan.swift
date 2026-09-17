import SwiftUI

extension WriteView {
    func handleScannedPages(_ result: Result<[UIImage], Error>) {
        switch result {
        case .success(let images):
            isScanningText = true
            // Reuses the same language preference the user already set for voice
            // transcription (ProtocolSettingsView) rather than a second, separate setting.
            let preferredLanguage = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? ""
            Task {
                do {
                    let text = try await Task.detached(priority: .userInitiated) {
                        try recognizedText(from: images, preferredLanguage: preferredLanguage)
                    }.value
                    isScanningText = false
                    appendScannedText(text)
                } catch {
                    isScanningText = false
                    textScanError = (error as? LocalizedError)?.errorDescription
                        ?? String(localized: "That scan couldn't be read. Try again with better lighting.")
                }
            }
        case .failure(let error):
            textScanError = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "That scan couldn't be read. Try again with better lighting.")
        }
    }

    private func appendScannedText(_ text: String) {
        let trimmed = viewModel.text.trimmingCharacters(in: .newlines)
        viewModel.text = trimmed.isEmpty ? text : "\(trimmed)\n\n\(text)"
        // Same clamped-stale-selection bug as templates/Talk it out (see
        // WritingTemplate.cursorOffset) — without this the caret stays wherever it was before
        // the scan, not at the end of the newly-inserted text.
        applyTextCommand(.moveCursor(location: .max))
    }
}
