import Foundation

/// Coordinates concurrent `SubAgentActor` workers and isolated `git worktree` sandboxes (FR-7.1, FR-7.2).
public actor SwarmCoordinator {
    private let primaryWorkspace: URL
    private let toolRegistry: ToolRegistry
    private let maxConcurrency: Int

    public init(primaryWorkspace: URL, toolRegistry: ToolRegistry, maxConcurrency: Int = 4) {
        self.primaryWorkspace = primaryWorkspace
        self.toolRegistry = toolRegistry
        self.maxConcurrency = max(1, maxConcurrency)
    }

    /// Runs a batch of sub-agent tasks concurrently via structured `withThrowingTaskGroup`.
    public func runSwarm(
        tasks: [SubAgentTaskSpec],
        provider: any LLMProvider,
        model: String,
        sandboxTier: SandboxTier = .seatbelt
    ) async throws -> [SubAgentResult] {
        var results: [SubAgentResult] = []
        var index = 0

        try await withThrowingTaskGroup(of: SubAgentResult.self) { group in
            while index < min(maxConcurrency, tasks.count) {
                let spec = tasks[index]
                index += 1
                group.addTask {
                    try await self.runSingle(spec: spec, provider: provider, model: model, sandboxTier: sandboxTier)
                }
            }
            for try await res in group {
                results.append(res)
                if index < tasks.count {
                    let nextSpec = tasks[index]
                    index += 1
                    group.addTask {
                        try await self.runSingle(spec: nextSpec, provider: provider, model: model, sandboxTier: sandboxTier)
                    }
                }
            }
        }
        return results
    }

    private func runSingle(
        spec: SubAgentTaskSpec,
        provider: any LLMProvider,
        model: String,
        sandboxTier: SandboxTier
    ) async throws -> SubAgentResult {
        var worktreeURL: URL?
        var branchName: String?
        let root: URL

        if spec.useIsolatedWorktree, isGitRepository(primaryWorkspace) {
            let short = String(spec.id.uuidString.prefix(8)).lowercased()
            let branch = "swiftcode-worker-\(short)"
            let dir = primaryWorkspace
                .appendingPathComponent(".swiftcode", isDirectory: true)
                .appendingPathComponent("worktrees", isDirectory: true)
                .appendingPathComponent(short, isDirectory: true)
            if createWorktree(at: dir, branch: branch) {
                worktreeURL = dir
                branchName = branch
                root = dir
            } else {
                root = primaryWorkspace
            }
        } else {
            root = primaryWorkspace
        }

        let policy = SandboxPolicy(tier: sandboxTier, workspaceRoot: root)
        let worker = SubAgentActor(
            spec: spec,
            workspaceRoot: root,
            provider: provider,
            model: model,
            toolRegistry: toolRegistry,
            sandboxPolicy: policy
        )
        let result = try await worker.execute()

        if let worktreeURL, let branchName {
            cleanupWorktree(at: worktreeURL, branch: branchName)
        }
        return SubAgentResult(
            taskID: result.taskID,
            role: result.role,
            summary: result.summary,
            usage: result.usage,
            worktreeBranch: branchName
        )
    }

    private func isGitRepository(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path)
    }

    private func createWorktree(at dir: URL, branch: String) -> Bool {
        try? FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        let res = runGit(["worktree", "add", "-b", branch, dir.path], cwd: primaryWorkspace)
        return res == 0
    }

    private func cleanupWorktree(at dir: URL, branch: String) {
        _ = runGit(["worktree", "remove", "--force", dir.path], cwd: primaryWorkspace)
        _ = runGit(["branch", "-D", branch], cwd: primaryWorkspace)
    }

    private func runGit(_ args: [String], cwd: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = cwd
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
