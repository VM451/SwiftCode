import Foundation

/// Pure-Swift stdio MCP server exposing SwiftCode tools (`--mcp-server` / `swiftcode mcp serve`).
public actor MCPStdioServer {
    private let registry: ToolRegistry
    private let workspaceRoot: URL
    private let sandboxPolicy: SandboxPolicy

    public init(
        registry: ToolRegistry = .makeDefault(),
        workspaceRoot: URL,
        sandboxPolicy: SandboxPolicy? = nil
    ) {
        self.registry = registry
        self.workspaceRoot = workspaceRoot
        self.sandboxPolicy = sandboxPolicy ?? SandboxPolicy(tier: .seatbelt, workspaceRoot: workspaceRoot)
    }

    /// Processes a single JSON-RPC 2.0 request line and returns an encoded response (nil for notifications).
    public func handleRequestLine(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8),
              let req = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            return encode(JSONRPCResponse(id: nil, error: .init(code: -32700, message: "Parse error")))
        }
        guard let id = req.id else {
            return nil // JSON-RPC notifications produce no reply
        }

        switch req.method {
        case "initialize":
            let result: JSONValue = .object([
                "protocolVersion": .string("2025-03-26"),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string("SwiftCode"), "version": .string("2.0.0")]),
            ])
            return encode(JSONRPCResponse(id: id, result: result))

        case "tools/list":
            let defs = await registry.definitions(for: .build)
            let list: [JSONValue] = defs.map { def in
                let schema = (try? JSONDecoder().decode(JSONValue.self, from: Data(def.inputSchemaJSON.utf8)))
                    ?? .object(["type": .string("object")])
                return .object([
                    "name": .string(def.name),
                    "description": .string(def.description),
                    "inputSchema": schema,
                ])
            }
            return encode(JSONRPCResponse(id: id, result: .object(["tools": .array(list)])))

        case "tools/call":
            return await handleCallTool(id: id, params: req.params)

        case "ping":
            return encode(JSONRPCResponse(id: id, result: .object([:])))

        default:
            return encode(JSONRPCResponse(id: id, error: .init(code: -32601, message: "Method not found: \(req.method)")))
        }
    }

    /// Runs the blocking stdin/stdout event loop until EOF.
    public func runStdioLoop() async {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if let reply = await handleRequestLine(trimmed) {
                print(reply)
                fflush(stdout)
            }
        }
    }

    private func handleCallTool(id: Int, params: JSONValue?) async -> String {
        guard case .object(let obj) = params,
              let name = obj["name"]?.stringValue else {
            return encode(JSONRPCResponse(id: id, error: .init(code: -32602, message: "Missing tool name")))
        }
        guard let tool = await registry.tool(named: name) else {
            return encode(JSONRPCResponse(id: id, error: .init(code: -32602, message: "Unknown tool: \(name)")))
        }
        let argsJSON = obj["arguments"]?.jsonString ?? "{}"
        let ctx = ToolContext(sessionID: UUID(), workspaceRoot: workspaceRoot, mode: .build, sandboxPolicy: sandboxPolicy)
        do {
            let output = try await tool.execute(argumentsJSON: argsJSON, context: ctx)
            let result: JSONValue = .object([
                "isError": .bool(output.isError),
                "content": .array([.object(["type": .string("text"), "text": .string(output.content)])]),
            ])
            return encode(JSONRPCResponse(id: id, result: result))
        } catch {
            return encode(JSONRPCResponse(id: id, error: .init(code: -32000, message: error.localizedDescription)))
        }
    }

    private func encode(_ response: JSONRPCResponse) -> String {
        guard let data = try? JSONEncoder().encode(response),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Encoding failure\"}}"
        }
        return str
    }
}
