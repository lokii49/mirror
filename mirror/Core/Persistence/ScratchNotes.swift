import Foundation
import SwiftData

/// Quick notes saved straight into Scratch (the collection kept out of reflections): the quick-note
/// sheet, Siri's "Add a note to Scratch" and the Control Center button all save through here.
enum ScratchNotes {
    enum SaveError: Error, Equatable {
        case empty
        /// The device can't encrypt yet (locked before first unlock, key not synced).
        case keyUnavailable
    }

    /// Where a quick note goes, without ever changing a choice the person made:
    /// 1. a kept-out collection named Scratch (in this language),
    /// 2. else any kept-out collection (Scratch renamed, or their own),
    /// 3. else a collection named Scratch, left as it is (they turned keeping it out off),
    /// 4. else a new Scratch, kept out.
    @MainActor
    static func target(in context: ModelContext) throws -> JournalCollection {
        let all = JournalOrganizationStore.collections(in: context)
        let name = JournalOrganizationStore.scratchName
        func named(_ collection: JournalCollection) -> Bool {
            collection.payload?.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        func keptOut(_ collection: JournalCollection) -> Bool { collection.payload?.keepsOutOfInsights == true }
        if let match = all.first(where: { keptOut($0) && named($0) }) ?? all.first(where: keptOut) ?? all.first(where: named) {
            return match
        }
        return try JournalOrganizationStore.createCollection(name: name, icon: JournalOrganizationStore.scratchIcon,
                                                             keepOutOfInsights: true, in: context)
    }

    /// Saves `text` as a new entry in the Scratch target. Throws `.empty` for blank text and
    /// `.keyUnavailable` when nothing can be encrypted; nothing is written in either case.
    @MainActor
    @discardableResult
    static func save(_ text: String, textStyleData: Data? = nil, inlineStyleData: Data? = nil,
                     in context: ModelContext) throws -> Entry {
        let cleaned = trimmed(text: text, textStyleData: textStyleData, inlineStyleData: inlineStyleData)
        let trimmed = cleaned.text
        guard !trimmed.isEmpty else { throw SaveError.empty }
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: true) else { throw SaveError.keyUnavailable }
        let collection: JournalCollection
        do { collection = try target(in: context) } catch JournalOrganizationStore.StoreError.keyUnavailable {
            throw SaveError.keyUnavailable
        }
        let entry = Entry(text: trimmed, source: .typed)
        // Checklists, numbered and bulleted lists from the quick-note editor (2026-11-07).
        entry.textStyleData = cleaned.textStyleData
        entry.inlineStyleData = cleaned.inlineStyleData
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: entry.createdAt)
        entry.collectionID = collection.id
        context.insert(entry)
        do { try context.save() } catch {
            // Leave nothing for autosave to save later: the caller says it wasn't saved, so a
            // second try mustn't make a duplicate.
            context.delete(entry)
            throw error
        }
        // Skips itself for a kept-out collection; runs if they turned keeping Scratch out off.
        MoodAutoDetector.shared.detectIfNeeded(entry, context: context)
        ReviewRequestManager.requestIfEntryMilestoneReached(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)
        return entry
    }

    /// The note without blank lines and spaces before and after it, with its paragraph styles and
    /// inline ranges moved to match: dropping two empty lines at the top must also drop their two
    /// paragraph styles, or every checklist item below would take the style of the line above it.
    /// Styles are kept only when some paragraph has one (a plain note stays plain).
    nonisolated static func trimmed(text: String, textStyleData: Data?, inlineStyleData: Data?)
        -> (text: String, textStyleData: Data?, inlineStyleData: Data?) {
        let paragraphs = text.components(separatedBy: "\n")
        guard let first = paragraphs.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let last = paragraphs.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return ("", nil, nil) }
        var kept = Array(paragraphs[first...last])
        // Spaces at the very start and end go too, as before (a list item's own text keeps its words).
        let leadingSpaces = kept[0].prefix { $0 == " " || $0 == "\t" }.count
        kept[0] = String(kept[0].dropFirst(leadingSpaces))
        while let lastChar = kept[kept.count - 1].last, lastChar == " " || lastChar == "\t" { kept[kept.count - 1].removeLast() }
        let result = kept.joined(separator: "\n")

        var styleData: Data?
        if let data = textStyleData, let doc = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data) {
            func slice<T>(_ values: [T]?, _ filler: T) -> [T]? {
                guard let values else { return nil }
                return (first...last).map { $0 < values.count ? values[$0] : filler }
            }
            let styles = slice(doc.paragraphStyles, .body) ?? []
            if styles.contains(where: { $0 != .body }) {
                let trimmedDoc = NoteTextStyleDocument(paragraphStyles: styles,
                                                       indentLevels: slice(doc.indentLevels, 0),
                                                       fontChoices: slice(doc.fontChoices, "system"))
                styleData = try? JSONEncoder().encode(trimmedDoc)
            }
        }

        var inlineData: Data?
        if let data = inlineStyleData, let doc = try? JSONDecoder().decode(InlineStyleDocument.self, from: data) {
            // UTF-16 offsets (no photos in a quick note): what was cut from the front shifts them.
            let removedFront = (paragraphs[..<first].map { $0 + "\n" }.joined() as NSString).length + leadingSpaces
            let length = (result as NSString).length
            let ranges = doc.ranges.compactMap { range -> InlineStyleRange? in
                var r = range
                let start = max(0, r.location - removedFront)
                let end = min(length, r.location + r.length - removedFront)
                guard end > start else { return nil }
                r.location = start
                r.length = end - start
                return r
            }
            if !ranges.isEmpty { inlineData = try? JSONEncoder().encode(InlineStyleDocument(ranges: ranges)) }
        }
        return (result, styleData, inlineData)
    }
}
