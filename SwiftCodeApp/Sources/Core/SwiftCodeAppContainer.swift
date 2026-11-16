import Foundation
import SwiftData
import SwiftCodeCore
import SwiftCodeDaemon

/// Shared `@MainActor` container bridging SwiftData persistence and `SwiftCodeCore` services.
@MainActor
@Observable
final class SwiftCodeAppContainer {
    let modelContainer: ModelContainer
    let configurationStore = ConfigurationStore()
    let secretStore: any SecretStore
    let daemonService: DaemonService
    var workspaceRoot: URL

    init(inMemory: Bool = false, workspaceRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        let schema = Schema([SwiftCodeSessionRecord.self, SwiftCodeTurnRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
        self.secretStore = SecretStoreFactory.makeDefault()
        self.workspaceRoot = workspaceRoot
        let cfg = configurationStore.load(workspaceRoot: workspaceRoot)
        self.daemonService = DaemonService(workspaceRoot: workspaceRoot, configuration: cfg, secretStore: secretStore)
        if !inMemory {
            seedDefaultSessionIfNeeded()
        }
    }

    func fetchSessionSummaries() -> [AgentSessionItem] {
        let descriptor = FetchDescriptor<SwiftCodeSessionRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let records = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return records.map { rec in
            AgentSessionItem(
                id: rec.id,
                title: rec.title,
                workspacePath: rec.workspacePath,
                mode: AgentMode(rawValue: rec.modeRawValue) ?? .plan,
                updatedAt: rec.updatedAt,
                totalTokens: rec.totalTokens,
                estimatedCostUSD: rec.estimatedCostUSD
            )
        }
    }

    func createSession(title: String, mode: AgentMode) -> AgentSessionItem {
        let record = SwiftCodeSessionRecord(
            title: title,
            workspacePath: workspaceRoot.path,
            modeRawValue: mode.rawValue
        )
        modelContainer.mainContext.insert(record)
        try? modelContainer.mainContext.save()
        return AgentSessionItem(
            id: record.id,
            title: record.title,
            workspacePath: record.workspacePath,
            mode: mode,
            updatedAt: record.updatedAt,
            totalTokens: 0,
            estimatedCostUSD: 0
        )
    }

    func appendTurn(sessionID: UUID, role: String, content: String, toolSummary: String? = nil) {
        let descriptor = FetchDescriptor<SwiftCodeSessionRecord>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = (try? modelContainer.mainContext.fetch(descriptor))?.first else { return }
        let turn = SwiftCodeTurnRecord(roleRawValue: role, content: content, toolSummary: toolSummary, session: session)
        session.turns.append(turn)
        session.updatedAt = Date()
        modelContainer.mainContext.insert(turn)
        try? modelContainer.mainContext.save()
    }

    func fetchTurns(sessionID: UUID) -> [WorkspaceTurnItem] {
        let descriptor = FetchDescriptor<SwiftCodeSessionRecord>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = (try? modelContainer.mainContext.fetch(descriptor))?.first else { return [] }
        return session.turns.sorted { $0.createdAt < $1.createdAt }.map {
            WorkspaceTurnItem(
                id: $0.id,
                role: $0.roleRawValue,
                content: $0.content,
                toolSummary: $0.toolSummary,
                createdAt: $0.createdAt
            )
        }
    }

    private func seedDefaultSessionIfNeeded() {
        if fetchSessionSummaries().isEmpty {
            let initial = createSession(title: "SwiftCode Session", mode: .plan)
            appendTurn(
                sessionID: initial.id,
                role: "assistant",
                content: "Ready in **Plan Mode** (read-only). Switch to **Build Mode** in the toolbar to enable workspace mutations and automatic Shadow-Git checkpoints."
            )
        }
    }
}
