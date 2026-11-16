import Foundation
import SwiftCodeCore

/// Value-type session summary displayed in the sidebar.
struct AgentSessionItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var workspacePath: String
    var mode: AgentMode
    var updatedAt: Date
    var totalTokens: Int
    var estimatedCostUSD: Double
}
