import Foundation
import SwiftCodeCore

/// Task submitted via webhook, Unix socket IPC, cron job, or chat bridge.
public struct InboundAgentTask: Codable, Sendable, Equatable {
    public let source: String
    public let prompt: String
    public let workspacePath: String?
    public let mode: AgentMode

    public init(source: String, prompt: String, workspacePath: String? = nil, mode: AgentMode = .plan) {
        self.source = source
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.mode = mode
    }
}

/// Execution summary returned from daemon task dispatch.
public struct TaskDispatchResult: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let summary: String
    public let sessionID: String?

    public init(accepted: Bool, summary: String, sessionID: String? = nil) {
        self.accepted = accepted
        self.summary = summary
        self.sessionID = sessionID
    }
}

/// Runtime health snapshot exposed over `/health` and `/status`.
public struct DaemonStatusSnapshot: Codable, Sendable, Equatable {
    public let running: Bool
    public let activeBridges: [String]
    public let processedTasks: Int
    public let uptimeSeconds: Int
    public let residentMemoryMB: Double

    public init(
        running: Bool,
        activeBridges: [String],
        processedTasks: Int,
        uptimeSeconds: Int,
        residentMemoryMB: Double
    ) {
        self.running = running
        self.activeBridges = activeBridges
        self.processedTasks = processedTasks
        self.uptimeSeconds = uptimeSeconds
        self.residentMemoryMB = residentMemoryMB
    }
}

public typealias DaemonTaskDispatcher = @Sendable (InboundAgentTask) async -> TaskDispatchResult
