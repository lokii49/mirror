import CryptoKit
import Foundation
import Security

enum MirrorEncryption {
    private static let keyAccount = "mirror_content_key_v1"
    private static let textPrefix = "mirror:v1:"
    static let unavailableText = "[Encrypted entry unavailable on this device]"

    private nonisolated(unsafe) static var _cachedKey: SymmetricKey? = nil
    private nonisolated(unsafe) static var _didMigrateSession = false
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
        return try AES.GCM.open(box, using: key(creatingIfNeeded: false))
    }

    private static func key(creatingIfNeeded: Bool) throws -> SymmetricKey {
        try keyQueue.sync {
            if let cached = _cachedKey { return cached }

            if let existing = KeychainManager.loadData(account: keyAccount), existing.count == 32 {
                if !_didMigrateSession {
                    KeychainManager.save(data: existing, account: keyAccount, synchronizable: true)
                    _didMigrateSession = true
                }
                let k = SymmetricKey(data: existing)
                _cachedKey = k
                return k
            }
            if let existing = KeychainManager.loadData(account: keyAccount, synchronizable: true), existing.count == 32 {
                if !_didMigrateSession {
                    KeychainManager.save(data: existing, account: keyAccount)
                    _didMigrateSession = true
                }
                let k = SymmetricKey(data: existing)
                _cachedKey = k
                return k
            }

            guard creatingIfNeeded else {
                throw CryptoKitError.incorrectKeySize
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
