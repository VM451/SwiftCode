import Foundation
import Logging
import Metrics

/// Primary event-sourced AI agent state machine orchestrating Plan/Build modes, HITL, checkpoints, and self-healing (FR-1.1..1.4).
public actor OrchestratorActor {
    public nonisolated let sessionID: UUID
    public nonisolated let workspaceRoot: URL

    private var configuration: SwiftCodeConfiguration
    private var mode: AgentMode
    private var messages: [ConversationMessage] = []
    private var events: [AgentEvent] = []
    private var usage = TokenUsage()
    private var continuations: [UUID: AsyncStream<AgentEvent>.Continuation] = [:]

    private let providerRegistry: ProviderRegistry
    private let overrideProvider: (any LLMProvider)?
    private let appleInspector: any AppleFoundationModelInspector
    private let toolRegistry: ToolRegistry
    private let approvalGate: ApprovalGate
    private let shadowGit: ShadowGitManager
    private let compactor: ContextCompactor
    private let redactor = SecretRedactor()
    private let mentionResolver = ContextMentionResolver()
    private let rulesLoader = ProjectRulesLoader()
    private let memoryStore: MemoryStore?
    private let workspaceLock: WorkspaceLock
    private let logger = Logger(label: "dev.swiftcode.orchestrator")

    public init(
        sessionID: UUID = UUID(),
        workspaceRoot: URL,
        configuration: SwiftCodeConfiguration = ConfigurationStore().load(),
        providerRegistry: ProviderRegistry? = nil,
        overrideProvider: (any LLMProvider)? = nil,
        appleInspector: any AppleFoundationModelInspector = LiveAppleFoundationModelInspector(),
        toolRegistry: ToolRegistry = .makeDefault(),
        approvalGate: ApprovalGate? = nil,
        memoryStore: MemoryStore? = try? MemoryStore()
    ) {
        self.sessionID = sessionID
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.configuration = configuration
        self.appleInspector = appleInspector
        self.providerRegistry = providerRegistry ?? ProviderRegistry(appleInspector: appleInspector)
        self.mode = configuration.defaultMode
        self.overrideProvider = overrideProvider
        self.toolRegistry = toolRegistry
        self.approvalGate = approvalGate ?? ApprovalGate(policy: configuration.permissions)
        self.shadowGit = ShadowGitManager(
            workspaceRoot: workspaceRoot,
            maxSnapshots: configuration.checkpoints.maxSnapshotsPerSession
        )
        self.compactor = ContextCompactor(
            maxTokens: configuration.contextWindowLimit,
            thresholdRatio: configuration.compactionThresholdRatio
        )
        self.memoryStore = memoryStore
        self.workspaceLock = WorkspaceLock(workspaceRoot: workspaceRoot)
    }

    public func currentMode() -> AgentMode { mode }
    public func currentUsage() -> TokenUsage { usage }
    public func eventHistory() -> [AgentEvent] { events }
    public func messageHistory() -> [ConversationMessage] { messages }

    /// Subscribes to live `AgentEvent` updates across CLI TUI, daemon streams, and chat bridges.
    public func subscribe() -> AsyncStream<AgentEvent> {
        let token = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(token) }
        }
        return stream
    }

    public func setMode(_ newMode: AgentMode) {
        guard newMode != mode else { return }
        let old = mode
        mode = newMode
        emit(.modeChanged(from: old, to: newMode))
    }

    public func switchAppleVariant(_ variant: AppleFoundationModelVariant) {
        configuration.applyDefaultAppleModel(variant)
    }

    /// Executes a user prompt through the Plan or Build loop and returns the final assistant text.
    @discardableResult
    public func runTurn(userPrompt: String, attachments: [ImageAttachment] = [], maxIterations: Int = 12) async throws -> String {
        if mode == .build {
            let acquired = (try? await workspaceLock.acquire()) ?? true
            if !acquired {
                emit(.errorEncountered(message: "Workspace is locked by another mutating SwiftCode session."))
            }
        }
        defer { Task { await workspaceLock.release() } }

        let resolvedPrompt = await mentionResolver.resolveMentions(in: userPrompt, workspaceRoot: workspaceRoot)
        let scrubbed = redactor.redact(resolvedPrompt).text
        emit(.userMessage(text: userPrompt))
        messages.append(ConversationMessage(role: .user, content: scrubbed, attachments: attachments))

        let role: ModelRole = mode == .plan ? .architect : .coder
        let assignment = providerRegistry.assignment(for: role, config: configuration)
        if assignment.provider == "apple-pcc" {
            let pccState = await appleInspector.pccQuotaState()
            if pccState.isLimitReached || pccState.isApproachingLimit {
                emit(.pccQuotaNotice(PCCQuotaNotice(state: pccState)))
            }
        }
        let provider = overrideProvider ?? providerRegistry.provider(for: assignment, fallback: configuration.models.fallback)
        let systemPrompt = OrchestratorPromptBuilder.systemPrompt(mode: mode, workspaceRoot: workspaceRoot, rulesLoader: rulesLoader)
        let activeContextLimit = configuration.effectiveContextWindowLimit(for: role)

        var finalAssistantText = ""
        for _ in 0..<maxIterations {
            let utilityAssignment = providerRegistry.assignment(for: .utility, config: configuration)
            let utilityProvider = overrideProvider ?? providerRegistry.provider(for: utilityAssignment)
            let compactResult = await compactor.compactIfNeeded(
                systemPrompt: systemPrompt,
                messages: messages,
                maxTokensOverride: activeContextLimit,
                utilityProvider: utilityProvider,
                utilityModel: utilityAssignment.model
            )
            if compactResult.didCompact {
                messages = compactResult.compactedMessages
                emit(.compactionTriggered(beforeTokens: compactResult.beforeTokens, afterTokens: compactResult.afterTokens))
            }

            let request = LLMRequest(
                model: assignment.model,
                systemPrompt: systemPrompt,
                messages: messages,
                tools: await toolRegistry.definitions(for: mode),
                maxTokens: assignment.maxTokens,
                temperature: assignment.temperature,
                enableReasoning: mode == .plan
            )

            let turnResult = try await streamSingleResponse(provider: provider, request: request, model: assignment.model)
            finalAssistantText = turnResult.text
            messages.append(ConversationMessage(
                role: .assistant,
                content: turnResult.text,
                reasoning: turnResult.reasoning.isEmpty ? nil : turnResult.reasoning,
                toolCalls: turnResult.toolCalls
            ))

            if turnResult.toolCalls.isEmpty {
                if mode == .plan && !turnResult.text.isEmpty {
                    let plan = ExecutionPlan(sessionID: sessionID, summary: "Generated Plan", markdown: turnResult.text)
                    _ = try? plan.writeToWorkspace(workspaceRoot)
                }
                break
            }
            for call in turnResult.toolCalls { await executeToolCall(call) }
        }

        if mode == .build && !configuration.verificationCommands.isEmpty {
            await runVerification(provider: provider, assignment: assignment, systemPrompt: systemPrompt)
        }

        Counter(label: "swiftcode.tokens.total").increment(by: usage.totalTokens)
        emit(.turnCompleted(usage: usage))
        try? await memoryStore?.saveSession(
            id: sessionID,
            title: String(userPrompt.prefix(64)),
            workspaceRoot: workspaceRoot,
            mode: mode,
            events: events
        )
        return finalAssistantText
    }

    private func streamSingleResponse(
        provider: any LLMProvider,
        request: LLMRequest,
        model: String
    ) async throws -> (text: String, reasoning: String, toolCalls: [ToolCall]) {
        var text = ""
        var reasoning = ""
        var calls: [String: (name: String, args: String)] = [:]
        var callOrder: [String] = []
        do {
            for try await chunk in provider.streamCompletion(request: request) {
                switch chunk {
                case .reasoningDelta(let d):
                    reasoning += d
                    emit(.reasoningTokenDelta(delta: d))
                case .textDelta(let d):
                    text += d
                    emit(.assistantTokenDelta(delta: d))
                case .toolCallStart(let id, let name):
                    callOrder.append(id)
                    calls[id] = (name, "")
                case .toolCallArgumentsDelta(let id, let delta):
                    if let existing = calls[id] { calls[id] = (existing.name, existing.args + delta) }
                case .usage(let input, let output, let cached):
                    let cost = TokenUsage.estimateCost(model: model, inputTokens: input, outputTokens: output, cachedTokens: cached)
                    usage.add(TokenUsage(inputTokens: input, outputTokens: output, cachedTokens: cached, estimatedCostUSD: cost))
                case .finished:
                    break
                }
            }
        } catch let appleError as AppleFoundationModelError {
            if case .pccQuotaLimitReached(let quotaState) = appleError {
                emit(.pccQuotaNotice(PCCQuotaNotice(state: quotaState)))
            }
            emit(.errorEncountered(message: appleError.localizedDescription))
            throw appleError
        } catch {
            if !text.isEmpty || !reasoning.isEmpty {
                messages.append(ConversationMessage(role: .assistant, content: text + "\n[Partial response preserved after stream interruption]"))
            }
            emit(.errorEncountered(message: error.localizedDescription))
            throw error
        }
        return (text, reasoning, OrchestratorPromptBuilder.buildToolCalls(order: callOrder, map: calls))
    }

    private func executeToolCall(_ rawCall: ToolCall) async {
        guard await toolRegistry.isPermitted(toolName: rawCall.name, in: mode),
              let tool = await toolRegistry.tool(named: rawCall.name) else {
            let denied = ToolOutput.failure("Tool '\(rawCall.name)' is not permitted in \(mode.rawValue) mode.")
            emit(.toolExecutionCompleted(callID: rawCall.id, name: rawCall.name, output: denied, durationMS: 0))
            messages.append(ConversationMessage(role: .tool, content: denied.content, toolCallID: rawCall.id, toolName: rawCall.name))
            return
        }

        emit(.toolCallProposed(call: rawCall, risk: tool.riskLevel))
        let decision = await approvalGate.authorize(call: rawCall, risk: tool.riskLevel, workspaceRoot: workspaceRoot)
        emit(.approvalResolved(callID: rawCall.id, approved: decision.approved, reason: decision.reason))
        guard decision.approved else {
            messages.append(ConversationMessage(role: .tool, content: "User denied tool '\(rawCall.name)': \(decision.reason ?? "Denied")", toolCallID: rawCall.id, toolName: rawCall.name))
            return
        }

        let effectiveCall = decision.effectiveCall
        if tool.riskLevel >= .workspaceMutation && configuration.checkpoints.enabled,
           let snapshot = try? await shadowGit.captureSnapshot(label: "Before \(effectiveCall.name)", eventID: UUID()) {
            emit(.checkpointCreated(commitHash: snapshot.commitHash, label: snapshot.label))
        }

        emit(.toolExecutionStarted(call: effectiveCall))
        let clock = ContinuousClock.now
        let policy = SandboxPolicy(
            tier: configuration.sandbox.defaultTier,
            workspaceRoot: workspaceRoot,
            allowNetwork: configuration.sandbox.allowNetworkInShell,
            vmImageDirectory: configuration.sandbox.vmImageDirectory
        )
        let ctx = ToolContext(sessionID: sessionID, workspaceRoot: workspaceRoot, mode: mode, sandboxPolicy: policy)
        let output: ToolOutput
        do { output = try await tool.execute(argumentsJSON: effectiveCall.argumentsJSON, context: ctx) } catch { output = .failure(error.localizedDescription) }
        let elapsed = clock.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)

        emit(.toolExecutionCompleted(callID: effectiveCall.id, name: effectiveCall.name, output: output, durationMS: max(0, ms)))
        messages.append(ConversationMessage(role: .tool, content: redactor.redact(output.content).text, toolCallID: effectiveCall.id, toolName: effectiveCall.name))
    }

    private func runVerification(provider: any LLMProvider, assignment: ModelRoleAssignment, systemPrompt: String) async {
        await VerificationLoopRunner().run(
            commands: configuration.verificationCommands,
            maxRetries: configuration.maxAutoFixRetries,
            workspaceRoot: workspaceRoot,
            sandboxTier: configuration.sandbox.defaultTier,
            toolRegistry: toolRegistry,
            emit: { [weak self] kind in await self?.emit(kind) },
            requestRepairTurn: { [weak self] prompt in
                guard let self else { return false }
                return await self.performRepair(prompt: prompt, provider: provider, assignment: assignment, systemPrompt: systemPrompt)
            }
        )
    }

    private func performRepair(prompt: String, provider: any LLMProvider, assignment: ModelRoleAssignment, systemPrompt: String) async -> Bool {
        messages.append(ConversationMessage(role: .user, content: prompt))
        let req = LLMRequest(model: assignment.model, systemPrompt: systemPrompt, messages: messages, tools: await toolRegistry.definitions(for: .build), maxTokens: assignment.maxTokens)
        guard let fixTurn = try? await streamSingleResponse(provider: provider, request: req, model: assignment.model) else { return false }
        messages.append(ConversationMessage(role: .assistant, content: fixTurn.text, toolCalls: fixTurn.toolCalls))
        for call in fixTurn.toolCalls { await executeToolCall(call) }
        return true
    }

    private func emit(_ kind: AgentEventKind) {
        let event = AgentEvent(sessionID: sessionID, kind: kind)
        events.append(event)
        logger.debug("AgentEvent: \(String(describing: kind).prefix(120))")
        for cont in continuations.values { cont.yield(event) }
    }

    private func removeContinuation(_ token: UUID) { continuations.removeValue(forKey: token) }
}
