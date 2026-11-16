import Foundation
import Testing
@testable import SwiftCodeCore

struct MockScriptedProvider: LLMProvider, Sendable {
    let providerID: String
    let script: @Sendable (LLMRequest) throws -> [LLMStreamChunk]

    func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            do {
                for chunk in try script(request) {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

struct SSEAndProviderTests {
    @Test func sseParserDecodesMultiLineEventsAndIgnoresComments() {
        var parser = SSEParser()
        #expect(parser.feed(line: ": keepalive") == nil)
        #expect(parser.feed(line: "event: content_block_delta") == nil)
        #expect(parser.feed(line: "data: {\"hello\":") == nil)
        #expect(parser.feed(line: "data: \"world\"}") == nil)

        let event = parser.feed(line: "")
        #expect(event?.event == "content_block_delta")
        #expect(event?.data == "{\"hello\":\n\"world\"}")
    }

    @Test func fallbackProviderSwitchesOnPrimaryError() async throws {
        let primary = MockScriptedProvider(providerID: "primary") { _ in
            throw LLMProviderError.httpStatus(503, body: "Overloaded", retryAfterSeconds: nil)
        }
        let backup = MockScriptedProvider(providerID: "backup") { req in
            [
                .textDelta("Recovered via \(req.model)"),
                .usage(inputTokens: 10, outputTokens: 5, cachedTokens: 0),
                .finished(stopReason: "stop"),
            ]
        }

        let resilient = FallbackLLMProvider(primary: primary, fallback: backup, fallbackModel: "backup-model")
        let req = LLMRequest(model: "primary-model", systemPrompt: "", messages: [ConversationMessage(role: .user, content: "hi")])
        var text = ""
        for try await chunk in resilient.streamCompletion(request: req) {
            if case .textDelta(let d) = chunk { text += d }
        }
        #expect(text == "Recovered via backup-model")
    }

    @Test func htmlMarkdownConverterStripsScriptsAndPreservesLinks() {
        let html = """
        <html><head><script>alert(1)</script><style>body{}</style></head>
        <body><h1>SwiftCode</h1><p>Read <a href="https://swift.org">Swift Docs</a>.</p></body></html>
        """
        let md = HTMLMarkdownConverter.convert(html)
        #expect(md.contains("alert(1)") == false)
        #expect(md.contains("## SwiftCode"))
        #expect(md.contains("[Swift Docs](https://swift.org)"))
    }

    @Test func swiftDiagnosticParserExtractsErrorsAndColumns() {
        let log = """
        /tmp/Sources/App.swift:42:13: error: cannot find 'missingVar' in scope
        /tmp/Sources/App.swift:45:5: warning: immutable value 'x' was never used
        """
        let diags = SwiftDiagnosticParser.parse(log)
        #expect(diags.count == 2)
        #expect(diags[0].line == 42)
        #expect(diags[0].column == 13)
        #expect(diags[0].severity == "error")
        #expect(diags[0].message.contains("missingVar"))
    }
}
