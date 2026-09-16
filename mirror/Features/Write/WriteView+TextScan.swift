import SwiftUI

extension WriteView {
    func handleScannedPages(_ result: Result<[UIImage], Error>) {
        switch result {
        case .success(let images):
            isScanningText = true
            Task {
                do {
                    let text = try await Task.detached(priority: .userInitiated) {
                        try recognizedText(from: images)
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
    }
}
