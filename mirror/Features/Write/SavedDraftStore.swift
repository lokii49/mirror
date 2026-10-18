import Foundation

extension Notification.Name {
    /// Drafts > Continue writing: the main Write editor takes `SavedDraftStore.pendingResume`.
    static let mirrorResumeSavedDraft = Notification.Name("mirror.resumeSavedDraft")
    /// A draft was added to, taken from or removed from Drafts (Write's Drafts menu reloads).
    static let mirrorSavedDraftsChanged = Notification.Name("mirror.savedDraftsChanged")
}

/// Drafts: new entries put aside to finish later. On this device only (never synced). Each one is
/// a `WriteDraftStore` blob in slot `.saved(id)` plus a `DraftAttachmentStore` file, both sealed
/// with the journal key, exactly as the editor's own draft is stored.
///
/// The editor never edits a saved draft in place. "Save to Drafts" moves the editor's draft into
/// a new saved slot; "Continue writing" moves the editor's draft (if any) into Drafts first and
/// then moves the chosen one into the editor's slot. Nothing is ever overwritten.
enum SavedDraftStore {

    struct Summary: Identifiable, Equatable {
        let id: UUID
        /// nil when this device can't decrypt it yet.
        let payload: WriteDraftStore.Payload?

        var savedAt: Date? { payload?.savedAt }
        var preview: String? {
            guard let text = payload?.text else { return nil }
            let body = NoteEditorCodec.splitTrailingPhotoTokens(text).body
            return body.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
        }
        var wordCount: Int { payload.map { strippedWordCount($0.text) } ?? 0 }
    }

    /// Set by the Drafts list right before posting `.mirrorResumeSavedDraft`; taken by the main
    /// Write editor (now, or when it next appears if it doesn't exist yet).
    @MainActor static var pendingResume: UUID?

    static func ids(defaults: UserDefaults = WriteDraftStore.storage) -> [UUID] {
        let prefix = WriteDraftStore.Slot.savedKeyPrefix
        var ids = Set<UUID>()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            var rest = String(key.dropFirst(prefix.count))
            if rest.hasSuffix(".unreadable") { rest = String(rest.dropLast(".unreadable".count)) }
            if let id = UUID(uuidString: rest) { ids.insert(id) }
        }
        return Array(ids)
    }

    /// Newest first; drafts that can't be read yet last.
    static func summaries(defaults: UserDefaults = WriteDraftStore.storage,
                          crypto: WriteDraftStore.Crypto = .live) -> [Summary] {
        ids(defaults: defaults).map { id in
            if case .payload(let payload) = WriteDraftStore.load(slot: .saved(id), defaults: defaults, crypto: crypto) {
                return Summary(id: id, payload: payload)
            }
            return Summary(id: id, payload: nil)
        }
        .sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    /// Moves the draft in `slot` (and its attachment file) into a new saved draft. The text blob
    /// is re-sealed with `savedAt` set; if it can't be opened right now it moves as it is.
    /// Returns nil when the slot holds nothing.
    @discardableResult
    static func stash(from slot: WriteDraftStore.Slot, attachments: DraftAttachmentStore.Location?,
                      now: Date = Date(), defaults: UserDefaults = WriteDraftStore.storage,
                      crypto: WriteDraftStore.Crypto = .live) -> UUID? {
        let id = UUID()
        let target = WriteDraftStore.Slot.saved(id)
        switch WriteDraftStore.load(slot: slot, defaults: defaults, crypto: crypto) {
        case .payload(var payload):
            payload.savedAt = now
            if WriteDraftStore.save(payload, slot: target, defaults: defaults, crypto: crypto) {
                defaults.removeObject(forKey: slot.key)
            } else if let sealed = defaults.data(forKey: slot.key) {
                defaults.set(sealed, forKey: target.key)
                defaults.removeObject(forKey: slot.key)
            }
        case .unavailable:
            // `load` set the blob aside under the preserved key; carry it over unopened.
            guard let sealed = defaults.data(forKey: slot.preservedKey) else { return nil }
            defaults.set(sealed, forKey: target.preservedKey)
            defaults.removeObject(forKey: slot.preservedKey)
        case .none:
            // Attachments alone (a photo with no text yet) are still a draft.
            guard DraftAttachmentStore.move(from: attachments, to: .saved(id)) else { return nil }
            WriteDraftStore.save(WriteDraftStore.Payload(savedAt: now), slot: target, defaults: defaults, crypto: crypto)
            postChanged()
            return id
        }
        DraftAttachmentStore.move(from: attachments, to: .saved(id))
        postChanged()
        return id
    }

    /// Moves a saved draft into `slot` (the editor's), replacing what the slot held: callers
    /// stash that first. False when the draft no longer exists.
    @discardableResult
    static func moveToEditor(_ id: UUID, slot: WriteDraftStore.Slot, attachments: DraftAttachmentStore.Location?,
                             defaults: UserDefaults = WriteDraftStore.storage) -> Bool {
        let source = WriteDraftStore.Slot.saved(id)
        let sealed = defaults.data(forKey: source.key)
        let preserved = defaults.data(forKey: source.preservedKey)
        guard sealed != nil || preserved != nil else { return false }
        defaults.removeObject(forKey: slot.key)
        if let sealed { defaults.set(sealed, forKey: slot.key) }
        if let preserved, sealed == nil { defaults.set(preserved, forKey: slot.preservedKey) }
        defaults.removeObject(forKey: source.key)
        defaults.removeObject(forKey: source.preservedKey)
        DraftAttachmentStore.clearIncludingPreserved(at: attachments)
        DraftAttachmentStore.move(from: .saved(id), to: attachments)
        DraftAttachmentStore.clearIncludingPreserved(at: .saved(id))
        postChanged()
        return true
    }

    static func delete(_ id: UUID, defaults: UserDefaults = WriteDraftStore.storage) {
        WriteDraftStore.clearIncludingPreserved(slot: .saved(id), defaults: defaults)
        DraftAttachmentStore.clearIncludingPreserved(at: .saved(id))
        postChanged()
    }

    private static func postChanged() {
        NotificationCenter.default.post(name: .mirrorSavedDraftsChanged, object: nil)
    }

    /// Delete All in Drafts, and Delete Everything.
    static func deleteAll(defaults: UserDefaults = WriteDraftStore.storage) {
        ids(defaults: defaults).forEach { delete($0, defaults: defaults) }
    }
}
