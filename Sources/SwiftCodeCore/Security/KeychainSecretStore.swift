import Foundation
#if canImport(Security)
import Security

/// Native macOS Keychain implementation backed by `Security.framework` (NFR-4).
public actor KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "dev.swiftcode.secrets") {
        self.service = service
    }

    public func setSecret(_ value: String, forKey key: String) async throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretStoreError.osStatus(addStatus, "SecItemAdd")
            }
        } else if status != errSecSuccess {
            throw SecretStoreError.osStatus(status, "SecItemUpdate")
        }
    }

    public func getSecret(forKey key: String) async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecretStoreError.osStatus(status, "SecItemCopyMatching")
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteSecret(forKey key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.osStatus(status, "SecItemDelete")
        }
    }

    public func listKeys() async throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw SecretStoreError.osStatus(status, "SecItemCopyMatching(list)")
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }
}
#endif
