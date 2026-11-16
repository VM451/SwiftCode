import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Streaming adapter for OpenAI, OpenRouter, Groq, Together, vLLM, and OpenAI-compatible endpoints (FR-2.1).
public struct OpenAIProvider: LLMProvider, Sendable {
    public let providerID: String
    private let apiKey: String?
    private let secretKeyName: String
    private let secretStore: any SecretStore
    private let endpoint: URL
    private let transport: HTTPTransport

    public init(
        providerID: String = "openai",
        apiKey: String? = nil,
        secretKeyName: String = SecretKey.openAIAPIKey.rawValue,
        secretStore: any SecretStore = SecretStoreFactory.makeDefault(),
        baseURL: String = "https://api.openai.com/v1",
        transport: HTTPTransport = .shared
    ) {
        self.providerID = providerID
        self.apiKey = apiKey
        self.secretKeyName = secretKeyName
        self.secretStore = secretStore
        self.endpoint = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions")!
        self.transport = transport
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = await resolveKey()
                    if providerID != "ollama" && providerID != "mlx-local", (key ?? "").isEmpty {
                        throw LLMProviderError.missingAPIKey(provider: providerID, secretKey: secretKeyName)
                    }
                    let urlRequest = try buildRequest(request: request, apiKey: key)
                    var parser = SSEParser()
                    var indexToID: [Int: String] = [:]
                    for try await line in transport.streamLines(for: urlRequest) {
                        if let event = parser.feed(line: line) {
                            processEvent(event, indexToID: &indexToID, continuation: continuation)
                        }
                    }
                    if let tail = parser.flush() {
                        processEvent(tail, indexToID: &indexToID, continuation: continuation)
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
        return await SecretStoreFactory.resolveSecret(key: secretKeyName, store: secretStore)
    }

    private func buildRequest(request: LLMRequest, apiKey: String?) throws -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var msgs: [[String: Any]] = []
        if !request.systemPrompt.isEmpty {
            msgs.append(["role": "system", "content": request.systemPrompt])
        }
        for msg in request.messages {
            msgs.append(serializeMessage(msg))
        }

        var body: [String: Any] = [
            "model": request.model,
            "messages": msgs,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.compactMap { tool -> [String: Any]? in
                guard let data = tool.inputSchemaJSON.data(using: .utf8),
                      let schema = try? JSONSerialization.jsonObject(with: data) else { return nil }
                return [
                    "type": "function",
                    "function": ["name": tool.name, "description": tool.description, "parameters": schema],
                ]
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func serializeMessage(_ msg: ConversationMessage) -> [String: Any] {
        switch msg.role {
        case .system:
            return ["role": "system", "content": msg.content]
        case .user:
            if msg.attachments.isEmpty {
                return ["role": "user", "content": msg.content]
            }
            var parts: [[String: Any]] = [["type": "text", "text": msg.content]]
            for img in msg.attachments {
                parts.append(["type": "image_url", "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64Data)"]])
            }
            return ["role": "user", "content": parts]
        case .assistant:
            var dict: [String: Any] = ["role": "assistant", "content": msg.content]
            if !msg.toolCalls.isEmpty {
                dict["tool_calls"] = msg.toolCalls.map { call in
                    ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.argumentsJSON]]
                }
            }
            return dict
        case .tool:
            return ["role": "tool", "tool_call_id": msg.toolCallID ?? "", "content": msg.content]
        }
    }

    private func processEvent(
        _ event: SSEEvent,
        indexToID: inout [Int: String],
        continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
    ) {
        guard event.data != "[DONE]",
              let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let usage = json["usage"] as? [String: Any] {
            let input = usage["prompt_tokens"] as? Int ?? 0
            let output = usage["completion_tokens"] as? Int ?? 0
            let cached = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
            continuation.yield(.usage(inputTokens: input, outputTokens: output, cachedTokens: cached))
        }
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else { return }
        if let delta = first["delta"] as? [String: Any] {
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                continuation.yield(.reasoningDelta(reasoning))
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.textDelta(content))
            }
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let idx = call["index"] as? Int ?? 0
                    if let id = call["id"] as? String {
                        indexToID[idx] = id
                        let fn = call["function"] as? [String: Any]
                        let name = fn?["name"] as? String ?? ""
                        continuation.yield(.toolCallStart(id: id, name: name))
                    }
                    if let fn = call["function"] as? [String: Any],
                       let argsDelta = fn["arguments"] as? String,
                       !argsDelta.isEmpty,
                       let resolvedID = indexToID[idx] {
                        continuation.yield(.toolCallArgumentsDelta(id: resolvedID, delta: argsDelta))
                    }
                }
            }
        }
        if let finish = first["finish_reason"] as? String {
            continuation.yield(.finished(stopReason: finish))
        }
    }
}
