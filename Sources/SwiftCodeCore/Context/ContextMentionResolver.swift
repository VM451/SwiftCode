import Foundation

/// Resolves `@file:`, `@folder:`, `@symbol:`, `@git:`, and `@url:` prompt mentions (FR-3.4).
public struct ContextMentionResolver: Sendable {
    public init() {}

    public func resolveMentions(in prompt: String, workspaceRoot: URL) async -> String {
        let pattern = "@(file|folder|symbol|git|url):([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return prompt }
        let ns = prompt as NSString
        let matches = regex.matches(in: prompt, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return prompt }

        var attachments: [String] = []
        for match in matches where match.numberOfRanges >= 3 {
            let kind = ns.substring(with: match.range(at: 1))
            let arg = ns.substring(with: match.range(at: 2))
            if let resolved = await resolveSingle(kind: kind, argument: arg, workspaceRoot: workspaceRoot) {
                attachments.append(resolved)
            }
        }
        guard !attachments.isEmpty else { return prompt }
        return prompt + "\n\n<attached_context>\n" + attachments.joined(separator: "\n\n") + "\n</attached_context>"
    }

    private func resolveSingle(kind: String, argument: String, workspaceRoot: URL) async -> String? {
        switch kind {
        case "file":
            let target = workspaceRoot.appendingPathComponent(argument).standardizedFileURL
            guard target.path.hasPrefix(workspaceRoot.standardizedFileURL.path),
                  let text = try? String(contentsOf: target, encoding: .utf8) else { return nil }
            return "<file path=\"\(argument)\">\n\(text.prefix(16_000))\n</file>"

        case "folder":
            let dir = workspaceRoot.appendingPathComponent(argument).standardizedFileURL
            guard dir.path.hasPrefix(workspaceRoot.standardizedFileURL.path),
                  let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
            return "<folder path=\"\(argument)\">\n\(entries.sorted().joined(separator: "\n"))\n</folder>"

        case "symbol":
            let inspector = SwiftASTInspector()
            let hits = inspector.findSymbol(named: argument, in: workspaceRoot)
            let formatted = hits.map { "\($0.relativePath):\($0.startLine) [\($0.kind.rawValue)] \($0.signature)" }
                .joined(separator: "\n")
            return formatted.isEmpty ? nil : "<symbol name=\"\(argument)\">\n\(formatted)\n</symbol>"

        case "git":
            let args = argument == "staged" ? ["diff", "--cached"] : ["diff"]
            let diff = runGit(args: args, cwd: workspaceRoot)
            return "<git type=\"\(argument)\">\n\(diff.prefix(16_000))\n</git>"

        case "url":
            guard let url = URL(string: argument),
                  let (data, _) = try? await HTTPTransport.shared.data(for: URLRequest(url: url)),
                  let html = String(data: data, encoding: .utf8) else { return nil }
            let markdown = HTMLMarkdownConverter.convert(html)
            return "<url href=\"\(argument)\">\n\(markdown.prefix(12_000))\n</url>"

        default:
            return nil
        }
    }

    private func runGit(args: [String], cwd: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
