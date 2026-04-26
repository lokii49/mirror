import SwiftUI
import SwiftData

@Observable
class WriteViewModel {
    var titleText: String = ""
    var selectedMood: String? = nil
    var wordCount: Int = 0
    var hasText: Bool = false
    var formatState = FormatState()

    let coordinator = RichTextCoordinator()
    private var didConfigure = false

    init() {
        coordinator.onChange = { [weak self] attrText in
            guard let self else { return }
            let plain = attrText.string
            wordCount = plain.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
            hasText = !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        coordinator.onFormatStateChange = { [weak self] state in
            self?.formatState = state
        }
    }

    var hasContent: Bool {
        hasText
    }

    func configure(entry: Entry?) {
        guard !didConfigure else { return }
        didConfigure = true
        titleText = entry?.title ?? ""
        selectedMood = entry?.mood
    }

    func save(context: ModelContext) {
        guard let tv = coordinator.textView else { return }
        let attrText = tv.attributedText ?? NSAttributedString()
        let plain = attrText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = Entry.extractTitle(from: plain)
        guard !plain.isEmpty || !title.isEmpty else { return }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: attrText, requiringSecureCoding: false)
        let entry = Entry(text: plain, richTextData: data, mood: selectedMood, title: title.isEmpty ? nil : title)
        context.insert(entry)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        coordinator.clear()
    }

    func updateEntry(_ entry: Entry) {
        guard let tv = coordinator.textView else { return }
        let attrText = tv.attributedText ?? NSAttributedString()
        let plain = attrText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = Entry.extractTitle(from: plain)
        guard !plain.isEmpty || !title.isEmpty else { return }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: attrText, requiringSecureCoding: false)
        entry.text = plain
        entry.richTextData = data
        entry.mood = selectedMood
        entry.wordCount = plain.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
        entry.tags = Entry.extractTags(from: plain)
        entry.title = title
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
