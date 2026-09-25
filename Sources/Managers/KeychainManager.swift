import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()

    private let serviceName = "com.forum.fourd4y"

    private init() {}

    // MARK: - Save

    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        // Delete any existing item
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            print("[Keychain] Saved: \(key)")
            return true
        } else {
            print("[Keychain] Failed to save \(key): \(status)")
            return false
        }
    }

    // MARK: - Load

    func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                print("[Keychain] Failed to load \(key): \(status)")
            }
            return nil
        }

        return value
    }

    // MARK: - Delete

    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            print("[Keychain] Failed to delete \(key): \(status)")
            return false
        }
    }

    // MARK: - Clear All

    func clearAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            print("[Keychain] Cleared all items")
            return true
        } else {
            print("[Keychain] Failed to clear all: \(status)")
            return false
        }
    }
}
