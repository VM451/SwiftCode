import Crypto
import Foundation

/// Cross-platform AES-256-GCM encrypted credential store for Linux and isolated vaults (NFR-4).
public actor EncryptedFileSecretStore: SecretStore {
    private let vaultURL: URL
    private let symmetricKey: SymmetricKey

    public init(
        vaultURL: URL = ConfigurationStore().baseDirectoryURL.appendingPathComponent("secrets.vault"),
        passphrase: String? = nil
    ) {
        self.vaultURL = vaultURL
        self.symmetricKey = Self.deriveKey(passphrase: passphrase)
    }

    public func setSecret(_ value: String, forKey key: String) async throws {
        var map = try loadVault()
        map[key] = value
        try saveVault(map)
    }

    public func getSecret(forKey key: String) async throws -> String? {
        try loadVault()[key]
    }

    public func deleteSecret(forKey key: String) async throws {
        var map = try loadVault()
        map.removeValue(forKey: key)
        try saveVault(map)
    }

    public func listKeys() async throws -> [String] {
        try loadVault().keys.sorted()
    }

    private func loadVault() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return [:]
        }
        let sealedData = try Data(contentsOf: vaultURL)
        guard let box = try? AES.GCM.SealedBox(combined: sealedData),
              let plaintext = try? AES.GCM.open(box, using: symmetricKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: plaintext) else {
            throw SecretStoreError.vaultCorrupted
        }
        return decoded
    }

    private func saveVault(_ map: [String: String]) throws {
        let dir = vaultURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plaintext = try JSONEncoder().encode(map)
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealed.combined else {
            throw SecretStoreError.encodingFailed
        }
        try combined.write(to: vaultURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
    }

    private static func deriveKey(passphrase: String?) -> SymmetricKey {
        let seed: String
        if let passphrase, !passphrase.isEmpty {
            seed = passphrase
        } else {
            let envSeed = ProcessInfo.processInfo.environment["SWIFTCODE_VAULT_KEY"]
            let user = ProcessInfo.processInfo.userName
            let host = ProcessInfo.processInfo.hostName
            seed = envSeed ?? "swiftcode:\(user)@\(host)"
        }
        let inputKey = SymmetricKey(data: Data(seed.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data("dev.swiftcode.vault.v1".utf8),
            info: Data("aes-256-gcm".utf8),
            outputByteCount: 32
        )
    }
}
