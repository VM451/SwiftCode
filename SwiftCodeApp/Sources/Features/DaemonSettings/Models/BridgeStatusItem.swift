import Foundation

/// Represents a configured chat/webhook bridge status inside DaemonSettings.
struct BridgeStatusItem: Identifiable, Sendable, Equatable {
    var id: String { name }
    let name: String
    let isEnabled: Bool
    let secretKey: String
}
