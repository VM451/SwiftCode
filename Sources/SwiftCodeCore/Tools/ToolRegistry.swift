import Foundation

/// Mode-aware tool registry enforcing Plan (read-only) vs. Build (read/write) isolation (FR-1.2).
public actor ToolRegistry {
    private var tools: [String: any SwiftCodeTool] = [:]

    public init(tools: [any SwiftCodeTool] = []) {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    /// Registers built-in Plan & Build tools using defaults.
    public static func makeDefault(sandbox: SandboxExecutor = SandboxExecutor()) -> ToolRegistry {
        ToolRegistry(tools: [
            ReadFileTool(),
            ListDirectoryTool(),
            GlobSearchTool(),
            GrepSearchTool(),
            GitStatusTool(),
            GitDiffTool(),
            ASTOutlineTool(),
            ASTFindSymbolTool(),
            WebFetchTool(),
            AskUserTool(),
            WriteFileTool(),
            PatchFileTool(),
            DeleteFileTool(),
            ExecuteShellTool(sandbox: sandbox),
            GitCommitTool(),
            RunSwiftVerifyTool(sandbox: sandbox),
        ])
    }

    public func register(_ tool: any SwiftCodeTool) {
        tools[tool.name] = tool
    }

    public func register(skill: any SwiftCodeSkill) {
        for tool in skill.tools {
            tools[tool.name] = tool
        }
    }

    public func tool(named name: String) -> (any SwiftCodeTool)? {
        tools[name]
    }

    /// Physically filters out mutating/execution tools when in Plan Mode.
    public func definitions(for mode: AgentMode) -> [LLMToolDefinition] {
        allowedTools(for: mode).map { tool in
            LLMToolDefinition(
                name: tool.name,
                description: tool.description,
                inputSchemaJSON: tool.inputSchemaJSON
            )
        }
    }

    public func allowedTools(for mode: AgentMode) -> [any SwiftCodeTool] {
        let all = tools.values.sorted { $0.name < $1.name }
        switch mode {
        case .plan:
            return all.filter { $0.riskLevel == .readOnly }
        case .build:
            return all
        }
    }

    /// Checks whether a tool is permitted in the given `AgentMode`.
    public func isPermitted(toolName: String, in mode: AgentMode) -> Bool {
        guard let tool = tools[toolName] else { return false }
        return mode == .build || tool.riskLevel == .readOnly
    }
}
