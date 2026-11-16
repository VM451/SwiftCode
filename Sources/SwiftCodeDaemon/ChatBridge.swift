import Foundation
import SwiftCodeCore

/// Message received or sent through any native chat bridge.
public struct BridgeMessage: Sendable, Equatable {
    public let channelID: String
    public let senderName: String
    public let text: String

    public init(channelID: String, senderName: String, text: String) {
        self.channelID = channelID
        self.senderName = senderName
        self.text = text
    }
}

/// Native pure-Swift chat bridge contract (Telegram, Discord, Slack, Apple Shortcuts).
public protocol ChatBridge: Sendable {
    var bridgeID: String { get }
    func start(onMessage: @escaping @Sendable (BridgeMessage) async -> String) async throws
    func stop() async
    func sendReply(channelID: String, text: String) async throws
}
