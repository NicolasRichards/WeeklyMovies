import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.weeklyMovies"
    private let account = "tmdbAPIKey"

    func saveAPIKey(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        // Delete any existing item first (local or synced)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
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
