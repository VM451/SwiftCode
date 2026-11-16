import Foundation

/// Structured implementation blueprint generated in Plan Mode before Build Mode.
public struct ExecutionPlan: Codable, Sendable, Equatable, Identifiable {
    public struct Step: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let details: String
        public let targetFiles: [String]
        public var isCompleted: Bool

        public init(
            id: UUID = UUID(),
            title: String,
            details: String,
            targetFiles: [String] = [],
            isCompleted: Bool = false
        ) {
            self.id = id
            self.title = title
            self.details = details
            self.targetFiles = targetFiles
            self.isCompleted = isCompleted
        }
    }

    public let id: UUID
    public let sessionID: UUID
    public let summary: String
    public var steps: [Step]
    public let markdown: String
    public var approved: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        summary: String,
        steps: [Step] = [],
        markdown: String,
        approved: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.summary = summary
        self.steps = steps
        self.markdown = markdown
        self.approved = approved
        self.createdAt = createdAt
    }

    /// Persists the plan markdown to `.swiftcode/plans/<session-id>.md`.
    public func writeToWorkspace(_ workspaceRoot: URL) throws -> URL {
        let plansDir = workspaceRoot
            .appendingPathComponent(".swiftcode", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
        try FileManager.default.createDirectory(at: plansDir, withIntermediateDirectories: true)
        let target = plansDir.appendingPathComponent("\(sessionID.uuidString).md")
        try markdown.write(to: target, atomically: true, encoding: .utf8)
        return target
    }
}
