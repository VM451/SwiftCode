import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native Ollama `/api/chat` NDJSON streaming adapter for local models (FR-2.1).
public struct OllamaProvider: LLMProvider, Sendable {
    public let providerID = "ollama"
    private let endpoint: URL
    private let transport: HTTPTransport

    public init(baseURL: String = "http://127.0.0.1:11434", transport: HTTPTransport = .shared) {
        self.endpoint = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/chat")!
        self.transport = transport
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var msgs: [[String: Any]] = []
                    if !request.systemPrompt.isEmpty {
                        msgs.append(["role": "system", "content": request.systemPrompt])
                    }
                    for msg in request.messages {
                        msgs.append(["role": msg.role.rawValue, "content": msg.content])
                    }
                    let body: [String: Any] = ["model": request.model, "messages": msgs, "stream": true]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    for try await line in transport.streamLines(for: req) {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let msg = json["message"] as? [String: Any],
                           let content = msg["content"] as? String, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if (json["done"] as? Bool) == true {
                            let input = json["prompt_eval_count"] as? Int ?? 0
                            let output = json["eval_count"] as? Int ?? 0
                            continuation.yield(.usage(inputTokens: input, outputTokens: output, cachedTokens: 0))
                            continuation.yield(.finished(stopReason: "stop"))
                        }
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
}
