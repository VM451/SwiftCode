import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeCore

/// Pure-Swift Telegram Bot API bridge with HTTPS long-polling and inline keyboard approval buttons (FR-8.2).
public actor TelegramBridge: ChatBridge {
    public nonisolated let bridgeID = "telegram"
    private let secretStore: any SecretStore
    private let transport: HTTPTransport
    private var pollingTask: Task<Void, Never>?
    private var updateOffset: Int = 0
    private var pendingApprovals: [String: CheckedContinuation<ApprovalResolution, Never>] = [:]

    public init(secretStore: any SecretStore = SecretStoreFactory.makeDefault(), transport: HTTPTransport = .shared) {
        self.secretStore = secretStore
        self.transport = transport
    }

    public func start(onMessage: @escaping @Sendable (BridgeMessage) async -> String) async throws {
        guard pollingTask == nil else { return }
        guard let token = await SecretStoreFactory.resolveSecret(key: SecretKey.telegramBotToken.rawValue, store: secretStore),
              !token.isEmpty else { return }

        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    try await pollOnce(token: token, onMessage: onMessage)
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    public func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func sendReply(channelID: String, text: String) async throws {
        guard let token = await SecretStoreFactory.resolveSecret(key: SecretKey.telegramBotToken.rawValue, store: secretStore) else { return }
        try await postBotMethod(token: token, method: "sendMessage", payload: [
            "chat_id": channelID,
            "text": String(text.prefix(4000)),
        ])
    }

    /// Sends an interactive `[Allow Once | Allow Session | Deny]` inline keyboard prompt to Telegram.
    public func requestApproval(chatID: String, request: ApprovalRequest) async -> ApprovalResolution {
        guard let token = await SecretStoreFactory.resolveSecret(key: SecretKey.telegramBotToken.rawValue, store: secretStore) else {
            return .deny("Missing Telegram token")
        }
        let callID = request.call.id
        let keyboard: [[[String: String]]] = [[
            ["text": "Allow Once", "callback_data": "allow:\(callID)"],
            ["text": "Allow Session", "callback_data": "session:\(callID)"],
            ["text": "Deny", "callback_data": "deny:\(callID)"],
        ]]
        let body = "Approval needed: \(request.summary)\n\(request.diffPreview?.prefix(1500) ?? request.call.argumentsJSON.prefix(800))"
        try? await postBotMethod(token: token, method: "sendMessage", payload: [
            "chat_id": chatID,
            "text": body,
            "reply_markup": ["inline_keyboard": keyboard],
        ])
        return await withCheckedContinuation { continuation in
            pendingApprovals[callID] = continuation
        }
    }

    private func pollOnce(token: String, onMessage: @escaping @Sendable (BridgeMessage) async -> String) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?timeout=25&offset=\(updateOffset)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 35
        let (data, _) = try await transport.data(for: req, maxRetries: 1)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updates = json["result"] as? [[String: Any]] else { return }

        for update in updates {
            if let uid = update["update_id"] as? Int { updateOffset = max(updateOffset, uid + 1) }
            if let callback = update["callback_query"] as? [String: Any],
               let cbData = callback["data"] as? String {
                resolveCallback(cbData)
                if let cbID = callback["id"] as? String {
                    try? await postBotMethod(token: token, method: "answerCallbackQuery", payload: ["callback_query_id": cbID])
                }
            } else if let msg = update["message"] as? [String: Any],
                      let text = msg["text"] as? String,
                      let chat = msg["chat"] as? [String: Any],
                      let chatID = chat["id"] {
                let from = (msg["from"] as? [String: Any])?["username"] as? String ?? "telegram-user"
                let reply = await onMessage(BridgeMessage(channelID: "\(chatID)", senderName: from, text: text))
                try? await sendReply(channelID: "\(chatID)", text: reply)
            }
        }
    }

    private func resolveCallback(_ data: String) {
        let parts = data.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let continuation = pendingApprovals.removeValue(forKey: parts[1]) else { return }
        switch parts[0] {
        case "allow": continuation.resume(returning: .allowOnce)
        case "session": continuation.resume(returning: .allowForSession)
        default: continuation.resume(returning: .deny("Denied from Telegram"))
        }
    }

    private func postBotMethod(token: String, method: String, payload: [String: Any]) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await transport.data(for: req)
    }
}
