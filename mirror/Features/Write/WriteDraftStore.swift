import Foundation

/// Encrypted, versioned storage for an unsaved Write draft's text and metadata.
///
/// Before 3.0.9 the draft lived in five UserDefaults keys: text and tags were
/// encrypted, but mood and the two style payloads (which can hold link URLs) were
/// stored as plaintext. Everything now goes into one sealed JSON blob per slot.
/// Legacy keys are migrated on first load and removed only after the replacement
/// blob has been written and read back.
///
/// Attachments stay in `DraftAttachmentStore` (they can be megabytes).
enum WriteDraftStore {

    struct Payload: Codable, Equatable {
        static let currentVersion = 1

        var version: Int = Payload.currentVersion
        var text: String = ""
        var textStyleData: Data?
        var inlineStyleData: Data?
        var mood: String?
        var tags: [String] = []

        var isEmpty: Bool {
            text.isEmpty && mood == nil && tags.isEmpty
        }
    }

    enum Slot: Equatable {
        case newEntry

        var key: String {
            switch self {
            case .newEntry: return "mirror.writeDraft.v2.new"
            }
        }

        /// Holds a blob that could not be decrypted when it was found, so a later
        /// save cannot overwrite it before its key arrives (e.g. via iCloud Keychain).
        var preservedKey: String { key + ".unreadable" }
    }

    enum LoadResult: Equatable {
        case none
        /// A draft exists but cannot be read right now. Storage is left as is.
        case unavailable
        case payload(Payload)
    }

    /// Indirection so tests can simulate an unavailable key.
    struct Crypto {
        var seal: (Data) -> Data?
        var open: (Data) -> Data?
        /// Decrypts a legacy `mirror:v1:` string; plaintext passes through; nil when unreadable.
        var openLegacyString: (String) -> String?

        static let live = Crypto(
            seal: { MirrorEncryption.sealData($0) },
            open: { MirrorEncryption.openData($0) },
            openLegacyString: { MirrorEncryption.decryptOptionalStringValue($0) }
        )
    }

    // Pre-3.0.9 keys. Only read for migration and always removed by `clear`.
    static let legacyTextKey = "mirror.writeDraft.text"
    static let legacyTextStyleKey = "mirror.writeDraft.textStyleData"
    static let legacyInlineStyleKey = "mirror.writeDraft.inlineStyleData"
    static let legacyMoodKey = "mirror.writeDraft.mood"
    static let legacyTagsKey = "mirror.writeDraft.tags"
    static let legacyKeys = [legacyTextKey, legacyTextStyleKey, legacyInlineStyleKey, legacyMoodKey, legacyTagsKey]

    // MARK: - Save

    /// Seals and stores the payload. Returns false (and leaves the stored draft
    /// untouched) when encryption fails. An empty payload clears the slot.
    @discardableResult
    static func save(
        _ payload: Payload,
        slot: Slot = .newEntry,
        defaults: UserDefaults = .standard,
        crypto: Crypto = .live
    ) -> Bool {
        if payload.isEmpty {
            clear(slot: slot, defaults: defaults)
            return true
        }
        guard let encoded = try? JSONEncoder().encode(payload),
              let sealed = crypto.seal(encoded) else { return false }
        defaults.set(sealed, forKey: slot.key)
        if slot == .newEntry { removeLegacyKeys(defaults) }
        return true
    }

    // MARK: - Load

    static func load(
        slot: Slot = .newEntry,
        defaults: UserDefaults = .standard,
        crypto: Crypto = .live
    ) -> LoadResult {
        if let sealed = defaults.data(forKey: slot.key) {
            guard let payload = decode(sealed, crypto: crypto) else {
                preserveUnreadable(sealed, slot: slot, defaults: defaults)
                return .unavailable
            }
            // A crash between writing the blob and deleting the legacy keys leaves
            // both; the blob is newer, so it wins.
            if slot == .newEntry { removeLegacyKeys(defaults) }
            return .payload(payload)
        }

        if slot == .newEntry, hasLegacyDraft(defaults) {
            return migrateLegacy(defaults: defaults, crypto: crypto)
        }

        // A previously unreadable draft whose key has since arrived.
        if let preserved = defaults.data(forKey: slot.preservedKey),
           let payload = decode(preserved, crypto: crypto) {
            defaults.set(preserved, forKey: slot.key)
            defaults.removeObject(forKey: slot.preservedKey)
            return .payload(payload)
        }
        return .none
    }

    // MARK: - Clear

    /// Removes the slot's draft and, for new-entry drafts, every legacy key. A
    /// preserved unreadable blob is kept: discarding today's draft is not a
    /// decision about a different draft the user has not seen yet.
    static func clear(slot: Slot = .newEntry, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: slot.key)
        if slot == .newEntry { removeLegacyKeys(defaults) }
    }

    /// Full reset (test-state reset only): also drops preserved blobs.
    static func clearIncludingPreserved(slot: Slot = .newEntry, defaults: UserDefaults = .standard) {
        clear(slot: slot, defaults: defaults)
        defaults.removeObject(forKey: slot.preservedKey)
    }

    // MARK: - Private

    private static func decode(_ sealed: Data, crypto: Crypto) -> Payload? {
        guard let opened = crypto.open(sealed) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: opened)
    }

    private static func preserveUnreadable(_ sealed: Data, slot: Slot, defaults: UserDefaults) {
        // Keep the first unreadable blob; never replace one we are already holding.
        guard defaults.data(forKey: slot.preservedKey) == nil else { return }
        defaults.set(sealed, forKey: slot.preservedKey)
        defaults.removeObject(forKey: slot.key)
    }

    private static func hasLegacyDraft(_ defaults: UserDefaults) -> Bool {
        legacyKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private static func removeLegacyKeys(_ defaults: UserDefaults) {
        for key in legacyKeys { defaults.removeObject(forKey: key) }
    }

    private static func migrateLegacy(defaults: UserDefaults, crypto: Crypto) -> LoadResult {
        var payload = Payload()
        if let storedText = defaults.string(forKey: legacyTextKey), !storedText.isEmpty {
            guard let text = crypto.openLegacyString(storedText) else { return .unavailable }
            payload.text = text
        }
        if let tagsData = defaults.data(forKey: legacyTagsKey) {
            let stored = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
            var tags: [String] = []
            for value in stored {
                guard let tag = crypto.openLegacyString(value) else { return .unavailable }
                tags.append(tag)
            }
            payload.tags = tags
        }
        payload.textStyleData = defaults.data(forKey: legacyTextStyleKey)
        payload.inlineStyleData = defaults.data(forKey: legacyInlineStyleKey)
        payload.mood = defaults.string(forKey: legacyMoodKey)

        if payload.isEmpty {
            removeLegacyKeys(defaults)
            return .none
        }

        // Write the replacement, read it back, and only then drop the originals.
        guard let encoded = try? JSONEncoder().encode(payload),
              let sealed = crypto.seal(encoded) else { return .payload(payload) }
        defaults.set(sealed, forKey: Slot.newEntry.key)
        if let stored = defaults.data(forKey: Slot.newEntry.key), decode(stored, crypto: crypto) == payload {
            removeLegacyKeys(defaults)
        } else {
            defaults.removeObject(forKey: Slot.newEntry.key)
        }
        return .payload(payload)
    }
}
