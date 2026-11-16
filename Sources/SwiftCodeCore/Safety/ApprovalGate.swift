import Foundation

/// Human-in-the-loop approval prompt context sent to CLI TUI, daemon, or chat bridges.
public struct ApprovalRequest: Sendable, Equatable {
    public let call: ToolCall
    public let riskLevel: ToolRiskLevel
    public let diffPreview: String?
    public let summary: String

    public init(call: ToolCall, riskLevel: ToolRiskLevel, diffPreview: String?, summary: String) {
        self.call = call
        self.riskLevel = riskLevel
        self.diffPreview = diffPreview
        self.summary = summary
    }
}

/// Async prompt callback provided by the presentation layer (`TUI`, `TelegramBridge`, or `--yes`).
public typealias ApprovalHandler = @Sendable (ApprovalRequest) async -> ApprovalResolution

/// Evaluates permission policies, session approvals, glob auto-allow commands, and deny rules (FR-5.1).
public actor ApprovalGate {
    private var policy: PermissionPolicyConfig
    private var sessionAllowedTools: Set<String> = []
    private var sessionAllowedPatterns: [String] = []
    private let handler: ApprovalHandler

    public init(
        policy: PermissionPolicyConfig = PermissionPolicyConfig(),
        handler: @escaping ApprovalHandler = { _ in .deny("No interactive approval handler configured.") }
    ) {
        self.policy = policy
        self.handler = handler
    }

    public func updatePolicy(_ newPolicy: PermissionPolicyConfig) {
        self.policy = newPolicy
    }

    /// Evaluates whether `call` may proceed, optionally requesting interactive human approval and returning edited args.
    public func authorize(
        call: ToolCall,
        risk: ToolRiskLevel,
        workspaceRoot: URL
    ) async -> (approved: Bool, effectiveCall: ToolCall, reason: String?) {
        if let command = extractShellCommand(from: call), matchesAnyPattern(command, patterns: policy.denyPatterns) {
            return (false, call, "Blocked by deny policy pattern.")
        }

        let rule = policy.rule(for: risk)
        switch rule {
        case .alwaysAllow:
            return (true, call, "Policy: alwaysAllow")
        case .deny:
            return (false, call, "Denied by policy rule for \(risk.displayName)")
        case .allowForSession, .askEveryTime:
            if sessionAllowedTools.contains(call.name) {
                return (true, call, "Allowed for session")
            }
            if let command = extractShellCommand(from: call),
               matchesAnyPattern(command, patterns: policy.autoAllowCommands + sessionAllowedPatterns) {
                return (true, call, "Matched auto-allow pattern")
            }
            if rule == .allowForSession {
                sessionAllowedTools.insert(call.name)
                return (true, call, "Allowed for session")
            }
        }

        let diff = computeDiffPreview(call: call, workspaceRoot: workspaceRoot)
        let summary = "\(call.name) [\(risk.displayName)]"
        let request = ApprovalRequest(call: call, riskLevel: risk, diffPreview: diff, summary: summary)
        let resolution = await handler(request)

        switch resolution {
        case .allowOnce:
            return (true, call, "Allowed once")
        case .allowForSession:
            sessionAllowedTools.insert(call.name)
            return (true, call, "Allowed for session")
        case .alwaysAllowPattern(let pattern):
            sessionAllowedPatterns.append(pattern)
            return (true, call, "Allowed pattern '\(pattern)'")
        case .editArguments(let newArgs):
            let updated = ToolCall(id: call.id, name: call.name, argumentsJSON: newArgs)
            return (true, updated, "Approved with edited arguments")
        case .deny(let feedback):
            return (false, call, feedback)
        }
    }

    private func extractShellCommand(from call: ToolCall) -> String? {
        guard call.name == "executeShell" || call.name == "runSwiftVerify",
              let args = try? ToolArgumentDecoder.decodeObject(call.argumentsJSON) else { return nil }
        return args["command"] as? String
    }

    private func matchesAnyPattern(_ value: String, patterns: [String]) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in patterns {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            if trimmed.range(of: "^\(escaped)$", options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private func computeDiffPreview(call: ToolCall, workspaceRoot: URL) -> String? {
        guard call.name == "writeFile" || call.name == "patchFile",
              let args = try? ToolArgumentDecoder.decodeObject(call.argumentsJSON),
              let path = args["path"] as? String,
              let url = try? ToolArgumentDecoder.resolveSafePath(path, workspaceRoot: workspaceRoot) else {
            return nil
        }
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if call.name == "writeFile", let updated = args["content"] as? String {
            return UnifiedDiffEngine.diff(path: path, original: original, updated: updated).unifiedText
        }
        if call.name == "patchFile",
           let search = args["search"] as? String,
           let replace = args["replace"] as? String,
           let range = original.range(of: search) {
            let updated = original.replacingCharacters(in: range, with: replace)
            return UnifiedDiffEngine.diff(path: path, original: original, updated: updated).unifiedText
        }
        return nil
    }
}
