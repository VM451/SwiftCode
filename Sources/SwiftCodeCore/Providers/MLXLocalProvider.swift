import Foundation

/// Apple Silicon local inference provider via MLX Swift server (`127.0.0.1:8080/v1`) or OpenAI-compatible socket (FR-2.1).
public struct MLXLocalProvider: LLMProvider, Sendable {
    public let providerID = "mlx-local"
    private let delegate: OpenAIProvider

    public init(baseURL: String = "http://127.0.0.1:8080/v1", transport: HTTPTransport = .shared) {
        self.delegate = OpenAIProvider(
            providerID: "mlx-local",
            apiKey: "mlx-local",
            baseURL: baseURL,
            transport: transport
        )
    }

    public static var isAppleSiliconSupported: Bool {
        #if os(macOS) && arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        delegate.streamCompletion(request: request)
    }
}
