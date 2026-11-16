import Foundation

/// Well-known credential identifiers managed by SwiftCode.
public enum SecretKey: String, CaseIterable, Sendable {
    case anthropicAPIKey = "ANTHROPIC_API_KEY"
    case openAIAPIKey = "OPENAI_API_KEY"
    case geminiAPIKey = "GEMINI_API_KEY"
    case openRouterAPIKey = "OPENROUTER_API_KEY"
    case telegramBotToken = "TELEGRAM_BOT_TOKEN"
    case discordBotToken = "DISCORD_BOT_TOKEN"
    case slackAppToken = "SLACK_APP_TOKEN"
    case slackBotToken = "SLACK_BOT_TOKEN"
    case githubWebhookSecret = "GITHUB_WEBHOOK_SECRET"
}

/// Errors emitted by secret storage backends.
public enum SecretStoreError: Error, LocalizedError, Sendable {
    case encodingFailed
    case osStatus(Int32, String)
    case vaultCorrupted

    public var errorDescription: String? {
        switch self {
        case .encodingFailed: "Failed to encode or decode secret payload."
        case .osStatus(let code, let context): "Keychain error (\(code)) during \(context)."
        case .vaultCorrupted: "Encrypted secret vault could not be decrypted or verified."
        }
    }
}

/// Secure credential store protocol (NFR-4).
public protocol SecretStore: Sendable {
    func setSecret(_ value: String, forKey key: String) async throws
    func getSecret(forKey key: String) async throws -> String?
    func deleteSecret(forKey key: String) async throws
    func listKeys() async throws -> [String]
}

/// Thread-safe in-memory secret store for isolated unit tests.
public actor InMemorySecretStore: SecretStore {
    private var storage: [String: String]

    public init(initial: [String: String] = [:]) {
        self.storage = initial
    }

    public func setSecret(_ value: String, forKey key: String) async throws {
        storage[key] = value
    }

    public func getSecret(forKey key: String) async throws -> String? {
        storage[key]
    }

    public func deleteSecret(forKey key: String) async throws {
        storage.removeValue(forKey: key)
    }

    public func listKeys() async throws -> [String] {
        storage.keys.sorted()
    }
}
