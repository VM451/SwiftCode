import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeCore

/// Pure-Swift Discord Gateway WebSocket (`URLSessionWebSocketTask`) + Bot REST client (FR-8.2).
public actor DiscordBridge: ChatBridge {
    public nonisolated let bridgeID = "discord"
    private let secretStore: any SecretStore
    private let transport: HTTPTransport
    private var runnerTask: Task<Void, Never>?
    #if canImport(Darwin)
    private var socketTask: URLSessionWebSocketTask?
    #endif
    private var lastSequence: Int?

    public init(secretStore: any SecretStore = SecretStoreFactory.makeDefault(), transport: HTTPTransport = .shared) {
        self.secretStore = secretStore
        self.transport = transport
    }

    public func start(onMessage: @escaping @Sendable (BridgeMessage) async -> String) async throws {
        guard runnerTask == nil else { return }
        guard let token = await SecretStoreFactory.resolveSecret(key: SecretKey.discordBotToken.rawValue, store: secretStore),
              !token.isEmpty else { return }

        #if canImport(Darwin)
        guard let gatewayURL = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        let ws = URLSession.shared.webSocketTask(with: gatewayURL)
        self.socketTask = ws
        ws.resume()

        let identify: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "intents": 33281,
                "properties": ["os": "macos", "browser": "SwiftCode", "device": "SwiftCode"],
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: identify),
           let text = String(data: data, encoding: .utf8) {
            try? await ws.send(.string(text))
        }

        runnerTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    guard case .string(let raw) = message else { continue }
                    await handleGatewayPayload(raw, onMessage: onMessage)
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
        guard let token = await SecretStoreFactory.resolveSecret(key: SecretKey.discordBotToken.rawValue, store: secretStore),
              let url = URL(string: "https://discord.com/api/v10/channels/\(channelID)/messages") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": String(text.prefix(1900))])
        _ = try await transport.data(for: req)
    }

    private func handleGatewayPayload(_ raw: String, onMessage: @escaping @Sendable (BridgeMessage) async -> String) async {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let s = json["s"] as? Int { lastSequence = s }
        if (json["t"] as? String) == "MESSAGE_CREATE",
           let d = json["d"] as? [String: Any],
           let content = d["content"] as? String,
           let channelID = d["channel_id"] as? String,
           let author = d["author"] as? [String: Any],
           (author["bot"] as? Bool) != true {
            let username = author["username"] as? String ?? "discord-user"
            let reply = await onMessage(BridgeMessage(channelID: channelID, senderName: username, text: content))
            try? await sendReply(channelID: channelID, text: reply)
        }
    }
}
