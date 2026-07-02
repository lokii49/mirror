import Foundation
import Security

enum KeychainManager {
    private static let service = "com.lokesh.mirror"

    /// Distinguishes "the item does not exist" from "the read failed" (e.g.
    /// errSecInteractionNotAllowed while the device is locked). Callers that
    /// rewrite data based on what they read MUST treat `.failure` as unknown
    /// state, never as absence.
    enum ReadResult {
        case found(Data)
        case missing
        case failure(OSStatus)

        var data: Data? {
            if case .found(let data) = self { return data }
            return nil
        }

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    private static func baseQuery(account: String, synchronizable: Bool) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
    }

    /// Update-in-place, falling back to add only when the item doesn't exist.
    /// Never delete-then-add: a kill between those two calls would erase the item.
    static func save(data: Data, account: String, synchronizable: Bool = false) {
        let query = baseQuery(account: account, synchronizable: synchronizable)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    /// Exact-slot read: matches only the requested synchronizable variant, so the
    /// local and iCloud-synced copies of an account are never conflated.
    static func read(account: String, synchronizable: Bool = false) -> ReadResult {
        var query = baseQuery(account: account, synchronizable: synchronizable)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failure(errSecInternalError) }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .failure(status)
        }
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }
}
