import Foundation

/// Invocation request for a named tool emitted by an LLM provider.
public struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Execution result returned by a `SwiftCodeTool`.
public struct ToolOutput: Codable, Sendable, Equatable {
    public let content: String
    public let isError: Bool
    public let metadata: [String: String]

    public init(content: String, isError: Bool = false, metadata: [String: String] = [:]) {
        self.content = content
        self.isError = isError
        self.metadata = metadata
    }

    public static func success(_ content: String, metadata: [String: String] = [:]) -> ToolOutput {
        ToolOutput(content: content, isError: false, metadata: metadata)
    }

    public static func failure(_ message: String, metadata: [String: String] = [:]) -> ToolOutput {
        ToolOutput(content: message, isError: true, metadata: metadata)
    }
}

/// Runtime context passed into every `SwiftCodeTool.execute` call.
public struct ToolContext: Sendable {
    public let sessionID: UUID
    public let workspaceRoot: URL
    public let mode: AgentMode
    public let sandboxPolicy: SandboxPolicy
    public let timeoutSeconds: TimeInterval

    public init(
        sessionID: UUID,
        workspaceRoot: URL,
        mode: AgentMode,
        sandboxPolicy: SandboxPolicy,
        timeoutSeconds: TimeInterval = 60
    ) {
        self.sessionID = sessionID
        self.workspaceRoot = workspaceRoot
        self.mode = mode
        self.sandboxPolicy = sandboxPolicy
        self.timeoutSeconds = timeoutSeconds
    }
}
