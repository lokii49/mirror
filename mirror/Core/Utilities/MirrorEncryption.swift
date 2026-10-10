import CryptoKit
import Foundation
import Security

enum MirrorEncryption {
    private static let keyAccount = "mirror_content_key_v1"
    /// Append-only ledger of every content key this account has ever used, kept in
    /// both the local and iCloud-synced Keychain. Entries written under rotated-away
    /// keys decrypt ONLY through this archive — it must never be deleted or trimmed
    /// by any reset or sign-out flow.
    private static let archiveAccount = "mirror_content_key_archive_v1"
    private static let textPrefix = "mirror:v1:"
    static let unavailableText = "[Encrypted entry unavailable on this device]"
    private static let keyLength = 32

    private nonisolated(unsafe) static var _cachedKey: SymmetricKey? = nil
    private nonisolated(unsafe) static var _didMigrateSession = false
    private nonisolated(unsafe) static var _didRefreshArchiveSession = false
    private nonisolated(unsafe) static var _fallbackCache: (keys: [Data], loadedAt: Date)? = nil
    /// Normal reads reuse the snapshot this long.
    private static let fallbackCacheWindow: TimeInterval = 30
    /// After a decrypt fails against the snapshot, allow a re-read this soon — a
    /// usable key may have just arrived via iCloud Keychain.
    private static let fallbackFailureWindow: TimeInterval = 2
    private static let keyQueue = DispatchQueue(label: "com.mirror.encryption.key")

    #if DEBUG && os(macOS)
    /// Mac UI snapshot mode (`--macSnapshot`, see MacSnapshot.swift) runs against an in-memory
    /// store with a throwaway key, so it never reads or writes the Keychain — a stray content
    /// key synced to iCloud Keychain could be mistaken for the real one on another device.
    /// `--perfSeed=N` (PerfSeed.swift) gets a fixed debug key for the same reason, stable across launches.
    static let debugEphemeralKey: SymmetricKey? =
        CommandLine.arguments.contains("--macSnapshot") ? SymmetricKey(size: .bits256)
            : PerfSeed.isRequested ? PerfSeed.key : nil
    #endif

    #if DEBUG
    /// Tests only: sealing fails as if the key couldn't be read, while opening still works.
    @TaskLocal static var sealFailsForTesting = false
    #endif

    /// Whether this device can seal new journal data right now. The `encrypt*` helpers below fail
    /// open when it can't (plaintext strings; nil data, which a setter would save as a deleted
    /// photo or recording), so every writer checks this first (backlog A3). User saves pass
    /// `creatingIfNeeded: true`, as sealing does (the first entry mints the key); automatic
    /// writers pass false, so a check can never mint a key before iCloud Keychain delivers the
    /// real one, or wait out its retry loop.
    static func canEncrypt(creatingIfNeeded: Bool) -> Bool {
        #if DEBUG
        if sealFailsForTesting { return false }
        #endif
        if (try? key(creatingIfNeeded: creatingIfNeeded)) != nil { return true }
        // Not minting still allows the one case sealing itself resolves without a new key: both
        // slots readably empty while the archive holds a key (iCloud Keychain delivered the archive
        // before the slot, so entries already open through it). Sealing adopts that key.
        return !creatingIfNeeded && archivedKeyWouldBeAdopted()
    }

    private static func archivedKeyWouldBeAdopted() -> Bool {
        #if DEBUG && os(macOS)
        if debugEphemeralKey != nil { return false }
        #endif
        return keyQueue.sync {
            let local = KeychainManager.read(account: keyAccount)
            let synced = KeychainManager.read(account: keyAccount, synchronizable: true)
            guard !local.isFailure, !synced.isFailure else { return false }
            return refreshArchiveLocked().last != nil
        }
    }

    static func encryptString(_ value: String) -> String {
        guard !value.isEmpty, !isEncryptedString(value) else { return value }
        guard let encrypted = try? encryptData(Data(value.utf8)) else { return value }
        return textPrefix + encrypted.base64EncodedString()
    }

    static func decryptString(_ value: String) -> String {
        decryptOptionalStringValue(value) ?? unavailableText
    }

    static func decryptOptionalStringValue(_ value: String) -> String? {
        guard isEncryptedString(value) else { return value }
        let payload = String(value.dropFirst(textPrefix.count))
        guard let data = Data(base64Encoded: payload),
              let decrypted = try? decryptData(data),
              let text = String(data: decrypted, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func encryptOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        return encryptString(value)
    }

    static func decryptOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        return decryptOptionalStringValue(value)
    }

    static func encryptedStringNeedsUnavailableKey(_ value: String) -> Bool {
        isEncryptedString(value) && decryptOptionalStringValue(value) == nil
    }

    /// True when `value` is sealed data this device can't open. `decryptOptionalData` hands such
    /// bytes back unchanged, so a caller that writes them back would re-encrypt ciphertext.
    /// Bytes that start like a format the app stores unencrypted elsewhere (JPEG/PNG photos,
    /// AAC voice notes, JSON style data) are taken as plaintext, not as a missing key.
    static func encryptedDataNeedsUnavailableKey(_ value: Data?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        if (try? decryptData(value)) != nil { return false }
        return !looksLikePlaintextPayload(value)
    }

    static func looksLikePlaintextPayload(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ magic: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + magic.count && Array(bytes[offset..<offset + magic.count]) == magic
        }
        return starts([0xFF, 0xD8, 0xFF])                       // JPEG
            || starts([0x89, 0x50, 0x4E, 0x47])                  // PNG
            || starts(Array("ftyp".utf8), at: 4)                 // M4A / HEIC / MP4
            || starts(Array("caff".utf8))                        // CAF
            || starts(Array("RIFF".utf8))                        // WAV
            || starts(Array("bplist".utf8))                      // binary plist
            // JSON style data. Parsed, not sniffed: a sealed box starts with a random nonce, so
            // one byte in 128 begins with "{" or "[".
            || ((starts(Array("{".utf8)) || starts(Array("[".utf8)))
                && (try? JSONSerialization.jsonObject(with: data)) != nil)
    }

    static func encryptOptionalData(_ value: Data?) -> Data? {
        guard let value, !value.isEmpty else { return value }
        return try? encryptData(value)
    }

    static func decryptOptionalData(_ value: Data?) -> Data? {
        guard let value, !value.isEmpty else { return value }
        return (try? decryptData(value)) ?? value
    }

    static func encryptDataArray(_ values: [Data]) -> [Data] {
        values.map { value in
            guard !value.isEmpty else { return value }
            return (try? encryptData(value)) ?? value
        }
    }

    static func decryptDataArray(_ values: [Data]) -> [Data] {
        values.map { value in
            guard !value.isEmpty else { return value }
            return (try? decryptData(value)) ?? value
        }
    }

    /// Strict variants for drafts and other local recovery stores: nil on any failure.
    /// Unlike the helpers above they never pass plaintext or ciphertext through, so a
    /// caller can tell "the key is unavailable" apart from real content.
    static func sealData(_ data: Data) -> Data? {
        try? encryptData(data)
    }

    static func openData(_ data: Data) -> Data? {
        try? decryptData(data)
    }

    static func encryptStringStrict(_ value: String) -> String? {
        guard !value.isEmpty else { return value }
        guard let encrypted = try? encryptData(Data(value.utf8)) else { return nil }
        return textPrefix + encrypted.base64EncodedString()
    }

    private static func isEncryptedString(_ value: String) -> Bool {
        value.hasPrefix(textPrefix)
    }

    private static func encryptData(_ data: Data) throws -> Data {
        #if DEBUG
        if sealFailsForTesting { throw CryptoKitError.incorrectKeySize }
        #endif
        let sealed = try AES.GCM.seal(data, using: key(creatingIfNeeded: true))
        return sealed.combined ?? data
    }

    private static func decryptData(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        // The primary key may be absent entirely (both live slots empty) while the
        // archive still holds usable keys — never let key() throwing end the attempt.
        let primary = try? key(creatingIfNeeded: false)
        if let primary, let opened = try? AES.GCM.open(box, using: primary) { return opened }

        let primaryData = primary?.withUnsafeBytes { Data($0) }
        let snapshot = fallbackKeys(maxAge: fallbackCacheWindow)
        for candidate in snapshot where candidate != primaryData {
            if let opened = try? AES.GCM.open(box, using: SymmetricKey(data: candidate)) {
                return opened
            }
        }
        // Nothing in the snapshot worked — take one fresh (throttled) look at the
        // Keychain and try only keys that weren't in the snapshot.
        for candidate in fallbackKeys(maxAge: fallbackFailureWindow)
        where candidate != primaryData && !snapshot.contains(candidate) {
            if let opened = try? AES.GCM.open(box, using: SymmetricKey(data: candidate)) {
                return opened
            }
        }
        throw CryptoKitError.authenticationFailure
    }

    // MARK: - Key archive

    private static func fallbackKeys(maxAge: TimeInterval) -> [Data] {
        #if DEBUG && os(macOS)
        if debugEphemeralKey != nil { return [] }
        #endif
        return keyQueue.sync {
            if let cache = _fallbackCache, Date().timeIntervalSince(cache.loadedAt) < maxAge {
                return cache.keys
            }
            return refreshArchiveLocked()
        }
    }

    /// Reads both archive copies and both live key slots, merges every distinct key,
    /// and rewrites an archive copy only when its key SET actually changed (order is
    /// ignored so two devices holding the same keys never ping-pong writes) and only
    /// when its read succeeded (a failed read is unknown state, not an empty archive —
    /// rewriting from a partial view would destroy archived keys). Must run on keyQueue.
    @discardableResult
    private static func refreshArchiveLocked() -> [Data] {
        let localRead = KeychainManager.read(account: archiveAccount)
        let syncedRead = KeychainManager.read(account: archiveAccount, synchronizable: true)
        let localKeys = parseArchive(localRead.data)
        let syncedKeys = parseArchive(syncedRead.data)

        var keys: [Data] = []
        func appendUnique(_ candidates: [Data]) {
            for candidate in candidates where candidate.count == keyLength && !keys.contains(candidate) {
                keys.append(candidate)
            }
        }
        appendUnique(localKeys)
        appendUnique(syncedKeys)
        for synchronizable in [false, true] {
            if case .found(let slot) = KeychainManager.read(account: keyAccount, synchronizable: synchronizable) {
                appendUnique([slot])
            }
        }

        let blob = keys.reduce(into: Data()) { $0.append($1) }
        // Rewrite a copy when its key set changed, or when its stored bytes aren't a
        // clean serialization (corrupt tail, duplicates) — but never after a failed
        // read, and never for a mere ordering difference (avoids cross-device write
        // ping-pong when two devices hold the same keys in different order).
        func needsRewrite(_ read: KeychainManager.ReadResult, parsed: [Data]) -> Bool {
            guard !read.isFailure else { return false }
            if Set(keys) != Set(parsed) { return true }
            return (read.data?.count ?? 0) != keys.count * keyLength
        }
        if needsRewrite(localRead, parsed: localKeys) {
            KeychainManager.save(data: blob, account: archiveAccount)
        }
        if needsRewrite(syncedRead, parsed: syncedKeys) {
            KeychainManager.save(data: blob, account: archiveAccount, synchronizable: true)
        }

        _fallbackCache = (keys, Date())
        return keys
    }

    private static func parseArchive(_ blob: Data?) -> [Data] {
        guard let blob, blob.count >= keyLength else { return [] }
        // Salvage every complete key; a truncated trailing fragment is unusable anyway.
        let wholeKeyBytes = (blob.count / keyLength) * keyLength
        return stride(from: 0, to: wholeKeyBytes, by: keyLength).map { offset in
            let start = blob.index(blob.startIndex, offsetBy: offset)
            return Data(blob[start..<blob.index(start, offsetBy: keyLength)])
        }
    }

    // MARK: - Primary key

    /// Caches the key and, once per session, refreshes the archive so this device's
    /// key is always preserved and propagated. Must run on keyQueue.
    private static func adoptKeyLocked(_ data: Data) -> SymmetricKey {
        let k = SymmetricKey(data: data)
        _cachedKey = k
        if !_didRefreshArchiveSession {
            _didRefreshArchiveSession = true
            _ = refreshArchiveLocked()
        }
        return k
    }

    private static func key(creatingIfNeeded: Bool) throws -> SymmetricKey {
        #if DEBUG && os(macOS)
        if let debugEphemeralKey { return debugEphemeralKey }
        #endif
        return try keyQueue.sync {
            if let cached = _cachedKey { return cached }

            let localSlot = KeychainManager.read(account: keyAccount)
            let syncedSlot = KeychainManager.read(account: keyAccount, synchronizable: true)

            if case .found(let existing) = localSlot, existing.count == keyLength {
                if !_didMigrateSession {
                    // Only backfill a slot that is confirmed absent — never overwrite an
                    // existing key (it may be the correct one this device hasn't adopted
                    // yet) and never write over unknown state after a failed read.
                    if case .missing = syncedSlot {
                        KeychainManager.save(data: existing, account: keyAccount, synchronizable: true)
                    }
                    _didMigrateSession = true
                }
                return adoptKeyLocked(existing)
            }
            if case .found(let existing) = syncedSlot, existing.count == keyLength {
                if !_didMigrateSession {
                    if case .missing = localSlot {
                        KeychainManager.save(data: existing, account: keyAccount)
                    }
                    _didMigrateSession = true
                }
                return adoptKeyLocked(existing)
            }

            guard creatingIfNeeded else {
                throw CryptoKitError.incorrectKeySize
            }

            // A failed slot read (e.g. device locked) is unknown state, not absence.
            // Minting or promoting a key now could overwrite a real key we couldn't
            // see, and a key cached without being persisted strands everything it
            // encrypts. Refuse until the Keychain is readable.
            guard !localSlot.isFailure, !syncedSlot.isFailure else {
                throw CryptoKitError.incorrectKeySize
            }

            // Neither slot has a key yet. If iCloud is signed in, give iCloud Keychain a
            // short window to deliver an existing key (slot or archive) from another
            // device before minting a new one — a fresh key here splits the key set.
            let iCloudSignedIn = FileManager.default.ubiquityIdentityToken != nil
            let retryCount = iCloudSignedIn ? 8 : 0
            for _ in 0..<retryCount {
                Thread.sleep(forTimeInterval: 0.5)
                if case .found(let existing) = KeychainManager.read(account: keyAccount, synchronizable: true),
                   existing.count == keyLength {
                    if case .missing = KeychainManager.read(account: keyAccount) {
                        KeychainManager.save(data: existing, account: keyAccount)
                    }
                    _didMigrateSession = true
                    return adoptKeyLocked(existing)
                }
                if let archived = refreshArchiveLocked().last {
                    return adoptArchivedKeyLocked(archived)
                }
            }
            // Also covers the no-iCloud path (retryCount == 0): an archived key always
            // beats minting a fresh one.
            if let archived = refreshArchiveLocked().last {
                return adoptArchivedKeyLocked(archived)
            }

            var bytes = [UInt8](repeating: 0, count: keyLength)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let data = Data(bytes)
            KeychainManager.save(data: data, account: keyAccount)
            KeychainManager.save(data: data, account: keyAccount, synchronizable: true)
            _didMigrateSession = true
            let minted = SymmetricKey(data: data)
            _cachedKey = minted
            // Archive the fresh key immediately — bypass any cached snapshot so it can
            // never exist only in the live slots.
            _didRefreshArchiveSession = true
            _ = refreshArchiveLocked()
            return minted
        }
    }

    // MARK: - Diagnostics

    #if DEBUG
    /// Human-readable key-state report for the Developer settings section. Never
    /// exposes key material — keys appear only as SHA256-prefix fingerprints.
    static func diagnosticsReport() -> String {
        keyQueue.sync {
            func fingerprint(_ data: Data) -> String {
                let digest = SHA256.hash(data: data)
                return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
            }
            func describe(_ read: KeychainManager.ReadResult) -> String {
                switch read {
                case .found(let data):
                    return data.count == keyLength ? "found (\(fingerprint(data)))" : "found but wrong size (\(data.count)B)"
                case .missing: return "missing"
                case .failure(let status): return "READ FAILED (OSStatus \(status))"
                }
            }
            let localSlot = KeychainManager.read(account: keyAccount)
            let syncedSlot = KeychainManager.read(account: keyAccount, synchronizable: true)
            let localArchive = KeychainManager.read(account: archiveAccount)
            let syncedArchive = KeychainManager.read(account: archiveAccount, synchronizable: true)
            let localKeys = parseArchive(localArchive.data)
            let syncedKeys = parseArchive(syncedArchive.data)
            let distinct = Set(localKeys + syncedKeys + [localSlot, syncedSlot].compactMap(\.data))
            let iCloud = FileManager.default.ubiquityIdentityToken != nil ? "signed in" : "NOT signed in"

            return """
            live local slot: \(describe(localSlot))
            live synced slot: \(describe(syncedSlot))
            local archive: \(localArchive.isFailure ? "READ FAILED" : "\(localKeys.count) key(s)") \(localKeys.map(fingerprint).joined(separator: ", "))
            synced archive: \(syncedArchive.isFailure ? "READ FAILED" : "\(syncedKeys.count) key(s)") \(syncedKeys.map(fingerprint).joined(separator: ", "))
            distinct keys reachable: \(distinct.count)
            iCloud account: \(iCloud)
            """
        }
    }
    #endif

    /// Promotes an archived key into both live slots and adopts it. Must run on keyQueue.
    private static func adoptArchivedKeyLocked(_ data: Data) -> SymmetricKey {
        KeychainManager.save(data: data, account: keyAccount)
        KeychainManager.save(data: data, account: keyAccount, synchronizable: true)
        _didMigrateSession = true
        return adoptKeyLocked(data)
    }
}
