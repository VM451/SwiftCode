import Foundation

/// Schema descriptor sent to LLM providers for tool calling.
public struct LLMToolDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchemaJSON: String

    public init(name: String, description: String, inputSchemaJSON: String) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
    }
}

/// Model-agnostic completion request.
public struct LLMRequest: Sendable {
    public let model: String
    public let systemPrompt: String
    public let messages: [ConversationMessage]
    public let tools: [LLMToolDefinition]
    public let maxTokens: Int
    public let temperature: Double
    public let enableReasoning: Bool

    public init(
        model: String,
        systemPrompt: String,
        messages: [ConversationMessage],
        tools: [LLMToolDefinition] = [],
        maxTokens: Int = 8192,
        temperature: Double = 0.2,
        enableReasoning: Bool = false
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enableReasoning = enableReasoning
    }
}

/// Streaming token/tool/usage events emitted by every `LLMProvider`.
public enum LLMStreamChunk: Sendable, Equatable {
    case reasoningDelta(String)
    case textDelta(String)
    case toolCallStart(id: String, name: String)
    case toolCallArgumentsDelta(id: String, delta: String)
    case usage(inputTokens: Int, outputTokens: Int, cachedTokens: Int)
    case finished(stopReason: String)
}

/// Errors thrown by `LLMProvider` implementations.
public enum LLMProviderError: Error, LocalizedError, Sendable {
    case missingAPIKey(provider: String, secretKey: String)
    case invalidEndpoint(String)
    case httpStatus(Int, body: String, retryAfterSeconds: TimeInterval?)
    case decodingFailed(String)
    case streamInterrupted(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider, let key):
            "Missing API key for \(provider). Store it with `swiftcode key set \(key)` or set $\(key)."
        case .invalidEndpoint(let url):
            "Invalid provider endpoint URL: \(url)"
        case .httpStatus(let status, let body, _):
            "Provider returned HTTP \(status): \(body.prefix(400))"
        case .decodingFailed(let detail):
            "Failed to decode provider response: \(detail)"
        case .streamInterrupted(let reason):
            "Stream interrupted: \(reason)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .httpStatus(let code, _, _):
            [429, 502, 503, 529].contains(code)
        case .streamInterrupted:
            true
        default:
            false
        }
    }
}

/// Unified model-agnostic streaming provider contract (PRD §6 / FR-2.1).
public protocol LLMProvider: Sendable {
    var providerID: String { get }
    func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error>
}
