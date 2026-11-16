import Foundation
import Testing
@testable import SwiftCodeCore

struct MCPProtocolTests {
    @Test func mcpStdioServerHandlesInitializeListAndToolCall() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "let answer = 42\n".write(to: tempDir.appendingPathComponent("Answer.swift"), atomically: true, encoding: .utf8)

        let server = MCPStdioServer(workspaceRoot: tempDir)

        let initReply = try #require(await server.handleRequestLine("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))
        let initResp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(initReply.utf8))
        #expect(initResp.id == 1)
        #expect(initResp.error == nil)

        // Notifications must return nil
        let notifReply = await server.handleRequestLine("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")
        #expect(notifReply == nil)

        let listReply = try #require(await server.handleRequestLine("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
        #expect(listReply.contains("astOutline"))

        let callReq = """
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"readFile","arguments":{"path":"Answer.swift"}}}
        """
        let callReply = try #require(await server.handleRequestLine(callReq))
        #expect(callReply.contains("let answer = 42"))

        let missingMethod = try #require(await server.handleRequestLine("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"unknown/op\"}"))
        let missingResp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(missingMethod.utf8))
        #expect(missingResp.error?.code == -32601)
    }
}
