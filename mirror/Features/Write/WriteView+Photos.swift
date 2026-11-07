import SwiftUI
#if os(iOS) && canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

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
            var mapLeads = false
            for (offset, url) in urls.enumerated() {
                if let data = try? await Task.detached(priority: .userInitiated, operation: { try preparedInlinePhotoData(fromFileAt: url) }).value {
                    prepared.append(data)
                    // The map is always the first picture `read` gives, when there is one.
                    if offset == 0, insert.mapLink != nil { mapLeads = true }
                }
                try? FileManager.default.removeItem(at: url)
            }
            let start = photoDataArray.count
            photoDataArray.append(contentsOf: prepared)
            setSuggestionText(insert, tokens: prepared.indices.map { inlinePhotoToken(at: start + $0) }, mapLeads: mapLeads)
            isAttachingPhoto = false
        }
        #else
        setSuggestionText(insert, tokens: [])
        #endif
    }

    /// On a blank entry the suggestion becomes the text; after writing it's added at the end, after
    /// a blank line, keeping the entry's paragraph styles and links (`SuggestionInsert.appended`).
    /// Places, songs and the map open Maps / Music / Podcasts as ordinary entry links.
    private func setSuggestionText(_ insert: SuggestionInsert, tokens: [String], mapLeads: Bool = false) {
        guard !insert.text(withPhotoTokens: tokens).isEmpty else { return }
        let existingStyles = viewModel.textStyleData.flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }
        let existingInline = inlineStyleData.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? []
        // After the paragraph the cursor is in (UI checklist 2026-11-07); the end when there's none.
        let afterParagraph = panelState.caretParagraph?()
        let result = insert.inserted(into: viewModel.text, afterParagraph: afterParagraph, existingStyles: existingStyles,
                                     existingInline: existingInline, tokens: tokens, mapLeads: mapLeads, entryFont: entryFontChoiceRaw)
        viewModel.text = result.text
        if let styles = result.styles { viewModel.textStyleData = try? JSONEncoder().encode(styles) }
        inlineStyleData = result.inline.isEmpty ? nil : try? JSONEncoder().encode(InlineStyleDocument(ranges: result.inline))
        // Added at the end: the cursor follows it. In the middle: the cursor stays where it was, just
        // above the new block (nothing before it moved).
        var ending = result.text
        while let last = ending.last, last.isNewline { ending.removeLast() }
        var added = insert.text(withPhotoTokens: tokens)
        while let last = added.last, last.isNewline { added.removeLast() }
        if ending.hasSuffix(added) { applyTextCommand(.moveCursor(location: .max)) }
    }
}

/// Presents Apple's Journaling Suggestions sheet from Write's paperclip menu and hands the pick to
/// `applySuggestion`. Its own type so Write's body (at the Debug stack limit) gains one layer, not
/// the picker's generic chain. While the pick is read, Write's attaching indicator shows.
struct SuggestionsPickerPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var isAdding: Bool
    let onSuggestion: (SuggestionInsert) -> Void

    func body(content: Content) -> some View {
        #if os(iOS) && canImport(JournalingSuggestions)
        if #available(iOS 17.2, *) {
            content.journalingSuggestionsPicker(isPresented: $isPresented) { suggestion in
                await MainActor.run { isAdding = true }
                let insert = await SuggestionInsert.read(suggestion)
                await MainActor.run {
                    isAdding = false
                    UserDefaults.standard.set(true, forKey: "mirror.suggestions.tipShown")
                    onSuggestion(insert)
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
