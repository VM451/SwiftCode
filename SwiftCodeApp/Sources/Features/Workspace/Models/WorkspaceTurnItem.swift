import Foundation
import SwiftCodeCore

/// Value-type conversation turn rendered in the Workspace timeline.
struct WorkspaceTurnItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: String
    var content: String
    var toolSummary: String?
    let createdAt: Date
}

/// Pending interactive HITL approval prompt shown in the Workspace UI.
struct PendingApprovalItem: Identifiable, Sendable {
    let id: String
    let summary: String
    let riskTitle: String
    let diffPreview: String?
    let argumentsPreview: String
}
