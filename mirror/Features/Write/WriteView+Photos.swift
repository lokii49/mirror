import SwiftUI

extension WriteView {
    func handlePickedPhoto(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isAttachingPhoto = true
            Task {
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let preparedData = try await Task.detached(priority: .userInitiated) {
                        try preparedInlinePhotoData(fromFileAt: url)
                    }.value
                    let index = photoDataArray.count
                    photoDataArray.append(preparedData)
                    viewModel.text = textWithInlinePhotoToken(viewModel.text, at: index)
                    isAttachingPhoto = false
                } catch {
                    isAttachingPhoto = false
                    photoAttachError = String(localized: "This image could not be attached. Try a different image or export it as JPEG first.")
                }
            }
        case .failure:
            photoAttachError = String(localized: "This image could not be attached. Try a different image or export it as JPEG first.")
        }
    }
}
