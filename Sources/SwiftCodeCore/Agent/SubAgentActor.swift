import Foundation

/// Task specification for an isolated child sub-agent worker (FR-7.1).
public struct SubAgentTaskSpec: Sendable {
    public let id: UUID
    public let role: String
    public let prompt: String
    public let mode: AgentMode
    public let maxTurns: Int
    public let useIsolatedWorktree: Bool

    public init(
        id: UUID = UUID(),
        role: String,
        prompt: String,
        mode: AgentMode = .plan,
        maxTurns: Int = 6,
        useIsolatedWorktree: Bool = false
    ) {
        self.id = id
        self.role = role
        self.prompt = prompt
        self.mode = mode
        self.maxTurns = maxTurns
        self.useIsolatedWorktree = useIsolatedWorktree
    }
}

/// Output summary returned by a completed `SubAgentActor`.
public struct SubAgentResult: Sendable, Equatable {
    public let taskID: UUID
    public let role: String
    public let summary: String
    public let usage: TokenUsage
    public let worktreeBranch: String?
}

/// Isolated child agent running in its own actor context with scoped tools and budget.
public actor SubAgentActor {
    private let spec: SubAgentTaskSpec
    private let workspaceRoot: URL
    private let provider: any LLMProvider
    private let model: String
    private let toolRegistry: ToolRegistry
    private let sandboxPolicy: SandboxPolicy

    public init(
        spec: SubAgentTaskSpec,
        workspaceRoot: URL,
        provider: any LLMProvider,
        model: String,
        toolRegistry: ToolRegistry,
        sandboxPolicy: SandboxPolicy
    ) {
        self.spec = spec
        self.workspaceRoot = workspaceRoot
        self.provider = provider
        self.model = model
        self.toolRegistry = toolRegistry
        self.sandboxPolicy = sandboxPolicy
    }

    public func execute() async throws -> SubAgentResult {
        var messages = [ConversationMessage(role: .user, content: spec.prompt)]
        var usage = TokenUsage()
        var finalReply = ""
        let systemPrompt = "You are SwiftCode SubAgent (\(spec.role)). Solve the assigned subtask cleanly and report concise results."
        let tools = await toolRegistry.definitions(for: spec.mode)

        for _ in 0..<spec.maxTurns {
            let req = LLMRequest(
                model: model,
                systemPrompt: systemPrompt,
                messages: messages,
                tools: tools,
                maxTokens: 4096
            )
            var turnText = ""
            var callsByID: [String: (name: String, args: String)] = [:]
            var orderedIDs: [String] = []

            for try await chunk in provider.streamCompletion(request: req) {
                switch chunk {
                case .textDelta(let d):
                    turnText += d
                case .toolCallStart(let id, let name):
                    orderedIDs.append(id)
                    callsByID[id] = (name, "")
                case .toolCallArgumentsDelta(let id, let d):
                    if let existing = callsByID[id] {
                        callsByID[id] = (existing.name, existing.args + d)
                    }
                case .usage(let i, let o, let c):
                    let deltaCost = TokenUsage.estimateCost(model: model, inputTokens: i, outputTokens: o, cachedTokens: c)
                    usage.add(TokenUsage(inputTokens: i, outputTokens: o, cachedTokens: c, estimatedCostUSD: deltaCost))
                case .reasoningDelta, .finished:
                    break
                }
            }

            let toolCalls = orderedIDs.compactMap { id -> ToolCall? in
                guard let pair = callsByID[id] else { return nil }
                return ToolCall(id: id, name: pair.name, argumentsJSON: pair.args.isEmpty ? "{}" : pair.args)
            }
            messages.append(ConversationMessage(role: .assistant, content: turnText, toolCalls: toolCalls))
            finalReply = turnText

            if toolCalls.isEmpty { break }

            let ctx = ToolContext(
                sessionID: spec.id,
                workspaceRoot: workspaceRoot,
                mode: spec.mode,
                sandboxPolicy: sandboxPolicy
            )
            for call in toolCalls {
                let output: ToolOutput
                if await toolRegistry.isPermitted(toolName: call.name, in: spec.mode),
                   let tool = await toolRegistry.tool(named: call.name) {
                    output = (try? await tool.execute(argumentsJSON: call.argumentsJSON, context: ctx))
                        ?? .failure("SubAgent tool error")
                } else {
                    output = .failure("Tool '\(call.name)' not permitted in sub-agent mode '\(spec.mode.rawValue)'.")
                }
                messages.append(ConversationMessage(role: .tool, content: output.content, toolCallID: call.id, toolName: call.name))
            }
        }

        return SubAgentResult(taskID: spec.id, role: spec.role, summary: finalReply, usage: usage, worktreeBranch: nil)
    }
}
