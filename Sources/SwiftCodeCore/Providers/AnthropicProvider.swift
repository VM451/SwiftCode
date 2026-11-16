import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native Anthropic Messages API SSE streaming adapter (FR-2.1).
public struct AnthropicProvider: LLMProvider, Sendable {
    public let providerID = "anthropic"
    private let apiKey: String?
    private let secretStore: any SecretStore
    private let endpoint: URL
    private let transport: HTTPTransport

    public init(
        apiKey: String? = nil,
        secretStore: any SecretStore = SecretStoreFactory.makeDefault(),
        baseURL: String = "https://api.anthropic.com",
        transport: HTTPTransport = .shared
    ) {
        self.apiKey = apiKey
        self.secretStore = secretStore
        self.endpoint = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/messages")!
        self.transport = transport
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = await resolveKey(), !key.isEmpty else {
                        throw LLMProviderError.missingAPIKey(provider: providerID, secretKey: SecretKey.anthropicAPIKey.rawValue)
                    }
                    let urlRequest = try buildRequest(request: request, apiKey: key)
                    var parser = SSEParser()
                    var activeBlockTools: [Int: String] = [:]
                    for try await line in transport.streamLines(for: urlRequest) {
                        if let event = parser.feed(line: line) {
                            processEvent(event, activeBlockTools: &activeBlockTools, continuation: continuation)
                        }
                    }
                    if let tail = parser.flush() {
                        processEvent(tail, activeBlockTools: &activeBlockTools, continuation: continuation)
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
        return await SecretStoreFactory.resolveSecret(key: SecretKey.anthropicAPIKey.rawValue, store: secretStore)
    }

    private func buildRequest(request: LLMRequest, apiKey: String) throws -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

        var payload: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "messages": serializeMessages(request.messages),
        ]
        if !request.systemPrompt.isEmpty {
            payload["system"] = [[
                "type": "text",
                "text": request.systemPrompt,
                "cache_control": ["type": "ephemeral"],
            ]]
        }
        if !request.tools.isEmpty {
            payload["tools"] = request.tools.compactMap { tool -> [String: Any]? in
                guard let data = tool.inputSchemaJSON.data(using: .utf8),
                      let schema = try? JSONSerialization.jsonObject(with: data) else { return nil }
                return ["name": tool.name, "description": tool.description, "input_schema": schema]
            }
        }
        if request.enableReasoning {
            payload["thinking"] = ["type": "enabled", "budget_tokens": min(4096, max(1024, request.maxTokens / 2))]
        } else {
            payload["temperature"] = request.temperature
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    private func serializeMessages(_ messages: [ConversationMessage]) -> [[String: Any]] {
        messages.compactMap { msg in
            switch msg.role {
            case .system:
                return nil
            case .user:
                var blocks: [[String: Any]] = []
                for img in msg.attachments {
                    blocks.append([
                        "type": "image",
                        "source": ["type": "base64", "media_type": img.mimeType, "data": img.base64Data],
                    ])
                }
                blocks.append(["type": "text", "text": msg.content])
                return ["role": "user", "content": blocks]
            case .assistant:
                var blocks: [[String: Any]] = []
                if !msg.content.isEmpty {
                    blocks.append(["type": "text", "text": msg.content])
                }
                for call in msg.toolCalls {
                    let inputObj = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [:]
                    blocks.append(["type": "tool_use", "id": call.id, "name": call.name, "input": inputObj])
                }
                return ["role": "assistant", "content": blocks]
            case .tool:
                return [
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": msg.toolCallID ?? "",
                        "content": msg.content,
                    ]],
                ]
            }
        }
    }

    private func processEvent(
        _ event: SSEEvent,
        activeBlockTools: inout [Int: String],
        continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
    ) {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "message_start":
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                let input = usage["input_tokens"] as? Int ?? 0
                let cached = usage["cache_read_input_tokens"] as? Int ?? 0
                continuation.yield(.usage(inputTokens: input, outputTokens: 0, cachedTokens: cached))
            }
        case "content_block_start":
            if let idx = json["index"] as? Int,
               let block = json["content_block"] as? [String: Any],
               (block["type"] as? String) == "tool_use",
               let id = block["id"] as? String,
               let name = block["name"] as? String {
                activeBlockTools[idx] = id
                continuation.yield(.toolCallStart(id: id, name: name))
            }
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return }
            if deltaType == "text_delta", let text = delta["text"] as? String {
                continuation.yield(.textDelta(text))
            } else if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String {
                continuation.yield(.reasoningDelta(thinking))
            } else if deltaType == "input_json_delta",
                      let partial = delta["partial_json"] as? String,
                      let idx = json["index"] as? Int,
                      let id = activeBlockTools[idx] {
                continuation.yield(.toolCallArgumentsDelta(id: id, delta: partial))
            }
        case "message_delta":
            if let usage = json["usage"] as? [String: Any] {
                let output = usage["output_tokens"] as? Int ?? 0
                continuation.yield(.usage(inputTokens: 0, outputTokens: output, cachedTokens: 0))
            }
            if let delta = json["delta"] as? [String: Any],
               let stop = delta["stop_reason"] as? String {
                continuation.yield(.finished(stopReason: stop))
            }
        default:
            break
        }
    }
}
