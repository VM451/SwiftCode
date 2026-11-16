import Foundation
import SwiftCodeCore

/// `@MainActor @Observable` ViewModel driving the active agent workspace and Plan/Build mode state.
@MainActor
@Observable
final class WorkspaceViewModel {
    private let container: SwiftCodeAppContainer
    private var orchestrator: OrchestratorActor?
    private var activeSessionID: UUID?
    private var approvalContinuations: [String: CheckedContinuation<ApprovalResolution, Never>] = [:]

    var selectedMode: AgentMode = .plan
    var promptDraft: String = ""
    var turns: [WorkspaceTurnItem] = []
    var isRunning = false
    var pendingApproval: PendingApprovalItem?
    var usage = TokenUsage()
    var lastErrorMessage: String?

    init(container: SwiftCodeAppContainer) {
        self.container = container
    }

    func loadSession(id: UUID?, mode: AgentMode) {
        activeSessionID = id
        selectedMode = mode
        lastErrorMessage = nil
        if let id {
            turns = container.fetchTurns(sessionID: id)
        } else {
            turns = []
        }
        orchestrator = nil
    }

    func switchMode(to newMode: AgentMode) {
        selectedMode = newMode
        guard let orchestrator else { return }
        Task {
            await orchestrator.setMode(newMode)
        }
    }

    func sendPrompt() {
        let prompt = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning else { return }
        promptDraft = ""
        lastErrorMessage = nil
        isRunning = true

        let sessionID = activeSessionID ?? container.createSession(title: String(prompt.prefix(40)), mode: selectedMode).id
        activeSessionID = sessionID
        container.appendTurn(sessionID: sessionID, role: "user", content: prompt)
        turns.append(WorkspaceTurnItem(id: UUID(), role: "user", content: prompt, toolSummary: nil, createdAt: Date()))

        let assistantID = UUID()
        turns.append(WorkspaceTurnItem(id: assistantID, role: "assistant", content: "", toolSummary: nil, createdAt: Date()))

        Task {
            await executeTurn(sessionID: sessionID, assistantTurnID: assistantID, prompt: prompt)
        }
    }

    func resolveApproval(_ resolution: ApprovalResolution) {
        guard let item = pendingApproval else { return }
        pendingApproval = nil
        if let cont = approvalContinuations.removeValue(forKey: item.id) {
            cont.resume(returning: resolution)
        }
    }

    private func executeTurn(sessionID: UUID, assistantTurnID: UUID, prompt: String) async {
        var config = container.configurationStore.load(workspaceRoot: container.workspaceRoot)
        config.defaultMode = selectedMode
        let gate = ApprovalGate(policy: config.permissions) { [weak self] req in
            guard let self else { return .deny("Cancelled") }
            return await self.awaitUserApproval(for: req)
        }
        let engine = orchestrator ?? OrchestratorActor(
            sessionID: sessionID,
            workspaceRoot: container.workspaceRoot,
            configuration: config,
            approvalGate: gate
        )
        orchestrator = engine
        await engine.setMode(selectedMode)

        let stream = await engine.subscribe()
        let observer = Task {
            for await event in stream {
                self.handle(event: event, assistantTurnID: assistantTurnID)
            }
        }

        do {
            let reply = try await engine.runTurn(userPrompt: prompt)
            let finalText = reply.isEmpty ? "Completed." : reply
            updateAssistantTurn(id: assistantTurnID, text: finalText)
            container.appendTurn(sessionID: sessionID, role: "assistant", content: finalText)
        } catch {
            lastErrorMessage = error.localizedDescription
            updateAssistantTurn(id: assistantTurnID, text: "Provider notice: \(error.localizedDescription)")
        }
        observer.cancel()
        isRunning = false
    }

    private func awaitUserApproval(for request: ApprovalRequest) async -> ApprovalResolution {
        pendingApproval = PendingApprovalItem(
            id: request.call.id,
            summary: request.summary,
            riskTitle: request.riskLevel.displayName,
            diffPreview: request.diffPreview,
            argumentsPreview: request.call.argumentsJSON
        )
        return await withCheckedContinuation { continuation in
            approvalContinuations[request.call.id] = continuation
        }
    }

    private func handle(event: AgentEvent, assistantTurnID: UUID) {
        switch event.kind {
        case .assistantTokenDelta(let delta):
            if let idx = turns.firstIndex(where: { $0.id == assistantTurnID }) {
                turns[idx].content += delta
            }
        case .toolExecutionCompleted(_, let name, let output, let ms):
            if let idx = turns.firstIndex(where: { $0.id == assistantTurnID }) {
                let badge = output.isError ? "✗" : "✓"
                let line = "\(badge) \(name) (\(ms)ms)"
                turns[idx].toolSummary = [turns[idx].toolSummary, line].compactMap { $0 }.joined(separator: "\n")
            }
        case .turnCompleted(let newUsage):
            usage = newUsage
        default:
            break
        }
    }

    private func updateAssistantTurn(id: UUID, text: String) {
        if let idx = turns.firstIndex(where: { $0.id == id }) {
            turns[idx].content = text
        }
    }
}
