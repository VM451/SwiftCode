import Foundation

/// Built-in tool allowing `OrchestratorActor` to delegate parallel tasks to `SubAgentActor` workers (FR-7.1).
public struct DelegateTaskTool: SwiftCodeTool, Sendable {
    public let name = "delegateTask"
    public let description = "Delegate a focused subtask to an isolated SubAgentActor (optionally in an isolated git worktree)."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"role":{"type":"string"},"prompt":{"type":"string"},"mode":{"type":"string","enum":["plan","build"]},"useIsolatedWorktree":{"type":"boolean"}},"required":["role","prompt"]}
    """

    private let provider: any LLMProvider
    private let model: String
    private let toolRegistry: ToolRegistry

    public init(provider: any LLMProvider, model: String, toolRegistry: ToolRegistry) {
        self.provider = provider
        self.model = model
        self.toolRegistry = toolRegistry
    }

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let role = args["role"] as? String,
              let prompt = args["prompt"] as? String else {
            return .failure("Missing 'role' or 'prompt'")
        }
        let requestedMode = AgentMode(rawValue: (args["mode"] as? String) ?? "plan") ?? .plan
        let effectiveMode: AgentMode = context.mode == .plan ? .plan : requestedMode
        let isolated = (args["useIsolatedWorktree"] as? Bool) ?? false

        let spec = SubAgentTaskSpec(
            role: role,
            prompt: prompt,
            mode: effectiveMode,
            maxTurns: 6,
            useIsolatedWorktree: isolated
        )
        let coordinator = SwarmCoordinator(primaryWorkspace: context.workspaceRoot, toolRegistry: toolRegistry)
        let results = try await coordinator.runSwarm(
            tasks: [spec],
            provider: provider,
            model: model,
            sandboxTier: context.sandboxPolicy.tier
        )
        guard let first = results.first else {
            return .failure("Sub-agent returned no result.")
        }
        return .success("[SubAgent:\(first.role)] \(first.summary)", metadata: [
            "tokens": "\(first.usage.totalTokens)",
            "branch": first.worktreeBranch ?? "",
        ])
    }
}
