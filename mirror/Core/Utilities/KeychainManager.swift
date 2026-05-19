import Foundation
import Security

enum KeychainManager {
    private static let service = "com.lokesh.mirror"

    static func save(data: Data, account: String, synchronizable: Bool = false) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func loadData(account: String, synchronizable: Bool = false) -> Data? {
        if let exact = loadData(account: account, synchronizableValue: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any) {
            return exact
        }
        return loadData(account: account, synchronizableValue: kSecAttrSynchronizableAny)
    }

    private static func loadData(account: String, synchronizableValue: Any) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizableValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
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
