import Foundation

/// Immutable event emitted by `OrchestratorActor` for replay, TUI, and SwiftUI observation.
public struct AgentEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let kind: AgentEventKind

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date = Date(),
        kind: AgentEventKind
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
    }
}

/// Discriminated union of all agent loop state transitions (FR-1.1).
public enum AgentEventKind: Codable, Sendable, Equatable {
    case userMessage(text: String)
    case reasoningTokenDelta(delta: String)
    case assistantTokenDelta(delta: String)
    case toolCallProposed(call: ToolCall, risk: ToolRiskLevel)
    case approvalRequested(call: ToolCall, risk: ToolRiskLevel, diffPreview: String?)
    case approvalResolved(callID: String, approved: Bool, reason: String?)
    case toolExecutionStarted(call: ToolCall)
    case toolExecutionCompleted(callID: String, name: String, output: ToolOutput, durationMS: Int)
    case checkpointCreated(commitHash: String, label: String)
    case compactionTriggered(beforeTokens: Int, afterTokens: Int)
    case subAgentSpawned(subAgentID: UUID, role: String, task: String)
    case subAgentCompleted(subAgentID: UUID, summary: String)
    case modeChanged(from: AgentMode, to: AgentMode)
    case verificationStarted(command: String)
    case verificationCompleted(passed: Bool, summary: String)
    case errorEncountered(message: String)
    case turnCompleted(usage: TokenUsage)
}
