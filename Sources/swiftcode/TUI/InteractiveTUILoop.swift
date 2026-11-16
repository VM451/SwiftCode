import Foundation
import SwiftCodeCore

/// Interactive ANSI terminal loop handling slash commands, `@` mentions, and Plan/Build mode toggling.
public struct InteractiveTUILoop: Sendable {
    private let workspaceRoot: URL
    private let configuration: SwiftCodeConfiguration

    public init(workspaceRoot: URL, configuration: SwiftCodeConfiguration) {
        self.workspaceRoot = workspaceRoot
        self.configuration = configuration
    }

    public func run() async throws {
        let renderer = TerminalRenderer()
        let shadowGit = ShadowGitManager(workspaceRoot: workspaceRoot)
        let orchestrator = OrchestratorActor(
            workspaceRoot: workspaceRoot,
            configuration: configuration,
            approvalGate: ApprovalGate(policy: configuration.permissions) { request in
                await renderer.promptApproval(request)
            }
        )

        let streamTask = Task {
            for await event in await orchestrator.subscribe() {
                await renderer.renderEvent(event)
            }
        }
        defer { streamTask.cancel() }

        let initialMode = await orchestrator.currentMode()
        let activeModel = initialMode == .plan ? configuration.models.architect.model : configuration.models.coder.model
        await renderer.renderHeader(
            workspace: workspaceRoot,
            branch: currentGitBranch(),
            mode: initialMode,
            model: activeModel
        )

        while true {
            let mode = await orchestrator.currentMode()
            let promptTag = mode == .plan ? "\u{001B}[36m[plan]\u{001B}[0m > " : "\u{001B}[33m[build]\u{001B}[0m > "
            print(promptTag, terminator: "")
            fflush(stdout)
            guard let raw = readLine() else { break }
            let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }

            if input.hasPrefix("/") {
                let shouldExit = await handleSlashCommand(input, orchestrator: orchestrator, shadowGit: shadowGit)
                if shouldExit { break }
                continue
            }

            do {
                _ = try await orchestrator.runTurn(userPrompt: input)
            } catch {
                print("\u{001B}[31mTurn error: \(error.localizedDescription)\u{001B}[0m")
            }
        }
    }

    private func handleSlashCommand(
        _ command: String,
        orchestrator: OrchestratorActor,
        shadowGit: ShadowGitManager
    ) async -> Bool {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        switch parts[0].lowercased() {
        case "/quit", "/exit", "/q":
            return true
        case "/plan":
            await orchestrator.setMode(.plan)
        case "/build":
            await orchestrator.setMode(.build)
        case "/checkpoints":
            let list = (try? await shadowGit.listCheckpoints(limit: 15)) ?? []
            if list.isEmpty {
                print("No Shadow-Git checkpoints recorded yet.")
            } else {
                for cp in list { print("  \(cp.shortHash)  \(cp.label)") }
            }
        case "/undo":
            let steps = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
            if let restored = try? await shadowGit.undo(steps: steps) {
                print("Rolled back to checkpoint \(restored.shortHash) (\(restored.label))")
            } else {
                print("No earlier checkpoint available to undo.")
            }
        case "/diff":
            let list = (try? await shadowGit.listCheckpoints(limit: 1)) ?? []
            if let target = parts.count > 1 ? parts[1] : list.first?.commitHash,
               let diffText = try? await shadowGit.diff(against: target) {
                print(diffText.isEmpty ? "No changes." : diffText)
            }
        case "/export":
            if let store = try? MemoryStore(),
               let md = try? await store.exportSessionMarkdown(id: orchestrator.sessionID) {
                print(md)
            }
        case "/status":
            let mode = await orchestrator.currentMode()
            let usage = await orchestrator.currentUsage()
            print("Session: \(orchestrator.sessionID.uuidString) | Mode: \(mode.rawValue) | Tokens: \(usage.totalTokens)")
        case "/help":
            print("Commands: /plan, /build, /checkpoints, /undo [n], /diff [hash], /export, /status, /quit")
        default:
            print("Unknown command: \(parts[0]). Type /help.")
        }
        return false
    }

    private func currentGitBranch() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        p.currentDirectoryURL = workspaceRoot
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? "detached" : out
    }
}
