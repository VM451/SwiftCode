import Foundation

/// Pure-Swift MCP client communicating over newline-delimited JSON-RPC 2.0 stdio (FR-4.2).
public actor MCPStdioClient {
    public let serverName: String
    private let command: String
    private let arguments: [String]
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextID = 1

    public init(serverName: String, command: String, arguments: [String] = []) {
        self.serverName = serverName
        self.command = command
        self.arguments = arguments
    }

    public func connect() throws {
        guard process == nil else { return }
        let proc = Process()
        if command.hasPrefix("/") {
            proc.executableURL = URL(fileURLWithPath: command)
            proc.arguments = arguments
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [command] + arguments
        }
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        self.process = proc
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading

        let initParams: JSONValue = .object([
            "protocolVersion": .string("2025-03-26"),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("SwiftCode"), "version": .string("2.0.0")]),
        ])
        _ = try sendRequest(method: "initialize", params: initParams)
        try sendNotification(method: "notifications/initialized", params: .object([:]))
    }

    public func listTools() throws -> [MCPToolDescriptor] {
        if process == nil { try connect() }
        let resp = try sendRequest(method: "tools/list", params: .object([:]))
        guard case .object(let root) = resp.result,
              case .array(let items) = root["tools"] else {
            return []
        }
        return items.compactMap { item in
            guard case .object(let obj) = item,
                  let name = obj["name"]?.stringValue else { return nil }
            return MCPToolDescriptor(
                name: name,
                description: obj["description"]?.stringValue,
                inputSchema: obj["inputSchema"]
            )
        }
    }

    public func callTool(name: String, arguments: JSONValue) throws -> ToolOutput {
        if process == nil { try connect() }
        let resp = try sendRequest(
            method: "tools/call",
            params: .object(["name": .string(name), "arguments": arguments])
        )
        if let err = resp.error {
            return .failure("MCP error \(err.code): \(err.message)")
        }
        guard case .object(let obj) = resp.result else {
            return .success("")
        }
        let isError: Bool = if case .bool(let b) = obj["isError"] { b } else { false }
        var texts: [String] = []
        if case .array(let content) = obj["content"] {
            for entry in content {
                if case .object(let cObj) = entry, let text = cObj["text"]?.stringValue {
                    texts.append(text)
                }
            }
        }
        let joined = texts.joined(separator: "\n")
        return isError ? .failure(joined) : .success(joined)
    }

    /// Registers all discovered MCP tools into `ToolRegistry` prefixed cleanly as `mcp_<server>_<tool>`.
    public func registerTools(into registry: ToolRegistry) async throws {
        let descriptors = try listTools()
        for desc in descriptors {
            let adapter = MCPToolAdapter(serverName: serverName, descriptor: desc, client: self)
            await registry.register(adapter)
        }
    }

    public func disconnect() {
        process?.terminate()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
    }

    private func sendNotification(method: String, params: JSONValue?) throws {
        let req = JSONRPCRequest(id: nil, method: method, params: params)
        var data = try JSONEncoder().encode(req)
        data.append(0x0A)
        stdinHandle?.write(data)
    }

    private func sendRequest(method: String, params: JSONValue?) throws -> JSONRPCResponse {
        let id = nextID
        nextID += 1
        let req = JSONRPCRequest(id: id, method: method, params: params)
        var data = try JSONEncoder().encode(req)
        data.append(0x0A)
        stdinHandle?.write(data)

        while let lineData = readLineData() {
            if let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: lineData),
               resp.id == id {
                return resp
            }
        }
        throw NSError(domain: "MCPStdioClient", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "EOF waiting for MCP response to \(method)",
        ])
    }

    private func readLineData() -> Data? {
        guard let stdoutHandle else { return nil }
        var buffer = Data()
        while true {
            let chunk = stdoutHandle.readData(ofLength: 1)
            if chunk.isEmpty {
                return buffer.isEmpty ? nil : buffer
            }
            if chunk[0] == 0x0A {
                return buffer
            }
            buffer.append(chunk)
        }
    }
}

/// Adapts a remote MCP tool into a native `SwiftCodeTool` inside `ToolRegistry`.
public struct MCPToolAdapter: SwiftCodeTool, Sendable {
    public let name: String
    public let description: String
    public let riskLevel: ToolRiskLevel = .networkAccess
    public let inputSchemaJSON: String
    private let remoteName: String
    private let client: MCPStdioClient

    public init(serverName: String, descriptor: MCPToolDescriptor, client: MCPStdioClient) {
        self.name = "mcp_\(serverName)_\(descriptor.name)"
        self.remoteName = descriptor.name
        self.description = descriptor.description ?? "MCP tool \(descriptor.name) from \(serverName)"
        self.inputSchemaJSON = descriptor.inputSchema?.jsonString ?? "{\"type\":\"object\",\"properties\":{}}"
        self.client = client
    }

    public func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        let argsValue = (try? JSONDecoder().decode(JSONValue.self, from: Data(argumentsJSON.utf8))) ?? .object([:])
        return try await client.callTool(name: remoteName, arguments: argsValue)
    }
}
