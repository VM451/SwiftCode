import Foundation

/// Reads a UTF-8 file with optional line pagination and binary file safety guard (EC-2).
public struct ReadFileTool: SwiftCodeTool, Sendable {
    public let name = "readFile"
    public let description = "Read text file contents with optional 1-based startLine and endLine. Binary files return metadata and SHA-256 instead of raw bytes."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"}},"required":["path"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let path = args["path"] as? String else { return .failure("Missing 'path'") }
        let url = try ToolArgumentDecoder.resolveSafePath(path, workspaceRoot: context.workspaceRoot)
        let data = try Data(contentsOf: url)

        if isLikelyBinary(data: data, ext: url.pathExtension) {
            let sha = WebhookSigner.sha256Hex(of: data)
            let mime = mimeType(for: url.pathExtension)
            return .success("[Binary File] path=\(path) mime=\(mime) bytes=\(data.count) sha256=\(sha)", metadata: [
                "binary": "true",
                "sha256": sha,
                "bytes": "\(data.count)",
            ])
        }

        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = max(1, args["startLine"] as? Int ?? 1)
        let end = min(lines.count, args["endLine"] as? Int ?? lines.count)
        guard start <= end else { return .success("") }

        let numbered = (start...end).map { idx in
            "\(idx): \(lines[idx - 1])"
        }.joined(separator: "\n")
        return .success(numbered, metadata: ["lineCount": "\(lines.count)"])
    }

    private func isLikelyBinary(data: Data, ext: String) -> Bool {
        let binaryExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "dylib", "o", "a"]
        if binaryExts.contains(ext.lowercased()) { return true }
        let sample = data.prefix(2048)
        if sample.contains(0) { return true }
        return String(data: Data(sample), encoding: .utf8) == nil && !sample.isEmpty
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "pdf": "application/pdf"
        case "zip": "application/zip"
        default: "application/octet-stream"
        }
    }
}

/// Lists immediate entries inside a workspace directory.
public struct ListDirectoryTool: SwiftCodeTool, Sendable {
    public let name = "listDirectory"
    public let description = "List files and subdirectories in a workspace path."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"path":{"type":"string"}},"required":[]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = (try? ToolArgumentDecoder.decodeObject(argumentsJSON)) ?? [:]
        let rel = (args["path"] as? String) ?? "."
        let dir = try ToolArgumentDecoder.resolveSafePath(rel, workspaceRoot: context.workspaceRoot)
        let entries = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        let lines = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? "\(url.lastPathComponent)/" : url.lastPathComponent
        }
        return .success(lines.joined(separator: "\n"))
    }
}

/// Finds workspace files matching a suffix or substring pattern while skipping `.git`, `.build`, and `.swiftcode`.
public struct GlobSearchTool: SwiftCodeTool, Sendable {
    public let name = "globSearch"
    public let description = "Search workspace file paths matching a glob or suffix pattern (e.g. '*.swift')."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"pattern":{"type":"string"}},"required":["pattern"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        let pattern = (args["pattern"] as? String) ?? "*"
        let matches = collectMatches(root: context.workspaceRoot, pattern: pattern)
        return .success(matches.joined(separator: "\n"))
    }

    private func collectMatches(root: URL, pattern: String) -> [String] {
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var matches: [String] = []
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            if path.contains("/.git/") || path.contains("/.build/") || path.contains("/.swiftcode/") {
                continue
            }
            let rel = path.replacingOccurrences(of: rootPath + "/", with: "")
            if matchesGlob(rel, pattern: pattern) {
                matches.append(rel)
                if matches.count >= 300 { break }
            }
        }
        return matches.sorted()
    }

    private func matchesGlob(_ text: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        let target = pattern.contains("/") ? text : URL(fileURLWithPath: text).lastPathComponent
        return target.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }
}

/// Writes or creates a file inside the workspace, returning a unified diff preview.
public struct WriteFileTool: SwiftCodeTool, Sendable {
    public let name = "writeFile"
    public let description = "Create or overwrite a UTF-8 file inside the workspace."
    public let riskLevel: ToolRiskLevel = .workspaceMutation
    public let inputSchemaJSON = """
    {"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else {
            return .failure("Missing 'path' or 'content'")
        }
        let target = try ToolArgumentDecoder.resolveSafePath(path, workspaceRoot: context.workspaceRoot)
        let previous = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: target, atomically: true, encoding: .utf8)
        let diff = UnifiedDiffEngine.diff(path: path, original: previous, updated: content)
        return .success("Wrote \(path) (+\(diff.additions)/-\(diff.deletions))", metadata: ["diff": diff.unifiedText])
    }
}

/// Applies exact search-and-replace patches with trimmed-line fuzzy fallback (FR-4.1).
public struct PatchFileTool: SwiftCodeTool, Sendable {
    public let name = "patchFile"
    public let description = "Replace an exact text block in a file with new text."
    public let riskLevel: ToolRiskLevel = .workspaceMutation
    public let inputSchemaJSON = """
    {"type":"object","properties":{"path":{"type":"string"},"search":{"type":"string"},"replace":{"type":"string"}},"required":["path","search","replace"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let path = args["path"] as? String,
              let search = args["search"] as? String,
              let replace = args["replace"] as? String else {
            return .failure("Missing 'path', 'search', or 'replace'")
        }
        let target = try ToolArgumentDecoder.resolveSafePath(path, workspaceRoot: context.workspaceRoot)
        let original = try String(contentsOf: target, encoding: .utf8)
        let updated: String
        if let range = original.range(of: search) {
            updated = original.replacingCharacters(in: range, with: replace)
        } else if let fuzzyUpdated = applyWhitespaceNormalizedPatch(original: original, search: search, replace: replace) {
            updated = fuzzyUpdated
        } else {
            return .failure("Search block not found in \(path).")
        }
        try updated.write(to: target, atomically: true, encoding: .utf8)
        let diff = UnifiedDiffEngine.diff(path: path, original: original, updated: updated)
        return .success("Patched \(path) (+\(diff.additions)/-\(diff.deletions))", metadata: ["diff": diff.unifiedText])
    }

    private func applyWhitespaceNormalizedPatch(original: String, search: String, replace: String) -> String? {
        let origLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let searchLines = search.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !searchLines.isEmpty, origLines.count >= searchLines.count else { return nil }
        for start in 0...(origLines.count - searchLines.count) {
            let window = origLines[start..<(start + searchLines.count)].map { $0.trimmingCharacters(in: .whitespaces) }
            if window == searchLines {
                let prefix = origLines[..<start]
                let suffix = origLines[(start + searchLines.count)...]
                return (Array(prefix) + [replace] + Array(suffix)).joined(separator: "\n")
            }
        }
        return nil
    }
}

/// Deletes a file inside the workspace.
public struct DeleteFileTool: SwiftCodeTool, Sendable {
    public let name = "deleteFile"
    public let description = "Delete a file inside the workspace."
    public let riskLevel: ToolRiskLevel = .workspaceMutation
    public let inputSchemaJSON = """
    {"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let path = args["path"] as? String else { return .failure("Missing 'path'") }
        let target = try ToolArgumentDecoder.resolveSafePath(path, workspaceRoot: context.workspaceRoot)
        try FileManager.default.removeItem(at: target)
        return .success("Deleted \(path)")
    }
}
