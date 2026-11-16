import Foundation

/// Metadata representing one Shadow-Git checkpoint commit.
public struct CheckpointSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { commitHash }
    public let commitHash: String
    public let shortHash: String
    public let label: String
    public let timestamp: Date

    public init(commitHash: String, label: String, timestamp: Date) {
        self.commitHash = commitHash
        self.shortHash = String(commitHash.prefix(8))
        self.label = label
        self.timestamp = timestamp
    }
}

/// Manages isolated `.swiftcode/shadow.git` snapshots without touching the user's real `.git` (FR-5.2).
public actor ShadowGitManager {
    public let workspaceRoot: URL
    private let shadowGitDir: URL
    private let maxSnapshots: Int

    public init(workspaceRoot: URL, maxSnapshots: Int = 100) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.shadowGitDir = self.workspaceRoot
            .appendingPathComponent(".swiftcode", isDirectory: true)
            .appendingPathComponent("shadow.git", isDirectory: true)
        self.maxSnapshots = maxSnapshots
    }

    /// Initializes `.swiftcode/shadow.git` and configures exclusions for internal & build directories.
    public func ensureInitialized() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: shadowGitDir.path) {
            try fm.createDirectory(at: shadowGitDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try runGit(args: ["init", "--bare", shadowGitDir.path], includeWorkTree: false)
            _ = try runGit(args: ["--git-dir=\(shadowGitDir.path)", "config", "user.name", "SwiftCode Shadow"], includeWorkTree: false)
            _ = try runGit(args: ["--git-dir=\(shadowGitDir.path)", "config", "user.email", "shadow@swiftcode.local"], includeWorkTree: false)
            _ = try runGit(args: ["--git-dir=\(shadowGitDir.path)", "config", "core.bare", "false"], includeWorkTree: false)
            _ = try runGit(args: ["--git-dir=\(shadowGitDir.path)", "config", "core.worktree", workspaceRoot.path], includeWorkTree: false)
        }
        let infoDir = shadowGitDir.appendingPathComponent("info", isDirectory: true)
        try fm.createDirectory(at: infoDir, withIntermediateDirectories: true)
        let excludeFile = infoDir.appendingPathComponent("exclude")
        let excludes = """
        .swiftcode/
        .git/
        .build/
        DerivedData/
        """
        try excludes.write(to: excludeFile, atomically: true, encoding: .utf8)
    }

    /// Stages the current workspace and records a snapshot commit if changes exist (or initial baseline).
    @discardableResult
    public func captureSnapshot(label: String, eventID: UUID? = nil) throws -> CheckpointSummary {
        try ensureInitialized()
        _ = try runGit(args: ["add", "-A"])

        let hasCommits = (try? runGit(args: ["rev-parse", "--verify", "HEAD"]))?.exitCode == 0
        let status = try runGit(args: ["status", "--porcelain"])
        if hasCommits && status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let head = try runGit(args: ["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return CheckpointSummary(commitHash: head, label: label, timestamp: Date())
        }

        let suffix = eventID.map { " [event:\($0.uuidString)]" } ?? ""
        let message = "\(label)\(suffix)"
        let commitRes = try runGit(args: ["commit", "--allow-empty", "-m", message])
        guard commitRes.exitCode == 0 else {
            throw NSError(domain: "ShadowGitManager", code: Int(commitRes.exitCode), userInfo: [
                NSLocalizedDescriptionKey: commitRes.stderr,
            ])
        }
        let hash = try runGit(args: ["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return CheckpointSummary(commitHash: hash, label: label, timestamp: Date())
    }

    /// Lists recorded Shadow-Git checkpoints newest first.
    public func listCheckpoints(limit: Int = 50) throws -> [CheckpointSummary] {
        try ensureInitialized()
        let res = try runGit(args: ["log", "-n", "\(min(limit, maxSnapshots))", "--format=%H|%ct|%s"])
        guard res.exitCode == 0 else { return [] }
        return res.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3, let epoch = TimeInterval(parts[1]) else { return nil }
            return CheckpointSummary(
                commitHash: String(parts[0]),
                label: String(parts[2]),
                timestamp: Date(timeIntervalSince1970: epoch)
            )
        }
    }

    /// Returns unified diff between `target` checkpoint and the current workspace (or `HEAD`).
    public func diff(against commitHash: String) throws -> String {
        try ensureInitialized()
        let res = try runGit(args: ["diff", commitHash])
        return res.stdout
    }

    /// Atomically restores workspace files back to the specified checkpoint hash.
    public func rollback(to commitHash: String) throws {
        try ensureInitialized()
        let reset = try runGit(args: ["read-tree", "--reset", "-u", commitHash])
        guard reset.exitCode == 0 else {
            throw NSError(domain: "ShadowGitManager", code: Int(reset.exitCode), userInfo: [
                NSLocalizedDescriptionKey: reset.stderr,
            ])
        }
        _ = try runGit(args: ["clean", "-fd"])
        _ = try runGit(args: ["update-ref", "HEAD", commitHash])
    }

    /// Reverts the workspace back by `steps` checkpoints (`steps = 1` goes to the previous snapshot).
    @discardableResult
    public func undo(steps: Int = 1) throws -> CheckpointSummary? {
        let checkpoints = try listCheckpoints(limit: max(2, steps + 2))
        guard checkpoints.count > steps else { return nil }
        let target = checkpoints[steps]
        try rollback(to: target.commitHash)
        return target
    }

    private func runGit(args: [String], includeWorkTree: Bool = true) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = workspaceRoot
        if includeWorkTree {
            process.arguments = ["--git-dir=\(shadowGitDir.path)", "--work-tree=\(workspaceRoot.path)"] + args
        } else {
            process.arguments = args
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, out, err)
    }
}
