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

extension WriteView {
    /// A picked Journaling Suggestion, inserted once all its pictures are ready (option A, owner
    /// 2026-11-07): the title as a Heading, its lines, the pictures one per line (the first full
    /// width, later ones as square tiles), and the cursor on an empty line underneath. Setting the
    /// text after the pictures keeps the cursor below them, not beside the last one.
    func applySuggestion(_ insert: SuggestionInsert) {
        if let mood = insert.mood, viewModel.selectedMood == nil { viewModel.selectedMood = mood }
        #if os(iOS)
        let urls = insert.pictures
        guard !urls.isEmpty else { setSuggestionText(insert, tokens: []); return }
        isAttachingPhoto = true
        Task {
            var prepared: [Data] = []
            for url in urls {
                if let data = try? await Task.detached(priority: .userInitiated, operation: { try preparedInlinePhotoData(fromFileAt: url) }).value {
                    prepared.append(data)
                }
                try? FileManager.default.removeItem(at: url)
            }
            let start = photoDataArray.count
            photoDataArray.append(contentsOf: prepared)
            setSuggestionText(insert, tokens: prepared.indices.map { inlinePhotoToken(at: start + $0) })
            isAttachingPhoto = false
        }
        #else
        setSuggestionText(insert, tokens: [])
        #endif
    }

    private func setSuggestionText(_ insert: SuggestionInsert, tokens: [String]) {
        let text = insert.text(withPhotoTokens: tokens)
        guard !text.isEmpty else { return }
        viewModel.text = text
        if insert.leadsWithTitle {
            // Every paragraph gets an explicit style: one without falls back to legacy "# " parsing.
            let count = text.components(separatedBy: "\n").count
            let models = [NoteEditorCodec.ParagraphModel(style: .heading)]
                + Array(repeating: NoteEditorCodec.ParagraphModel(style: .body), count: max(0, count - 1))
            viewModel.textStyleData = NoteEditorCodec.encodeTextStyleData(
                models: models, entryFont: WritingFontChoice(rawValue: entryFontChoiceRaw) ?? .system)
        }
        applyTextCommand(.moveCursor(location: .max))
    }
}
