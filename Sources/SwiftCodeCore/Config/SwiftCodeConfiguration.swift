import Foundation

/// Provider + model selection for a specific cognitive role.
public struct ModelRoleAssignment: Codable, Sendable, Equatable {
    public var provider: String
    public var model: String
    public var baseURL: String?
    public var maxTokens: Int
    public var temperature: Double

    public init(
        provider: String,
        model: String,
        baseURL: String? = nil,
        maxTokens: Int = 8192,
        temperature: Double = 0.2
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// Multi-model cognitive routing configuration (FR-2.2).
public struct ModelRoutingConfig: Codable, Sendable, Equatable {
    public var architect: ModelRoleAssignment
    public var coder: ModelRoleAssignment
    public var utility: ModelRoleAssignment
    public var fallback: ModelRoleAssignment?

    public init(
        architect: ModelRoleAssignment = .init(provider: "anthropic", model: "claude-sonnet-4-5"),
        coder: ModelRoleAssignment = .init(provider: "anthropic", model: "claude-sonnet-4-5"),
        utility: ModelRoleAssignment = .init(provider: "ollama", model: "qwen2.5-coder:7b"),
        fallback: ModelRoleAssignment? = nil
    ) {
        self.architect = architect
        self.coder = coder
        self.utility = utility
        self.fallback = fallback
    }
}

/// Sandbox settings in `config.json`.
public struct SandboxConfig: Codable, Sendable, Equatable {
    public var defaultTier: SandboxTier
    public var allowNetworkInShell: Bool
    public var vmImageDirectory: String

    public init(
        defaultTier: SandboxTier = .seatbelt,
        allowNetworkInShell: Bool = false,
        vmImageDirectory: String = "~/.swiftcode/vm-images/ubuntu-swift6"
    ) {
        self.defaultTier = defaultTier
        self.allowNetworkInShell = allowNetworkInShell
        self.vmImageDirectory = vmImageDirectory
    }
}

/// Shadow-Git checkpoint retention settings.
public struct CheckpointConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var maxSnapshotsPerSession: Int

    public init(enabled: Bool = true, maxSnapshotsPerSession: Int = 100) {
        self.enabled = enabled
        self.maxSnapshotsPerSession = maxSnapshotsPerSession
    }
}

/// External MCP server configuration entry.
public struct MCPServerConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var transport: String
    public var command: String?
    public var args: [String]
    public var url: String?
    public var enabled: Bool

    public init(
        name: String,
        transport: String = "stdio",
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        enabled: Bool = true
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.enabled = enabled
    }
}

/// Always-on daemon, webhook, and chat bridge configuration.
public struct DaemonConfig: Codable, Sendable, Equatable {
    public var socketPath: String
    public var webhookHost: String
    public var webhookPort: Int
    public var telegramEnabled: Bool
    public var discordEnabled: Bool
    public var slackEnabled: Bool
    public var shortcutsEnabled: Bool

    public init(
        socketPath: String = "~/.swiftcode/daemon.sock",
        webhookHost: String = "127.0.0.1",
        webhookPort: Int = 8787,
        telegramEnabled: Bool = false,
        discordEnabled: Bool = false,
        slackEnabled: Bool = false,
        shortcutsEnabled: Bool = true
    ) {
        self.socketPath = socketPath
        self.webhookHost = webhookHost
        self.webhookPort = webhookPort
        self.telegramEnabled = telegramEnabled
        self.discordEnabled = discordEnabled
        self.slackEnabled = slackEnabled
        self.shortcutsEnabled = shortcutsEnabled
    }
}

/// Top-level declarative SwiftCode configuration (`~/.swiftcode/config.json`).
public struct SwiftCodeConfiguration: Codable, Sendable, Equatable {
    public var defaultMode: AgentMode
    public var contextWindowLimit: Int
    public var compactionThresholdRatio: Double
    public var maxAutoFixRetries: Int
    public var models: ModelRoutingConfig
    public var sandbox: SandboxConfig
    public var permissions: PermissionPolicyConfig
    public var checkpoints: CheckpointConfig
    public var daemon: DaemonConfig
    public var mcpServers: [MCPServerConfig]
    public var verificationCommands: [String]

    public init(
        defaultMode: AgentMode = .plan,
        contextWindowLimit: Int = 200_000,
        compactionThresholdRatio: Double = 0.80,
        maxAutoFixRetries: Int = 3,
        models: ModelRoutingConfig = .init(),
        sandbox: SandboxConfig = .init(),
        permissions: PermissionPolicyConfig = .init(),
        checkpoints: CheckpointConfig = .init(),
        daemon: DaemonConfig = .init(),
        mcpServers: [MCPServerConfig] = [],
        verificationCommands: [String] = ["swift test"]
    ) {
        self.defaultMode = defaultMode
        self.contextWindowLimit = contextWindowLimit
        self.compactionThresholdRatio = compactionThresholdRatio
        self.maxAutoFixRetries = maxAutoFixRetries
        self.models = models
        self.sandbox = sandbox
        self.permissions = permissions
        self.checkpoints = checkpoints
        self.daemon = daemon
        self.mcpServers = mcpServers
        self.verificationCommands = verificationCommands
    }
}
