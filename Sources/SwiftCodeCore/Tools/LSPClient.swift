import Foundation

/// Pure-Swift JSON-RPC 2.0 client for SourceKit-LSP and standard Language Servers (FR-4.1).
public actor LSPClient {
    public struct Location: Codable, Sendable, Equatable {
        public let uri: String
        public let line: Int
        public let character: Int
    }

    private let serverCommand: String
    private let workspaceRoot: URL
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextRequestID = 1
    private var initialized = false

    public init(serverCommand: String = "sourcekit-lsp", workspaceRoot: URL) {
        self.serverCommand = serverCommand
        self.workspaceRoot = workspaceRoot
    }

    /// Starts the language server subprocess and sends `initialize` + `initialized`.
    public func start() async throws {
        guard process == nil else { return }
        let executable = resolveExecutable(serverCommand)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.currentDirectoryURL = workspaceRoot
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()

        self.process = proc
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading

        let params: [String: Any] = [
            "processId": Int(ProcessInfo.processInfo.processIdentifier),
            "rootUri": workspaceRoot.absoluteString,
            "capabilities": [:],
        ]
        _ = try sendRequest(method: "initialize", params: params)
        try sendNotification(method: "initialized", params: [:])
        initialized = true
    }

    /// Queries go-to-definition for a 0-based line/character inside `fileURL`.
    public func definition(fileURL: URL, line: Int, character: Int) async throws -> [Location] {
        if !initialized { try await start() }
        try openDocumentIfNeeded(fileURL: fileURL)
        let params: [String: Any] = [
            "textDocument": ["uri": fileURL.absoluteString],
            "position": ["line": line, "character": character],
        ]
        let response = try sendRequest(method: "textDocument/definition", params: params)
        return parseLocations(from: response["result"])
    }

    /// Gracefully shuts down the LSP process.
    public func stop() {
        if initialized {
            _ = try? sendRequest(method: "shutdown", params: nil)
            try? sendNotification(method: "exit", params: nil)
        }
        process?.terminate()
        process = nil
        initialized = false
    }

    private func openDocumentIfNeeded(fileURL: URL) throws {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        try sendNotification(method: "textDocument/didOpen", params: [
            "textDocument": [
                "uri": fileURL.absoluteString,
                "languageId": "swift",
                "version": 1,
                "text": text,
            ],
        ])
    }

    private func sendNotification(method: String, params: [String: Any]?) throws {
        var payload: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { payload["params"] = params }
        try writeFramed(payload)
    }

    private func sendRequest(method: String, params: [String: Any]?) throws -> [String: Any] {
        let id = nextRequestID
        nextRequestID += 1
        var payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { payload["params"] = params }
        try writeFramed(payload)

        while let message = try readFramed() {
            if let respID = message["id"] as? Int, respID == id {
                return message
            }
        }
        return [:]
    }

    private func writeFramed(_ object: [String: Any]) throws {
        guard let stdinHandle else { return }
        let body = try JSONSerialization.data(withJSONObject: object)
        let header = "Content-Length: \(body.count)\r\n\r\n"
        stdinHandle.write(Data(header.utf8))
        stdinHandle.write(body)
    }

    private func readFramed() throws -> [String: Any]? {
        guard let stdoutHandle else { return nil }
        var headerBytes = Data()
        let delimiter = Data("\r\n\r\n".utf8)
        while true {
            let chunk = stdoutHandle.readData(ofLength: 1)
            if chunk.isEmpty { return nil }
            headerBytes.append(chunk)
            if headerBytes.suffix(4) == delimiter { break }
        }
        let headerStr = String(data: headerBytes, encoding: .utf8) ?? ""
        var contentLength = 0
        for line in headerStr.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:"),
               let val = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") {
                contentLength = val
            }
        }
        guard contentLength > 0 else { return nil }
        var body = Data()
        while body.count < contentLength {
            let chunk = stdoutHandle.readData(ofLength: contentLength - body.count)
            if chunk.isEmpty { break }
            body.append(chunk)
        }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private func parseLocations(from result: Any?) -> [Location] {
        let rawList: [[String: Any]]
        if let single = result as? [String: Any] {
            rawList = [single]
        } else if let array = result as? [[String: Any]] {
            rawList = array
        } else {
            return []
        }
        return rawList.compactMap { item in
            guard let uri = item["uri"] as? String,
                  let range = item["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let line = start["line"] as? Int,
                  let ch = start["character"] as? Int else { return nil }
            return Location(uri: uri, line: line, character: ch)
        }
    }

    private func resolveExecutable(_ name: String) -> String {
        if name.hasPrefix("/") { return name }
        for prefix in ["/usr/bin/", "/usr/local/bin/", "/opt/homebrew/bin/"] {
            if FileManager.default.isExecutableFile(atPath: prefix + name) {
                return prefix + name
            }
        }
        return "/usr/bin/env"
    }
}
