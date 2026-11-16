import Foundation

/// SwiftSyntax AST outline tool returning declarations and line ranges for any Swift file.
public struct ASTOutlineTool: SwiftCodeTool, Sendable {
    public let name = "astOutline"
    public let description = "Inspect Swift file declarations and exact line ranges using SwiftSyntax."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let path = args["path"] as? String else { return .failure("Missing 'path'") }
        let url = try ToolArgumentDecoder.resolveSafePath(path, workspaceRoot: context.workspaceRoot)
        let symbols = try SwiftASTInspector().outline(fileURL: url, relativeTo: context.workspaceRoot)
        let lines = symbols.map { "L\($0.startLine)-\($0.endLine) [\($0.kind.rawValue)] \($0.signature)" }
        return .success(lines.isEmpty ? "No declarations found." : lines.joined(separator: "\n"))
    }
}

/// Searches Swift declarations across the workspace using SwiftSyntax.
public struct ASTFindSymbolTool: SwiftCodeTool, Sendable {
    public let name = "astSymbolSearch"
    public let description = "Find Swift structs, classes, actors, protocols, enums, and functions across the workspace."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let query = args["query"] as? String else { return .failure("Missing 'query'") }
        let hits = SwiftASTInspector().findSymbol(named: query, in: context.workspaceRoot)
        let lines = hits.map { "\($0.relativePath):\($0.startLine)-\($0.endLine) [\($0.kind.rawValue)] \($0.signature)" }
        return .success(lines.isEmpty ? "No matching Swift symbols." : lines.joined(separator: "\n"))
    }
}

/// Runs shell commands inside `SandboxExecutor` (Seatbelt / Linux unshare / timeout guard).
public struct ExecuteShellTool: SwiftCodeTool, Sendable {
    public let name = "executeShell"
    public let description = "Execute a shell command inside the configured OS sandbox."
    public let riskLevel: ToolRiskLevel = .shellExecution
    public let inputSchemaJSON = """
    {"type":"object","properties":{"command":{"type":"string"},"timeoutSeconds":{"type":"integer"}},"required":["command"]}
    """
    private let sandbox: SandboxExecutor

    public init(sandbox: SandboxExecutor = SandboxExecutor()) {
        self.sandbox = sandbox
    }

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let command = args["command"] as? String, !command.isEmpty else {
            return .failure("Missing 'command'")
        }
        let timeout = TimeInterval(args["timeoutSeconds"] as? Int ?? Int(context.timeoutSeconds))
        let result = try await sandbox.execute(
            command: command,
            policy: context.sandboxPolicy,
            timeoutSeconds: timeout
        )
        var text = ""
        if !result.stdout.isEmpty { text += result.stdout }
        if !result.stderr.isEmpty { text += (text.isEmpty ? "" : "\n") + "[stderr]\n" + result.stderr }
        if result.timedOut { text += "\n[TIMED OUT after \(Int(timeout))s]" }
        let metadata = [
            "exitCode": "\(result.exitCode)",
            "durationMS": "\(result.durationMS)",
            "timedOut": "\(result.timedOut)",
        ]
        return result.exitCode == 0 && !result.timedOut
            ? .success(text.isEmpty ? "(exit 0)" : text, metadata: metadata)
            : .failure(text.isEmpty ? "Exit code \(result.exitCode)" : text, metadata: metadata)
    }
}

/// Structured compiler diagnostic extracted from `swift build`, `swift test`, or `xcodebuild` (FR-1.3).
public struct SwiftCompilerDiagnostic: Codable, Sendable, Equatable {
    public let file: String
    public let line: Int
    public let column: Int
    public let severity: String
    public let message: String
}

/// Parses Swift and Xcode build/test diagnostics cleanly for self-healing verification loops.
public enum SwiftDiagnosticParser {
    public static func parse(_ output: String) -> [SwiftCompilerDiagnostic] {
        let pattern = "^(.+?):(\\d+):(\\d+):\\s+(error|warning|note):\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return []
        }
        let ns = output as NSString
        return regex.matches(in: output, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 6,
                  let line = Int(ns.substring(with: match.range(at: 2))),
                  let col = Int(ns.substring(with: match.range(at: 3))) else { return nil }
            return SwiftCompilerDiagnostic(
                file: ns.substring(with: match.range(at: 1)),
                line: line,
                column: col,
                severity: ns.substring(with: match.range(at: 4)),
                message: ns.substring(with: match.range(at: 5))
            )
        }
    }
}

/// Runs `swift test` / `swift build` / `xcodebuild` and emits structured diagnostics.
public struct RunSwiftVerifyTool: SwiftCodeTool, Sendable {
    public let name = "runSwiftVerify"
    public let description = "Run `swift build`, `swift test`, or `xcodebuild` and return structured compiler diagnostics."
    public let riskLevel: ToolRiskLevel = .shellExecution
    public let inputSchemaJSON = """
    {"type":"object","properties":{"command":{"type":"string"}},"required":[]}
    """
    private let sandbox: SandboxExecutor

    public init(sandbox: SandboxExecutor = SandboxExecutor()) {
        self.sandbox = sandbox
    }

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = (try? ToolArgumentDecoder.decodeObject(argumentsJSON)) ?? [:]
        let command = (args["command"] as? String) ?? "swift test"
        let res = try await sandbox.execute(command: command, policy: context.sandboxPolicy, timeoutSeconds: 180)
        let combined = [res.stdout, res.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let diags = SwiftDiagnosticParser.parse(combined).filter { $0.severity == "error" }
        var summary = "Exit \(res.exitCode) in \(res.durationMS)ms"
        if !diags.isEmpty {
            let formatted = diags.prefix(20).map { "\($0.file):\($0.line):\($0.column): error: \($0.message)" }
            summary += "\nErrors:\n" + formatted.joined(separator: "\n")
        } else if !combined.isEmpty {
            summary += "\n" + String(combined.suffix(4000))
        }
        return res.exitCode == 0 ? .success(summary) : .failure(summary)
    }
}
