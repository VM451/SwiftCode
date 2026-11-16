import ArgumentParser
import Foundation
import SwiftCodeCore
import SwiftCodeDaemon

@main
struct SwiftCodeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftcode",
        abstract: "100% Native Swift 6 AI Agent Harness",
        version: "2.0.0",
        subcommands: [
            RunCommand.self,
            ResumeCommand.self,
            UndoCommand.self,
            CheckpointCommand.self,
            DaemonCommand.self,
            VMCommand.self,
            DoctorCommand.self,
            KeyCommand.self,
            ASTCommand.self,
            MCPCommand.self,
            ConfigCommand.self,
        ],
        defaultSubcommand: nil
    )

    @Flag(name: .long, help: "Run SwiftCode as a stdio Model Context Protocol (MCP) server.")
    var mcpServer = false

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if mcpServer {
            let server = MCPStdioServer(workspaceRoot: workspace)
            await server.runStdioLoop()
            return
        }
        let config = ConfigurationStore().load(workspaceRoot: workspace)
        let tui = InteractiveTUILoop(workspaceRoot: workspace, configuration: config)
        try await tui.run()
    }
}

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Run a non-interactive prompt")

    @Argument(help: "Prompt to execute.")
    var prompt: String

    @Option(name: .long, help: "Execution mode: plan or build.")
    var mode: String = "plan"

    @Option(name: .long, help: "Sandbox tier: seatbelt, vm, or none.")
    var sandbox: String?

    @Option(name: .long, help: "Override model identifier.")
    var model: String?

    @Flag(name: .long, help: "Auto-approve tool executions.")
    var yes = false

    @Flag(name: .long, help: "Emit JSON output.")
    var json = false

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var config = ConfigurationStore().load(workspaceRoot: workspace)
        config.defaultMode = AgentMode(rawValue: mode) ?? .plan
        if let sandbox, let tier = SandboxTier(rawValue: sandbox) {
            config.sandbox.defaultTier = tier
        }
        if let model {
            config.models.architect.model = model
            config.models.coder.model = model
        }
        let gate = ApprovalGate(policy: config.permissions) { _ in
            yes ? .allowOnce : .deny("Non-interactive run requires --yes to approve mutating tools.")
        }
        let orchestrator = OrchestratorActor(workspaceRoot: workspace, configuration: config, approvalGate: gate)
        let reply = try await orchestrator.runTurn(userPrompt: prompt)
        if json {
            let usage = await orchestrator.currentUsage()
            let payload: [String: Any] = [
                "sessionID": orchestrator.sessionID.uuidString,
                "mode": config.defaultMode.rawValue,
                "reply": reply,
                "tokens": usage.totalTokens,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(reply)
        }
    }
}

struct ResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "resume", abstract: "List or inspect persisted sessions")

    @Argument(help: "Optional session UUID to export.")
    var sessionID: String?

    func run() async throws {
        let store = try MemoryStore()
        if let sessionID, let uuid = UUID(uuidString: sessionID) {
            print(try await store.exportSessionMarkdown(id: uuid))
            return
        }
        let sessions = await store.listSessions()
        if sessions.isEmpty {
            print("No saved sessions.")
            return
        }
        for s in sessions {
            print("\(s.id.uuidString)  [\(s.mode.rawValue)]  \(s.title)")
        }
    }
}

struct UndoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "undo", abstract: "Rollback workspace to an earlier Shadow-Git checkpoint")

    @Option(name: .long, help: "Number of checkpoints to rewind.")
    var steps: Int = 1

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let manager = ShadowGitManager(workspaceRoot: workspace)
        if let target = try await manager.undo(steps: steps) {
            print("Restored workspace to \(target.shortHash) (\(target.label))")
        } else {
            print("No checkpoint available to undo.")
        }
    }
}

struct CheckpointCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "checkpoint", abstract: "Inspect Shadow-Git checkpoints")

    @Argument(help: "Action: list, capture, diff, or rollback.")
    var action: String = "list"

    @Argument(help: "Optional label or commit hash.")
    var target: String?

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let manager = ShadowGitManager(workspaceRoot: workspace)
        switch action {
        case "capture":
            let cp = try await manager.captureSnapshot(label: target ?? "Manual snapshot")
            print("Captured \(cp.shortHash): \(cp.label)")
        case "diff":
            let list = try await manager.listCheckpoints(limit: 1)
            guard let hash = target ?? list.first?.commitHash else { return }
            print(try await manager.diff(against: hash))
        case "rollback":
            guard let hash = target else { throw ValidationError("Commit hash required for rollback.") }
            try await manager.rollback(to: hash)
            print("Rolled back workspace to \(hash)")
        default:
            let list = try await manager.listCheckpoints(limit: 30)
            for cp in list { print("\(cp.shortHash)  \(cp.timestamp)  \(cp.label)") }
        }
    }
}
