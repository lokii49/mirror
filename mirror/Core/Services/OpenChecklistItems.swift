import Foundation
import SwiftData

/// Unticked checklist items across the journal, for the Still open page. App-built from each
/// entry's own paragraph styles: nothing is guessed, and nothing reads text that isn't a checklist
/// line. Kept-out collections (Scratch) are included on purpose: a shopping list is what this is for.
enum OpenChecklistItems {
    struct Line: Equatable {
        /// Index of the paragraph in the entry's `\n`-separated text (= its style index).
        let index: Int
        let text: String
    }

    struct Group: Identifiable {
        let entryID: UUID
        let createdAt: Date
        var lines: [Line]
        var id: UUID { entryID }
    }

    /// Unchecked, non-empty checklist lines of one entry, in order. Photo tokens are left out of the
    /// shown text.
    static func uncheckedLines(text: String, textStyleData: Data?) -> [Line] {
        guard let styles = NoteEditorCodec.decodeTextStyleDocument(textStyleData)?.paragraphStyles,
              styles.contains(.checklistUnchecked) else { return [] }
        let paragraphs = text.components(separatedBy: "\n")
        var lines: [Line] = []
        for (index, style) in styles.enumerated() where style == .checklistUnchecked && paragraphs.indices.contains(index) {
            let shown = paragraphs[index]
                .replacingPhotoTokens()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !shown.isEmpty { lines.append(Line(index: index, text: shown)) }
        }
        return lines
    }

    /// Every entry with an open item, newest first. Only entries that carry a style document are
    /// decrypted, and their text only when that document has an unchecked line.
    @MainActor
    static func groups(in context: ModelContext) -> [Group] {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.encryptedTextStyleData != nil },
                                                sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.propertiesToFetch = [\.id, \.createdAt, \.encryptedTextStyleData]
        let candidates = (try? context.fetch(descriptor)) ?? []
        var result: [Group] = []
        for entry in candidates {
            let styleData = entry.textStyleData
            guard let styles = NoteEditorCodec.decodeTextStyleDocument(styleData)?.paragraphStyles,
                  styles.contains(.checklistUnchecked),
                  let text = entry.decryptedText else { continue }
            let lines = uncheckedLines(text: text, textStyleData: styleData)
            if !lines.isEmpty { result.append(Group(entryID: entry.id, createdAt: entry.createdAt, lines: lines)) }
        }
        return result
    }

    /// Ticks or unticks one line, only if the entry still has a checklist line there with the same
    /// text (it may have been edited on another device since the page loaded). True when written.
    @MainActor
    @discardableResult
    static func setChecked(_ checked: Bool, line: Line, entryID: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first,
              let text = entry.decryptedText,
              let data = entry.textStyleData,
              var document = NoteEditorCodec.decodeTextStyleDocument(data),
              document.paragraphStyles.indices.contains(line.index) else { return false }
        let current = document.paragraphStyles[line.index]
        guard current == .checklistUnchecked || current == .checklistChecked else { return false }
        let paragraphs = text.components(separatedBy: "\n")
        guard paragraphs.indices.contains(line.index),
              paragraphs[line.index].replacingPhotoTokens()
                .trimmingCharacters(in: .whitespacesAndNewlines) == line.text else { return false }
        document.paragraphStyles[line.index] = checked ? .checklistChecked : .checklistUnchecked
        guard let encoded = try? JSONEncoder().encode(document) else { return false }
        entry.textStyleData = encoded
        guard entry.textStyleData == encoded else { return false }   // key unavailable: nothing sealed
        do { try context.save() } catch { return false }
        return true
    }
}

extension String {
    /// The text without its `[[mirror-photo-N]]` tokens (`textWithPhotoTokensReplaced`).
    func replacingPhotoTokens() -> String { textWithPhotoTokensReplaced(self, placeholder: "") }
}
