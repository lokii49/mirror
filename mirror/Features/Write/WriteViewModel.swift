import SwiftUI

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

    private func updateWordCount() {
        wordCount = strippedWordCount(text)
    }
}
