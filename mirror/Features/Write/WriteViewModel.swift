import SwiftUI
import SwiftData

@Observable
class WriteViewModel {
    var text: String = ""
    var selectedMood: String? = nil

    var wordCount: Int {
        text.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func configure(entry: Entry?) {
        if let entry {
            text = entry.text
            selectedMood = entry.mood
        }
    }

    func save(context: ModelContext) {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let entry = Entry(text: plain, mood: selectedMood, source: .typed)
        context.insert(entry)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        text = ""
        selectedMood = nil
    }

    func updateEntry(_ entry: Entry) {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        entry.text = plain
        entry.wordCount = plain.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
        entry.mood = selectedMood
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
