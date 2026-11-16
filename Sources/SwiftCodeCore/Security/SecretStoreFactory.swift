import Foundation

/// Resolves the platform-appropriate secret store and reads credentials safely.
public enum SecretStoreFactory {
    /// Returns `KeychainSecretStore` on Apple platforms and `EncryptedFileSecretStore` on Linux.
    public static func makeDefault() -> any SecretStore {
        #if canImport(Security)
        return KeychainSecretStore()
        #else
        return EncryptedFileSecretStore()
        #endif
    }

    /// Resolves a secret from environment variable first, falling back to the secure store.
    public static func resolveSecret(
        key: String,
        store: any SecretStore = makeDefault()
    ) async -> String? {
        if let envValue = ProcessInfo.processInfo.environment[key], !envValue.isEmpty {
            return envValue
        }
        return try? await store.getSecret(forKey: key)
    }
}
