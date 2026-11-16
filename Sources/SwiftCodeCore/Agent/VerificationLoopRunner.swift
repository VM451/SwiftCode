import Foundation

/// Runs post-mutation verification hooks and drives self-healing fix attempts (FR-1.3).
struct VerificationLoopRunner: Sendable {
    func run(
        commands: [String],
        maxRetries: Int,
        workspaceRoot: URL,
        sandboxTier: SandboxTier,
        toolRegistry: ToolRegistry,
        emit: @Sendable (AgentEventKind) async -> Void,
        requestRepairTurn: @Sendable (String) async -> Bool
    ) async {
        guard let verifyTool = await toolRegistry.tool(named: "runSwiftVerify") else { return }
        let policy = SandboxPolicy(tier: sandboxTier, workspaceRoot: workspaceRoot)
        let ctx = ToolContext(sessionID: UUID(), workspaceRoot: workspaceRoot, mode: .build, sandboxPolicy: policy)

        for cmd in commands {
            for attempt in 0..<maxRetries {
                await emit(.verificationStarted(command: cmd))
                let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
                let args = "{\"command\":\"\(escaped)\"}"
                let res = (try? await verifyTool.execute(argumentsJSON: args, context: ctx))
                    ?? .failure("Verification command crashed.")
                await emit(.verificationCompleted(passed: !res.isError, summary: res.content))
                if !res.isError || attempt == maxRetries - 1 {
                    break
                }
                let prompt = "Verification command `\(cmd)` failed. Fix the diagnostics and verify again:\n\(res.content)"
                let repaired = await requestRepairTurn(prompt)
                if !repaired { break }
            }
        }
    }
}
