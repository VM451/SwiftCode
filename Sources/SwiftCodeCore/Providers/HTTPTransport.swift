import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cross-platform HTTP & streaming transport built solely on `URLSession`.
public final class HTTPTransport: Sendable {
    public static let shared = HTTPTransport()
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    /// Performs a single request with resilient exponential backoff + jitter on 429/502/503/529 (FR-2.3).
    public func data(for request: URLRequest, maxRetries: Int = 3) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await performData(request)
                guard let http = response as? HTTPURLResponse else {
                    throw LLMProviderError.streamInterrupted("Non-HTTP response")
                }
                if [429, 502, 503, 529].contains(http.statusCode), attempt < maxRetries {
                    let retryAfter = parseRetryAfter(http)
                    try await sleepBackoff(attempt: attempt, retryAfter: retryAfter)
                    attempt += 1
                    continue
                }
                return (data, http)
            } catch let error as LLMProviderError where error.isRetryable && attempt < maxRetries {
                try await sleepBackoff(attempt: attempt, retryAfter: nil)
                attempt += 1
            }
        }
    }

    /// Streams raw lines from an HTTP response using `URLSession.bytes` on Darwin or data fallback on Linux.
    public func streamLines(
        for request: URLRequest,
        maxRetries: Int = 3
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                while true {
                    do {
                        #if canImport(Darwin)
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else {
                            throw LLMProviderError.streamInterrupted("Non-HTTP response")
                        }
                        if http.statusCode >= 400 {
                            var bodyData = Data()
                            for try await byte in bytes {
                                bodyData.append(byte)
                                if bodyData.count > 16_384 { break }
                            }
                            let body = String(data: bodyData, encoding: .utf8) ?? ""
                            let retryAfter = parseRetryAfter(http)
                            let err = LLMProviderError.httpStatus(http.statusCode, body: body, retryAfterSeconds: retryAfter)
                            if err.isRetryable, attempt < maxRetries {
                                try await sleepBackoff(attempt: attempt, retryAfter: retryAfter)
                                attempt += 1
                                continue
                            }
                            throw err
                        }
                        for try await line in bytes.lines {
                            continuation.yield(line)
                        }
                        continuation.finish()
                        return
                        #else
                        let (data, http) = try await self.data(for: request, maxRetries: maxRetries)
                        if http.statusCode >= 400 {
                            let body = String(data: data, encoding: .utf8) ?? ""
                            throw LLMProviderError.httpStatus(http.statusCode, body: body, retryAfterSeconds: parseRetryAfter(http))
                        }
                        let text = String(data: data, encoding: .utf8) ?? ""
                        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                            continuation.yield(String(line))
                        }
                        continuation.finish()
                        return
                        #endif
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func performData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(Darwin)
        return try await session.data(for: request)
        #else
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: LLMProviderError.streamInterrupted("Empty URLSession callback"))
                }
            }
            task.resume()
        }
        #endif
    }

    private func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return seconds
    }

    private func sleepBackoff(attempt: Int, retryAfter: TimeInterval?) async throws {
        let base = retryAfter ?? min(30.0, pow(2.0, Double(attempt)))
        let jitter = Double.random(in: 0.0...0.35)
        try await Task.sleep(for: .seconds(base + jitter))
    }
}
