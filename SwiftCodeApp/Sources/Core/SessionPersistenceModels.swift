import Foundation
import SwiftData

/// SwiftData persistent session record stored locally in `SwiftCodeApp`.
@Model
final class SwiftCodeSessionRecord {
    var id: UUID
    var title: String
    var workspacePath: String
    var modeRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var totalTokens: Int
    var estimatedCostUSD: Double

    @Relationship(deleteRule: .cascade, inverse: \SwiftCodeTurnRecord.session)
    var turns: [SwiftCodeTurnRecord] = []

    init(
        id: UUID = UUID(),
        title: String,
        workspacePath: String,
        modeRawValue: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalTokens: Int = 0,
        estimatedCostUSD: Double = 0
    ) {
        self.id = id
        self.title = title
        self.workspacePath = workspacePath
        self.modeRawValue = modeRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

/// SwiftData persistent turn entry belonging to a `SwiftCodeSessionRecord`.
@Model
final class SwiftCodeTurnRecord {
    var id: UUID
    var roleRawValue: String
    var content: String
    var toolSummary: String?
    var createdAt: Date
    var session: SwiftCodeSessionRecord?

    init(
        id: UUID = UUID(),
        roleRawValue: String,
        content: String,
        toolSummary: String? = nil,
        createdAt: Date = Date(),
        session: SwiftCodeSessionRecord? = nil
    ) {
        self.id = id
        self.roleRawValue = roleRawValue
        self.content = content
        self.toolSummary = toolSummary
        self.createdAt = createdAt
        self.session = session
    }
}
