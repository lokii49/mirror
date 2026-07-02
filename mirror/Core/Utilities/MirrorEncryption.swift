import CryptoKit
import Foundation
import Security

enum MirrorEncryption {
    private static let keyAccount = "mirror_content_key_v1"
    private static let archiveAccount = "mirror_content_key_archive_v1"
    private static let textPrefix = "mirror:v1:"
    static let unavailableText = "[Encrypted entry unavailable on this device]"

    private nonisolated(unsafe) static var _cachedKey: SymmetricKey? = nil
    private nonisolated(unsafe) static var _didMigrateSession = false
    private nonisolated(unsafe) static var _cachedFallbackKeys: [Data]? = nil
    private nonisolated(unsafe) static var _fallbackKeysLoadedAt: Date? = nil
    private static let fallbackCacheWindow: TimeInterval = 30
    private static let keyQueue = DispatchQueue(label: "com.mirror.encryption.key")

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

    private static func isEncryptedString(_ value: String) -> Bool {
        value.hasPrefix(textPrefix)
    }

    private static func encryptData(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key(creatingIfNeeded: true))
        return sealed.combined ?? data
    }

    private static func decryptData(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        let primary = try key(creatingIfNeeded: false)
        if let opened = try? AES.GCM.open(box, using: primary) { return opened }

        // Primary key failed — the ciphertext may predate a key rotation caused by the
        // old clobber bug. Try every other key we can still reach (both Keychain slots
        // plus the append-only archive) before giving up.
        let primaryData = primary.withUnsafeBytes { Data($0) }
        for candidate in fallbackKeyData() where candidate != primaryData {
            if let opened = try? AES.GCM.open(box, using: SymmetricKey(data: candidate)) {
                return opened
            }
        }
        throw CryptoKitError.authenticationFailure
    }

    /// Every distinct content key reachable on this device: the archive (local + synced)
    /// merged with whatever currently sits in the two live Keychain slots. Any newly seen
    /// key is appended to the archive in both slots so it survives future slot overwrites
    /// and propagates to other devices via iCloud Keychain.
    private static func fallbackKeyData() -> [Data] {
        keyQueue.sync { fallbackKeyDataLocked() }
    }

    private static func fallbackKeyDataLocked() -> [Data] {
        if let cached = _cachedFallbackKeys,
           let loadedAt = _fallbackKeysLoadedAt,
           Date().timeIntervalSince(loadedAt) < fallbackCacheWindow {
            return cached
        }

        let localArchive = parseArchive(KeychainManager.loadData(account: archiveAccount))
        let syncedArchive = parseArchive(KeychainManager.loadData(account: archiveAccount, synchronizable: true))

        var keys: [Data] = []
        for candidate in localArchive + syncedArchive where candidate.count == 32 && !keys.contains(candidate) {
            keys.append(candidate)
        }
        for synchronizable in [false, true] {
            if let slot = KeychainManager.loadData(account: keyAccount, synchronizable: synchronizable),
               slot.count == 32, !keys.contains(slot) {
                keys.append(slot)
            }
        }

        let blob = keys.reduce(Data(), +)
        if keys != localArchive { KeychainManager.save(data: blob, account: archiveAccount) }
        if keys != syncedArchive { KeychainManager.save(data: blob, account: archiveAccount, synchronizable: true) }

        _cachedFallbackKeys = keys
        _fallbackKeysLoadedAt = Date()
        return keys
    }

    private static func parseArchive(_ blob: Data?) -> [Data] {
        guard let blob, !blob.isEmpty, blob.count % 32 == 0 else { return [] }
        var keys: [Data] = []
        var index = blob.startIndex
        while index < blob.endIndex {
            let next = blob.index(index, offsetBy: 32)
            keys.append(Data(blob[index..<next]))
            index = next
        }
        return keys
    }

    private static func key(creatingIfNeeded: Bool) throws -> SymmetricKey {
        try keyQueue.sync {
            // Keep the key archive fresh on every device, including ones where decryption
            // never fails — that's how a key stranded on an old device reaches this one.
            defer { _ = fallbackKeyDataLocked() }

            if let cached = _cachedKey { return cached }

            if let existing = KeychainManager.loadData(account: keyAccount), existing.count == 32 {
                if !_didMigrateSession {
                    // Only backfill the synced slot if it's empty — never clobber a key that's already there,
                    // it may be the correct one this device just hasn't received yet.
                    if KeychainManager.loadData(account: keyAccount, synchronizable: true) == nil {
                        KeychainManager.save(data: existing, account: keyAccount, synchronizable: true)
                    }
                    _didMigrateSession = true
                }
                let k = SymmetricKey(data: existing)
                _cachedKey = k
                return k
            }
            if let existing = KeychainManager.loadData(account: keyAccount, synchronizable: true), existing.count == 32 {
                if !_didMigrateSession {
                    if KeychainManager.loadData(account: keyAccount) == nil {
                        KeychainManager.save(data: existing, account: keyAccount)
                    }
                    _didMigrateSession = true
                }
                let k = SymmetricKey(data: existing)
                _cachedKey = k
                return k
            }

            guard creatingIfNeeded else {
                throw CryptoKitError.incorrectKeySize
            }

            // Neither slot has a key yet. If iCloud is signed in, give iCloud Keychain a short
            // window to deliver an existing key from another device before minting a new one —
            // generating here permanently strands ciphertext encrypted under a key that lived
            // only in the cloud. Skip the wait entirely if there's no iCloud account (nothing to sync).
            let iCloudSignedIn = FileManager.default.ubiquityIdentityToken != nil
            let retryCount = iCloudSignedIn ? 8 : 0
            for _ in 0..<retryCount {
                Thread.sleep(forTimeInterval: 0.5)
                if let existing = KeychainManager.loadData(account: keyAccount, synchronizable: true), existing.count == 32 {
                    let k = SymmetricKey(data: existing)
                    _cachedKey = k
                    _didMigrateSession = true
                    if KeychainManager.loadData(account: keyAccount) == nil {
                        KeychainManager.save(data: existing, account: keyAccount)
                    }
                    return k
                }
            }

            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let data = Data(bytes)
            KeychainManager.save(data: data, account: keyAccount)
            KeychainManager.save(data: data, account: keyAccount, synchronizable: true)
            let k = SymmetricKey(data: data)
            _cachedKey = k
            _didMigrateSession = true
            return k
        }
    }
}
