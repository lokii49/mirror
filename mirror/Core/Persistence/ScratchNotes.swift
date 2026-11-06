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
    static func save(_ text: String, in context: ModelContext) throws -> Entry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SaveError.empty }
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: true) else { throw SaveError.keyUnavailable }
        let collection: JournalCollection
        do { collection = try target(in: context) } catch JournalOrganizationStore.StoreError.keyUnavailable {
            throw SaveError.keyUnavailable
        }
        let entry = Entry(text: trimmed, source: .typed)
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
}
