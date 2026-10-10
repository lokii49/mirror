import Foundation
import SwiftData

/// One-time pass that removes list markers the pre-3.1.0 iOS editor saved into the text of entries
/// with a mid-text photo (audit item 2): a marker right after a photo token, or a list item's own
/// marker at the start of its text, shown doubled. See `NoteEditorCodec.repairPhotoMarkerDamage`
/// for exactly what is removed. Paragraph styles that were shifted cannot be told from real ones
/// and are not touched. Sets `text` and `inlineStyleData` only; dates stay as they are.
enum PhotoMarkerRepair {
    static let flag = "mirror.didRepairPhotoMarkers.v1"

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        // Same wait-for-CloudKit deferral as UngroundedInsightCleanup: on a new device, entries
        // can still be arriving on first launch, and marking done early would skip them.
        guard UserDefaults.standard.integer(forKey: UngroundedInsightCleanup.backgroundingCountKey) >= 1 else { return }
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        // An empty store may just not have synced yet: retry next foreground instead of
        // marking done.
        guard !entries.isEmpty else { return }

        var changed = 0
        for entry in entries {
            guard let text = entry.decryptedText, text.contains("[[mirror-photo") else { continue }
            // Formatting that can't be read now must not be overwritten with nothing.
            let inline = entry.inlineStyleData
            if entry.encryptedInlineStyleData != nil, inline == nil { continue }
            // Nor formatting this device can't decrypt (handed back as ciphertext, not nil).
            if MirrorEncryption.encryptedDataNeedsUnavailableKey(entry.encryptedInlineStyleData)
                || MirrorEncryption.encryptedDataNeedsUnavailableKey(entry.encryptedTextStyleData) { continue }
            guard let repaired = NoteEditorCodec.repairPhotoMarkerDamage(
                text: text, textStyleData: entry.textStyleData, inlineStyleData: inline
            ) else { continue }
            entry.text = repaired.text
            entry.inlineStyleData = repaired.inlineStyleData
            changed += 1
        }
        do {
            if changed > 0 { try context.save() }
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Leave the flag unset; retry next foreground.
        }
    }
}
