import Foundation

/// Execution mode governing whether mutating tools are permitted.
public enum AgentMode: String, Codable, Sendable, CaseIterable {
    /// Read-only discovery, AST/LSP inspection, and architectural planning.
    case plan
    /// Full workspace mutation, shell execution, and verification capabilities.
    case build
}

/// Risk classification assigned to every tool for HITL approval evaluation.
public enum ToolRiskLevel: Int, Comparable, Codable, Sendable, CaseIterable {
    case readOnly = 0
    case workspaceMutation = 1
    case shellExecution = 2
    case networkAccess = 3
    case systemModification = 4

    public static func < (lhs: ToolRiskLevel, rhs: ToolRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .readOnly: "Read Only"
        case .workspaceMutation: "Workspace Mutation"
        case .shellExecution: "Shell Execution"
        case .networkAccess: "Network Access"
        case .systemModification: "System Modification"
        }
    }
}
