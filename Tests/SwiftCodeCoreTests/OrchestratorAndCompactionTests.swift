import Foundation
import Testing
@testable import SwiftCodeCore

struct OrchestratorAndCompactionTests {
    @Test func approvalGateEnforcesPatternsSessionAndEdits() async {
        let gate = ApprovalGate(
            policy: PermissionPolicyConfig(
                readOnly: .alwaysAllow,
                workspaceMutation: .askEveryTime,
                shellExecution: .askEveryTime,
                autoAllowCommands: ["swift test"],
                denyPatterns: ["rm -rf /"]
            )
        ) { req in
            if req.call.name == "writeFile" {
                return .editArguments("{\"path\":\"Safe.swift\",\"content\":\"// edited\"}")
            }
            return .allowForSession
        }

        let root = URL(fileURLWithPath: "/tmp")
        let blocked = await gate.authorize(
            call: ToolCall(id: "1", name: "executeShell", argumentsJSON: "{\"command\":\"rm -rf /\"}"),
            risk: .shellExecution,
            workspaceRoot: root
        )
        #expect(blocked.approved == false)

        let autoAllowed = await gate.authorize(
            call: ToolCall(id: "2", name: "executeShell", argumentsJSON: "{\"command\":\"swift test\"}"),
            risk: .shellExecution,
            workspaceRoot: root
        )
        #expect(autoAllowed.approved)

        let edited = await gate.authorize(
            call: ToolCall(id: "3", name: "writeFile", argumentsJSON: "{\"path\":\"Raw.swift\",\"content\":\"raw\"}"),
            risk: .workspaceMutation,
            workspaceRoot: root
        )
        #expect(edited.approved)
        #expect(edited.effectiveCall.argumentsJSON.contains("Safe.swift"))
    }

    @Test func contextCompactorPreservesPinnedAndRecentTurnsAtThreshold() async {
        let compactor = ContextCompactor(maxTokens: 200, thresholdRatio: 0.5, keepRecentTurns: 2)
        var history: [ConversationMessage] = [
            ConversationMessage(role: .user, content: "Pinned architectural constraint", isPinned: true),
        ]
        for idx in 0..<8 {
            history.append(ConversationMessage(role: .user, content: "Turn \(idx) " + String(repeating: "x", count: 120)))
        }
        let outcome = await compactor.compactIfNeeded(systemPrompt: "System", messages: history)
        #expect(outcome.didCompact)
        #expect(outcome.afterTokens < outcome.beforeTokens)
        #expect(outcome.compactedMessages.contains { $0.content.contains("Pinned architectural constraint") })
        #expect(outcome.compactedMessages.contains { $0.content.contains("<compacted_history>") })
    }

    @Test func orchestratorPlanAndBuildLoopProducesPlanCheckpointsAndMemory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-orch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        let memDir = tempDir.appendingPathComponent("memory", isDirectory: true)
        let store = try MemoryStore(databaseURL: dbURL, memoryDirectoryURL: memDir)
        try await store.saveMemoryNote(id: "style", title: "Swift Style", body: "Use strict concurrency and actors.")
        let hits = await store.searchMemoryNotes(query: "strict concurrency")
        #expect(hits.isEmpty == false)

        let provider = MockScriptedProvider(providerID: "mock") { request in
            if request.messages.last?.role == .tool {
                return [
                    .textDelta("Done writing file."),
                    .usage(inputTokens: 40, outputTokens: 10, cachedTokens: 0),
                    .finished(stopReason: "end_turn"),
                ]
            }
            if request.tools.contains(where: { $0.name == "writeFile" }) {
                return [
                    .toolCallStart(id: "tc1", name: "writeFile"),
                    .toolCallArgumentsDelta(id: "tc1", delta: "{\"path\":\"Generated.swift\",\"content\":\"let ok = true\\n\"}"),
                    .usage(inputTokens: 50, outputTokens: 20, cachedTokens: 10),
                    .finished(stopReason: "tool_use"),
                ]
            }
            return [
                .textDelta("## Execution Plan\n1. Create Generated.swift"),
                .usage(inputTokens: 30, outputTokens: 15, cachedTokens: 0),
                .finished(stopReason: "end_turn"),
            ]
        }

        var cfg = SwiftCodeConfiguration()
        cfg.defaultMode = .plan
        cfg.verificationCommands = []
        cfg.permissions.workspaceMutation = .alwaysAllow

        let orchestrator = OrchestratorActor(
            workspaceRoot: tempDir,
            configuration: cfg,
            overrideProvider: provider,
            memoryStore: store
        )

        let planReply = try await orchestrator.runTurn(userPrompt: "Plan feature")
        #expect(planReply.contains("Execution Plan"))
        let planFile = tempDir.appendingPathComponent(".swiftcode/plans/\(orchestrator.sessionID.uuidString).md")
        #expect(FileManager.default.fileExists(atPath: planFile.path))

        await orchestrator.setMode(.build)
        let buildReply = try await orchestrator.runTurn(userPrompt: "Implement it")
        #expect(buildReply.contains("Done writing file."))
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Generated.swift").path))

        let events = await orchestrator.eventHistory()
        #expect(events.contains { if case .checkpointCreated = $0.kind { return true }; return false })

        let exported = try await store.exportSessionMarkdown(id: orchestrator.sessionID)
        #expect(exported.contains("Plan feature"))
    }

    @Test func swarmCoordinatorExecutesConcurrentSubAgents() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-swarm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let provider = MockScriptedProvider(providerID: "mock") { req in
            [
                .textDelta("Completed: \(req.messages.first?.content ?? "")"),
                .usage(inputTokens: 10, outputTokens: 5, cachedTokens: 0),
                .finished(stopReason: "stop"),
            ]
        }
        let coordinator = SwarmCoordinator(primaryWorkspace: tempDir, toolRegistry: .makeDefault(), maxConcurrency: 2)
        let results = try await coordinator.runSwarm(
            tasks: [
                SubAgentTaskSpec(role: "explorer", prompt: "Inspect A"),
                SubAgentTaskSpec(role: "reviewer", prompt: "Inspect B"),
            ],
            provider: provider,
            model: "mock-model",
            sandboxTier: .none
        )
        #expect(results.count == 2)
        #expect(results.contains { $0.role == "explorer" && $0.summary.contains("Inspect A") })
        #expect(results.contains { $0.role == "reviewer" && $0.summary.contains("Inspect B") })
    }
}
