import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native Google Gemini streaming SSE client (`streamGenerateContent?alt=sse`) (FR-2.1).
public struct GeminiProvider: LLMProvider, Sendable {
    public let providerID = "gemini"
    private let apiKey: String?
    private let secretStore: any SecretStore
    private let baseURL: String
    private let transport: HTTPTransport

    public init(
        apiKey: String? = nil,
        secretStore: any SecretStore = SecretStoreFactory.makeDefault(),
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta",
        transport: HTTPTransport = .shared
    ) {
        self.apiKey = apiKey
        self.secretStore = secretStore
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.transport = transport
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = await resolveKey(), !key.isEmpty else {
                        throw LLMProviderError.missingAPIKey(provider: providerID, secretKey: SecretKey.geminiAPIKey.rawValue)
                    }
                    let urlRequest = try buildRequest(request: request, apiKey: key)
                    var parser = SSEParser()
                    for try await line in transport.streamLines(for: urlRequest) {
                        if let event = parser.feed(line: line) {
                            processEvent(event, continuation: continuation)
                        }
                    }
                    if let tail = parser.flush() {
                        processEvent(tail, continuation: continuation)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func resolveKey() async -> String? {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        return await SecretStoreFactory.resolveSecret(key: SecretKey.geminiAPIKey.rawValue, store: secretStore)
    }

    private func buildRequest(request: LLMRequest, apiKey: String) throws -> URLRequest {
        let model = request.model.hasPrefix("models/") ? String(request.model.dropFirst(7)) : request.model
        guard let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse") else {
            throw LLMProviderError.invalidEndpoint(baseURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let contents = request.messages.compactMap { msg -> [String: Any]? in
            switch msg.role {
            case .system:
                return nil
            case .user:
                return ["role": "user", "parts": [["text": msg.content]]]
            case .assistant:
                var parts: [[String: Any]] = []
                if !msg.content.isEmpty { parts.append(["text": msg.content]) }
                for call in msg.toolCalls {
                    let args = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [:]
                    parts.append(["functionCall": ["name": call.name, "args": args]])
                }
                return ["role": "model", "parts": parts]
            case .tool:
                return [
                    "role": "user",
                    "parts": [[
                        "functionResponse": [
                            "name": msg.toolName ?? "tool",
                            "response": ["result": msg.content],
                        ],
                    ]],
                ]
            }
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": request.temperature,
                "maxOutputTokens": request.maxTokens,
            ],
        ]
        if !request.systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": request.systemPrompt]]]
        }
        if !request.tools.isEmpty {
            let declarations = request.tools.compactMap { tool -> [String: Any]? in
                guard let data = tool.inputSchemaJSON.data(using: .utf8),
                      let schema = try? JSONSerialization.jsonObject(with: data) else { return nil }
                return ["name": tool.name, "description": tool.description, "parameters": schema]
            }
            body["tools"] = [["functionDeclarations": declarations]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func processEvent(
        _ event: SSEEvent,
        continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
    ) {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let usage = json["usageMetadata"] as? [String: Any] {
            let input = usage["promptTokenCount"] as? Int ?? 0
            let output = usage["candidatesTokenCount"] as? Int ?? 0
            let cached = usage["cachedContentTokenCount"] as? Int ?? 0
            continuation.yield(.usage(inputTokens: input, outputTokens: output, cachedTokens: cached))
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return }

        for part in parts {
            let isThought = (part["thought"] as? Bool) ?? false
            if let text = part["text"] as? String {
                continuation.yield(isThought ? .reasoningDelta(text) : .textDelta(text))
            }
            if let fnCall = part["functionCall"] as? [String: Any],
               let name = fnCall["name"] as? String {
                let callID = "gemini_\(UUID().uuidString.prefix(8))"
                let argsObj = fnCall["args"] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: argsObj)) ?? Data("{}".utf8)
                let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
                continuation.yield(.toolCallStart(id: callID, name: name))
                continuation.yield(.toolCallArgumentsDelta(id: callID, delta: argsJSON))
            }
        }
        if let reason = first["finishReason"] as? String {
            continuation.yield(.finished(stopReason: reason))
        }
    }
}
