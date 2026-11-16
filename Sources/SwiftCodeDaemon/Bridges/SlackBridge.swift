import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeCore

/// Pure-Swift Slack Socket Mode client using `apps.connections.open` + `URLSessionWebSocketTask` (FR-8.2).
public actor SlackBridge: ChatBridge {
    public nonisolated let bridgeID = "slack"
    private let secretStore: any SecretStore
    private let transport: HTTPTransport
    private var runnerTask: Task<Void, Never>?
    #if canImport(Darwin)
    private var socketTask: URLSessionWebSocketTask?
    #endif

    public init(secretStore: any SecretStore = SecretStoreFactory.makeDefault(), transport: HTTPTransport = .shared) {
        self.secretStore = secretStore
        self.transport = transport
    }

    public func start(onMessage: @escaping @Sendable (BridgeMessage) async -> String) async throws {
        guard runnerTask == nil else { return }
        guard let appToken = await SecretStoreFactory.resolveSecret(key: SecretKey.slackAppToken.rawValue, store: secretStore),
              !appToken.isEmpty,
              let wssURL = try await openSocketURL(appToken: appToken) else { return }

        #if canImport(Darwin)
        let ws = URLSession.shared.webSocketTask(with: wssURL)
        self.socketTask = ws
        ws.resume()
        runnerTask = Task {
            while !Task.isCancelled {
                do {
                    let frame = try await ws.receive()
                    guard case .string(let raw) = frame else { continue }
                    await handleEnvelope(raw, ws: ws, onMessage: onMessage)
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        #endif
    }

    public func stop() async {
        runnerTask?.cancel()
        runnerTask = nil
        #if canImport(Darwin)
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        #endif
    }

    public func sendReply(channelID: String, text: String) async throws {
        guard let botToken = await SecretStoreFactory.resolveSecret(key: SecretKey.slackBotToken.rawValue, store: secretStore),
              let url = URL(string: "https://slack.com/api/chat.postMessage") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["channel": channelID, "text": text])
        _ = try await transport.data(for: req)
    }

    private func openSocketURL(appToken: String) async throws -> URL? {
        guard let url = URL(string: "https://slack.com/api/apps.connections.open") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await transport.data(for: req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let rawURL = json?["url"] as? String else { return nil }
        return URL(string: rawURL)
    }

    #if canImport(Darwin)
    private func handleEnvelope(
        _ raw: String,
        ws: URLSessionWebSocketTask,
        onMessage: @escaping @Sendable (BridgeMessage) async -> String
    ) async {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let envelopeID = json["envelope_id"] as? String {
            let ack = "{\"envelope_id\":\"\(envelopeID)\"}"
            try? await ws.send(.string(ack))
        }
        if let payload = json["payload"] as? [String: Any],
           let event = payload["event"] as? [String: Any],
           (event["type"] as? String) == "message" || (event["type"] as? String) == "app_mention",
           event["bot_id"] == nil,
           let text = event["text"] as? String,
           let channel = event["channel"] as? String {
            let user = event["user"] as? String ?? "slack-user"
            let reply = await onMessage(BridgeMessage(channelID: channel, senderName: user, text: text))
            try? await sendReply(channelID: channel, text: reply)
        }
    }
    #endif
}
