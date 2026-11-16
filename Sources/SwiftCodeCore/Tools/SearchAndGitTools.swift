import Foundation

/// Searches workspace files via regex or literal substring while skipping hidden/build directories.
public struct GrepSearchTool: SwiftCodeTool, Sendable {
    public let name = "grepSearch"
    public let description = "Search workspace text files for a literal or regular expression query."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"query":{"type":"string"},"isRegex":{"type":"boolean"}},"required":["query"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let query = args["query"] as? String, !query.isEmpty else { return .failure("Missing 'query'") }
        let isRegex = (args["isRegex"] as? Bool) ?? false
        let results = searchSync(root: context.workspaceRoot, query: query, isRegex: isRegex)
        return .success(results.isEmpty ? "No matches found." : results.joined(separator: "\n"))
    }

    private func searchSync(root: URL, query: String, isRegex: Bool) -> [String] {
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var results: [String] = []
        let regex = isRegex ? (try? NSRegularExpression(pattern: query)) : nil
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            if path.contains("/.git/") || path.contains("/.build/") || path.contains("/.swiftcode/") {
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = path.replacingOccurrences(of: rootPath + "/", with: "")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                let s = String(line)
                let matched: Bool = if let regex {
                    regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
                } else {
                    s.contains(query)
                }
                if matched {
                    results.append("\(rel):\(idx + 1): \(s.trimmingCharacters(in: .whitespaces))")
                    if results.count >= 200 { return results }
                }
            }
        }
        return results
    }
}

/// Inspects `git status` in the workspace.
public struct GitStatusTool: SwiftCodeTool, Sendable {
    public let name = "gitStatus"
    public let description = "Show `git status --short` for the workspace."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{}}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let out = runProcess(args: ["status", "--short"], cwd: context.workspaceRoot)
        return .success(out.isEmpty ? "Working tree clean." : out)
    }

    private func runProcess(args: [String], cwd: URL) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

/// Inspects `git diff` in the workspace.
public struct GitDiffTool: SwiftCodeTool, Sendable {
    public let name = "gitDiff"
    public let description = "Show `git diff` (optionally staged) for the workspace."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"staged":{"type":"boolean"}}}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = (try? ToolArgumentDecoder.decodeObject(argumentsJSON)) ?? [:]
        let staged = (args["staged"] as? Bool) ?? false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = staged ? ["diff", "--cached"] : ["diff"]
        p.currentDirectoryURL = context.workspaceRoot
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return .success(out.isEmpty ? "No diff." : String(out.prefix(24_000)))
    }
}

/// Stages and commits changes in the user's workspace repository.
public struct GitCommitTool: SwiftCodeTool, Sendable {
    public let name = "gitCommit"
    public let description = "Stage specified paths (or all changes) and create a Git commit."
    public let riskLevel: ToolRiskLevel = .workspaceMutation
    public let inputSchemaJSON = """
    {"type":"object","properties":{"message":{"type":"string"}},"required":["message"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let message = args["message"] as? String, !message.isEmpty else {
            return .failure("Missing commit message.")
        }
        _ = runGit(["add", "-A"], cwd: context.workspaceRoot)
        let res = runGit(["commit", "-m", message], cwd: context.workspaceRoot)
        return res.status == 0 ? .success(res.output) : .failure(res.output)
    }

    private func runGit(_ args: [String], cwd: URL) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }
}

/// Fetches a web page and converts HTML to clean Markdown without a browser engine (FR-4.1).
public struct WebFetchTool: SwiftCodeTool, Sendable {
    public let name = "fetchWeb"
    public let description = "Fetch an HTTP(S) URL and return clean Markdown text."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        guard let urlStr = args["url"] as? String,
              let url = URL(string: urlStr),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return .failure("Valid http/https URL required.")
        }
        let (data, http) = try await HTTPTransport.shared.data(for: URLRequest(url: url))
        guard http.statusCode < 400 else {
            return .failure("HTTP \(http.statusCode) fetching \(urlStr)")
        }
        let raw = String(decoding: data, as: UTF8.self)
        let markdown = HTMLMarkdownConverter.convert(raw)
        return .success(String(markdown.prefix(20_000)))
    }
}

/// Requests clarifying user input safely during Plan or Build mode.
public struct AskUserTool: SwiftCodeTool, Sendable {
    public let name = "askUser"
    public let description = "Ask the user a clarifying question before proceeding."
    public let riskLevel: ToolRiskLevel = .readOnly
    public let inputSchemaJSON = """
    {"type":"object","properties":{"question":{"type":"string"}},"required":["question"]}
    """

    public init() {}

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let args = try ToolArgumentDecoder.decodeObject(argumentsJSON)
        let question = (args["question"] as? String) ?? "Please clarify."
        return .success("[Question for user]: \(question)")
    }
}
