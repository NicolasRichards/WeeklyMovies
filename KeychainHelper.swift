import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.weeklyMovies"
    private let account = "tmdbAPIKey"

    /// Stores the key as a synced item, updating it in place or adding it.
    /// Returns false if nothing was stored; any existing copy is left intact.
    @discardableResult
    func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        let syncedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true
        ]
        var status = SecItemUpdate(syncedQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = syncedQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }

        // Only now that the synced copy exists, drop any pre-sync local-only item
        // so it can't be read back instead of the new key.
        let localQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(localQuery as CFDictionary)
        return true
    }

    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let result = item as? [String: Any],
              let data = result[kSecValueData as String] as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        // Migrate a pre-sync local-only item so the key follows the user to new devices
        let isSynced = (result[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false
        if !isSynced {
            saveAPIKey(key)
        }
        return key
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
