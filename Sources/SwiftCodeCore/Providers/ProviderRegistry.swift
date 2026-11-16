import Foundation

/// Cognitive role used to route requests across `architect`, `coder`, and `utility` models (FR-2.2).
public enum ModelRole: String, Sendable {
    case architect
    case coder
    case utility
}

/// Wraps a primary provider with automatic fallback to a secondary provider on failure (FR-2.3).
public struct FallbackLLMProvider: LLMProvider, Sendable {
    public let providerID: String
    private let primary: any LLMProvider
    private let fallback: (any LLMProvider)?
    private let fallbackModel: String?

    public init(primary: any LLMProvider, fallback: (any LLMProvider)? = nil, fallbackModel: String? = nil) {
        self.providerID = primary.providerID
        self.primary = primary
        self.fallback = fallback
        self.fallbackModel = fallbackModel
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var emittedAnyChunk = false
                do {
                    for try await chunk in primary.streamCompletion(request: request) {
                        emittedAnyChunk = true
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if !emittedAnyChunk, let fallback {
                        let fallbackReq = LLMRequest(
                            model: fallbackModel ?? request.model,
                            systemPrompt: request.systemPrompt,
                            messages: request.messages,
                            tools: request.tools,
                            maxTokens: request.maxTokens,
                            temperature: request.temperature,
                            enableReasoning: request.enableReasoning
                        )
                        do {
                            for try await chunk in fallback.streamCompletion(request: fallbackReq) {
                                continuation.yield(chunk)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Resolves concrete `LLMProvider` instances from `SwiftCodeConfiguration` and role assignments.
public struct ProviderRegistry: Sendable {
    private let secretStore: any SecretStore
    private let transport: HTTPTransport
    private let appleInspector: any AppleFoundationModelInspector

    public init(
        secretStore: any SecretStore = SecretStoreFactory.makeDefault(),
        transport: HTTPTransport = .shared,
        appleInspector: any AppleFoundationModelInspector = LiveAppleFoundationModelInspector()
    ) {
        self.secretStore = secretStore
        self.transport = transport
        self.appleInspector = appleInspector
    }

    public func assignment(for role: ModelRole, config: SwiftCodeConfiguration) -> ModelRoleAssignment {
        switch role {
        case .architect: config.models.architect
        case .coder: config.models.coder
        case .utility: config.models.utility
        }
    }

    public func provider(for assignment: ModelRoleAssignment, fallback: ModelRoleAssignment? = nil) -> any LLMProvider {
        let primary = makeProvider(id: assignment.provider, baseURL: assignment.baseURL)
        guard let fallback else { return primary }
        let fbProvider = makeProvider(id: fallback.provider, baseURL: fallback.baseURL)
        return FallbackLLMProvider(primary: primary, fallback: fbProvider, fallbackModel: fallback.model)
    }

    public func makeProvider(id: String, baseURL: String? = nil) -> any LLMProvider {
        switch id.lowercased() {
        case "apple-local":
            return AppleFoundationModelProvider(variant: .local, inspector: appleInspector)
        case "apple-pcc":
            return AppleFoundationModelProvider(variant: .privateCloudCompute, inspector: appleInspector)
        case "anthropic":
            return AnthropicProvider(secretStore: secretStore, baseURL: baseURL ?? "https://api.anthropic.com", transport: transport)
        case "openai":
            return OpenAIProvider(providerID: "openai", secretKeyName: SecretKey.openAIAPIKey.rawValue, secretStore: secretStore, baseURL: baseURL ?? "https://api.openai.com/v1", transport: transport)
        case "openrouter":
            return OpenAIProvider(providerID: "openrouter", secretKeyName: SecretKey.openRouterAPIKey.rawValue, secretStore: secretStore, baseURL: baseURL ?? "https://openrouter.ai/api/v1", transport: transport)
        case "gemini", "google":
            return GeminiProvider(secretStore: secretStore, baseURL: baseURL ?? "https://generativelanguage.googleapis.com/v1beta", transport: transport)
        case "mlx", "mlx-local":
            return MLXLocalProvider(baseURL: baseURL ?? "http://127.0.0.1:8080/v1", transport: transport)
        case "ollama":
            return OllamaProvider(baseURL: baseURL ?? "http://127.0.0.1:11434", transport: transport)
        default:
            return OpenAIProvider(providerID: id, secretKeyName: SecretKey.openAIAPIKey.rawValue, secretStore: secretStore, baseURL: baseURL ?? "https://api.openai.com/v1", transport: transport)
        }
    }
}
