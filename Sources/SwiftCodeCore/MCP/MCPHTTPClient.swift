import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP/SSE JSON-RPC 2.0 client for remote MCP servers (FR-4.2).
public actor MCPHTTPClient {
    public let serverName: String
    private let endpoint: URL
    private let transport: HTTPTransport
    private var nextID = 1

    public init(serverName: String, endpoint: URL, transport: HTTPTransport = .shared) {
        self.serverName = serverName
        self.endpoint = endpoint
        self.transport = transport
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        let resp = try await send(method: "tools/list", params: .object([:]))
        guard case .object(let obj) = resp.result,
              case .array(let list) = obj["tools"] else { return [] }
        return list.compactMap { entry in
            guard case .object(let dict) = entry,
                  let name = dict["name"]?.stringValue else { return nil }
            return MCPToolDescriptor(name: name, description: dict["description"]?.stringValue, inputSchema: dict["inputSchema"])
        }
    }

    public func callTool(name: String, arguments: JSONValue) async throws -> ToolOutput {
        let resp = try await send(method: "tools/call", params: .object(["name": .string(name), "arguments": arguments]))
        if let err = resp.error {
            return .failure("MCP HTTP error \(err.code): \(err.message)")
        }
        guard case .object(let obj) = resp.result else { return .success("") }
        var textOut: [String] = []
        if case .array(let content) = obj["content"] {
            for item in content {
                if case .object(let d) = item, let t = d["text"]?.stringValue { textOut.append(t) }
            }
        }
        return .success(textOut.joined(separator: "\n"))
    }

    private func send(method: String, params: JSONValue?) async throws -> JSONRPCResponse {
        let id = nextID
        nextID += 1
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(JSONRPCRequest(id: id, method: method, params: params))

        let (data, http) = try await transport.data(for: req)
        guard http.statusCode < 400 else {
            throw LLMProviderError.httpStatus(http.statusCode, body: String(decoding: data, as: UTF8.self), retryAfterSeconds: nil)
        }
        if let direct = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
            return direct
        }
        // Handle SSE envelope response if server replies with `data: { ... }`
        let text = String(decoding: data, as: UTF8.self)
        var parser = SSEParser()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let event = parser.feed(line: String(line)),
               let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: Data(event.data.utf8)) {
                return resp
            }
        }
        if let tail = parser.flush(),
           let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: Data(tail.data.utf8)) {
            return resp
        }
        throw LLMProviderError.decodingFailed("Invalid MCP HTTP response")
    }
}
