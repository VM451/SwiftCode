import Foundation
import Testing
@testable import SwiftCodeCore

struct ConfigAndSecurityTests {
    @Test func configurationStoreRoundTripsWorkspaceAndGlobal() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("sh-home-\(UUID().uuidString)")
        let tempWork = FileManager.default.temporaryDirectory.appendingPathComponent("sh-work-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempHome)
            try? FileManager.default.removeItem(at: tempWork)
        }

        let store = ConfigurationStore(homeDirectory: tempHome)
        try store.ensureDirectories()
        var cfg = SwiftCodeConfiguration()
        cfg.defaultMode = .build
        cfg.models.architect = ModelRoleAssignment(provider: "anthropic", model: "claude-opus-4")
        try store.save(cfg)

        let loadedGlobal = store.load()
        #expect(loadedGlobal.defaultMode == .build)
        #expect(loadedGlobal.models.architect.model == "claude-opus-4")

        var localCfg = cfg
        localCfg.defaultMode = .plan
        let localURL = tempWork.appendingPathComponent(".swiftcode/config.json")
        try store.save(localCfg, to: localURL)

        let merged = store.load(workspaceRoot: tempWork)
        #expect(merged.defaultMode == .plan)
    }

    @Test func encryptedVaultStoresAndProtectsSecrets() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sh-vault-\(UUID().uuidString)")
            .appendingPathComponent("secrets.vault")
        defer { try? FileManager.default.removeItem(at: vaultURL.deletingLastPathComponent()) }

        let store = EncryptedFileSecretStore(vaultURL: vaultURL, passphrase: "unit-test-passphrase")
        try await store.setSecret("sk-ant-secret1234567890", forKey: SecretKey.anthropicAPIKey.rawValue)

        let fetched = try await store.getSecret(forKey: SecretKey.anthropicAPIKey.rawValue)
        #expect(fetched == "sk-ant-secret1234567890")
        #expect(try await store.listKeys() == [SecretKey.anthropicAPIKey.rawValue])

        // Ensure ciphertext on disk does not contain plaintext secret
        let rawData = try Data(contentsOf: vaultURL)
        let rawString = String(decoding: rawData, as: UTF8.self)
        #expect(rawString.contains("sk-ant-secret1234567890") == false)

        // Wrong passphrase must throw vaultCorrupted
        let wrongStore = EncryptedFileSecretStore(vaultURL: vaultURL, passphrase: "wrong-passphrase")
        await #expect(throws: SecretStoreError.self) {
            _ = try await wrongStore.getSecret(forKey: SecretKey.anthropicAPIKey.rawValue)
        }

        try await store.deleteSecret(forKey: SecretKey.anthropicAPIKey.rawValue)
        #expect(try await store.getSecret(forKey: SecretKey.anthropicAPIKey.rawValue) == nil)
    }

    @Test func webhookSignerVerifiesHMACConstantTime() {
        let payload = Data("{\"action\":\"opened\"}".utf8)
        let sig = WebhookSigner.sign(payload: payload, secret: "top-secret")
        #expect(sig.hasPrefix("sha256="))
        #expect(WebhookSigner.verify(payload: payload, signatureHeader: sig, secret: "top-secret"))
        #expect(WebhookSigner.verify(payload: payload, signatureHeader: sig, secret: "wrong") == false)
        #expect(WebhookSigner.verify(payload: Data("tampered".utf8), signatureHeader: sig, secret: "top-secret") == false)
    }

    @Test func secretRedactorMasksCredentialsAndPEMKeys() {
        let input = """
        OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz123456
        ANTHROPIC=sk-ant-api03-secretsecretsecret12345
        -----BEGIN EC PRIVATE KEY-----
        MHcCAQEEIPfakekeymaterial1234567890
        -----END EC PRIVATE KEY-----
        safe_line=hello_world
        """
        let result = SecretRedactor().redact(input)
        #expect(result.redactedCount >= 3)
        #expect(result.text.contains("sk-proj-") == false)
        #expect(result.text.contains("sk-ant-") == false)
        #expect(result.text.contains("MHcCAQEEIP") == false)
        #expect(result.text.contains("safe_line=hello_world"))
    }
}
