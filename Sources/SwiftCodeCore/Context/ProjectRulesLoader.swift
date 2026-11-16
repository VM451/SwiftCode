import Foundation

/// Loads hierarchical instruction files (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`) (FR-3.1).
public struct ProjectRulesLoader: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    /// Loads global `~/.swiftcode/AGENTS.md` plus repo-root and nested directory rules.
    public func loadRules(workspaceRoot: URL, activeFileURL: URL? = nil) -> String {
        var sections: [String] = []

        let globalRules = homeDirectory
            .appendingPathComponent(".swiftcode", isDirectory: true)
            .appendingPathComponent("AGENTS.md")
        if let content = readIfExists(globalRules) {
            sections.append("### Global Rules (`~/.swiftcode/AGENTS.md`)\n\(content)")
        }

        if let rootRule = loadRootRule(in: workspaceRoot) {
            sections.append(rootRule)
        }

        if let activeFileURL {
            for scoped in loadScopedRules(workspaceRoot: workspaceRoot, fileURL: activeFileURL) {
                sections.append(scoped)
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private func loadRootRule(in workspaceRoot: URL) -> String? {
        for filename in ["AGENTS.md", "CLAUDE.md", ".cursorrules"] {
            let url = workspaceRoot.appendingPathComponent(filename)
            if let content = readIfExists(url) {
                return "### Workspace Rules (`\(filename)`)\n\(content)"
            }
        }
        return nil
    }

    private func loadScopedRules(workspaceRoot: URL, fileURL: URL) -> [String] {
        let rootPath = workspaceRoot.standardizedFileURL.path
        var dir = fileURL.standardizedFileURL.deletingLastPathComponent()
        var collected: [String] = []
        while dir.path.hasPrefix(rootPath) && dir.path != rootPath {
            let candidate = dir.appendingPathComponent("AGENTS.md")
            if let content = readIfExists(candidate) {
                let rel = dir.path.replacingOccurrences(of: rootPath + "/", with: "")
                collected.append("### Directory Rules (`\(rel)/AGENTS.md`)\n\(content)")
            }
            dir = dir.deletingLastPathComponent()
        }
        return collected.reversed()
    }

    private func readIfExists(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
