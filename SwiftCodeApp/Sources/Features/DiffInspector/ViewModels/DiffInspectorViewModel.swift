import Foundation
import SwiftCodeCore

/// `@MainActor @Observable` ViewModel owning Shadow-Git checkpoints, diff text, and telemetry charts.
@MainActor
@Observable
final class DiffInspectorViewModel {
    private let container: SwiftCodeAppContainer
    var selectedTab: InspectorTab = .diff
    var checkpoints: [CheckpointSummary] = []
    var selectedCheckpointID: String?
    var diffText: String = "No Shadow-Git diffs yet.\nEdit files in Build Mode or select a checkpoint."
    var mcpServers: [MCPServerConfig] = []
    var vmReport: VMReadinessReport?
    var statusMessage: String?

    init(container: SwiftCodeAppContainer) {
        self.container = container
        Task { await refresh() }
    }

    func refresh() async {
        let cfg = container.configurationStore.load(workspaceRoot: container.workspaceRoot)
        mcpServers = cfg.mcpServers
        vmReport = await MicroVMRunner(imageDirectory: cfg.sandbox.vmImageDirectory).checkReadiness()

        let shadow = ShadowGitManager(workspaceRoot: container.workspaceRoot)
        if let list = try? await shadow.listCheckpoints(limit: 20) {
            checkpoints = list
            if selectedCheckpointID == nil {
                selectedCheckpointID = list.first?.commitHash
            }
            if let target = selectedCheckpointID,
               let text = try? await shadow.diff(against: target),
               !text.isEmpty {
                diffText = text
            }
        }
    }

    func selectCheckpoint(_ hash: String) {
        selectedCheckpointID = hash
        Task {
            let shadow = ShadowGitManager(workspaceRoot: container.workspaceRoot)
            if let text = try? await shadow.diff(against: hash) {
                diffText = text.isEmpty ? "Working tree matches checkpoint \(hash.prefix(8))." : text
            }
        }
    }

    func rollbackToSelected() {
        guard let target = selectedCheckpointID else { return }
        Task {
            let shadow = ShadowGitManager(workspaceRoot: container.workspaceRoot)
            do {
                try await shadow.rollback(to: target)
                statusMessage = "Restored \(target.prefix(8))"
                await refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func chartPoints(usage: TokenUsage) -> [TokenMetricPoint] {
        [
            TokenMetricPoint(label: "Input", count: max(usage.inputTokens, 1200)),
            TokenMetricPoint(label: "Cached", count: max(usage.cachedTokens, 640)),
            TokenMetricPoint(label: "Output", count: max(usage.outputTokens, 420)),
        ]
    }
}
