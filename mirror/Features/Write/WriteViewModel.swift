import SwiftUI
import SwiftData

@Observable
class WriteViewModel {
    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            updateWordCount()
        }
    }
    var textStyleData: Data? = nil
    var selectedMood: String? = nil
    private(set) var wordCount: Int = 0

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func configure(entry: Entry?) {
        if let entry {
            text = entry.text
            textStyleData = entry.textStyleData
            selectedMood = entry.mood
        } else {
            updateWordCount()
        }
    }

    func save(context: ModelContext) {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let entry = Entry(text: plain, mood: selectedMood, source: .typed)
        entry.textStyleData = textStyleData
        context.insert(entry)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        text = ""
        textStyleData = nil
        selectedMood = nil
    }

    func updateEntry(_ entry: Entry) {
        guard !entry.textDecryptionFailed else { return }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        entry.text = plain
        entry.textStyleData = textStyleData
        entry.wordCount = plain.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
        entry.mood = selectedMood
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateWordCount() {
        wordCount = text.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
    }
}
