import Foundation

/// Configured rule for a tool risk level or explicit tool pattern.
public enum PermissionRule: String, Codable, Sendable, CaseIterable {
    case alwaysAllow
    case askEveryTime
    case allowForSession
    case deny
}

/// Interactive response chosen by a human reviewer during an HITL prompt.
public enum ApprovalResolution: Sendable, Equatable {
    case allowOnce
    case allowForSession
    case alwaysAllowPattern(String)
    case deny(String)
    case editArguments(String)

    public var isApproved: Bool {
        switch self {
        case .allowOnce, .allowForSession, .alwaysAllowPattern, .editArguments:
            true
        case .deny:
            false
        }
    }
}

/// Declarative per-risk permission rules and command allow/deny patterns (FR-5.1).
public struct PermissionPolicyConfig: Codable, Sendable, Equatable {
    public var readOnly: PermissionRule
    public var workspaceMutation: PermissionRule
    public var shellExecution: PermissionRule
    public var networkAccess: PermissionRule
    public var systemModification: PermissionRule
    public var autoAllowCommands: [String]
    public var denyPatterns: [String]

    public init(
        readOnly: PermissionRule = .alwaysAllow,
        workspaceMutation: PermissionRule = .askEveryTime,
        shellExecution: PermissionRule = .askEveryTime,
        networkAccess: PermissionRule = .askEveryTime,
        systemModification: PermissionRule = .askEveryTime,
        autoAllowCommands: [String] = ["swift build", "swift test", "git status", "git diff *"],
        denyPatterns: [String] = ["rm -rf /", "sudo *", ":(){ :|:& };:"]
    ) {
        self.readOnly = readOnly
        self.workspaceMutation = workspaceMutation
        self.shellExecution = shellExecution
        self.networkAccess = networkAccess
        self.systemModification = systemModification
        self.autoAllowCommands = autoAllowCommands
        self.denyPatterns = denyPatterns
    }

    public func rule(for risk: ToolRiskLevel) -> PermissionRule {
        switch risk {
        case .readOnly: readOnly
        case .workspaceMutation: workspaceMutation
        case .shellExecution: shellExecution
        case .networkAccess: networkAccess
        case .systemModification: systemModification
        }
    }
}
