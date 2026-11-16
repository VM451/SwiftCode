import Foundation
import Logging
import SwiftCodeCore

/// Coordinates `DaemonServer`, `CronScheduler`, and enabled `ChatBridge` channels (FR-8.1..8.3).
public actor DaemonService {
    private let workspaceRoot: URL
    private let configuration: SwiftCodeConfiguration
    private let secretStore: any SecretStore
    private let logger = Logger(label: "dev.swiftcode.daemon")

    private var server: DaemonServer?
    private var cronScheduler = CronScheduler()
    private var telegramBridge: TelegramBridge?
    private var discordBridge: DiscordBridge?
    private var slackBridge: SlackBridge?
    private var startedAt = Date()
    private var processedTasks = 0

    public init(
        workspaceRoot: URL,
        configuration: SwiftCodeConfiguration = ConfigurationStore().load(),
        secretStore: any SecretStore = SecretStoreFactory.makeDefault()
    ) {
        self.workspaceRoot = workspaceRoot
        self.configuration = configuration
        self.secretStore = secretStore
    }

    public func start() async throws {
        startedAt = Date()
        let webhookSecret = await SecretStoreFactory.resolveSecret(
            key: SecretKey.githubWebhookSecret.rawValue,
            store: secretStore
        )
        let srv = DaemonServer(
            host: configuration.daemon.webhookHost,
            port: configuration.daemon.webhookPort,
            socketPath: configuration.daemon.socketPath,
            webhookSecret: webhookSecret,
            dispatcher: { [weak self] task in
                guard let self else {
                    return TaskDispatchResult(accepted: false, summary: "Daemon shutting down")
                }
                return await self.dispatch(task: task)
            },
            statusProvider: { [weak self] in
                guard let self else {
                    return DaemonStatusSnapshot(running: false, activeBridges: [], processedTasks: 0, uptimeSeconds: 0, residentMemoryMB: 0)
                }
                return await self.statusSnapshot()
            }
        )
        self.server = srv
        try await srv.start()

        await cronScheduler.start { [weak self] task in
            guard let self else {
                return TaskDispatchResult(accepted: false, summary: "Daemon stopped")
            }
            return await self.dispatch(task: task)
        }

        if configuration.daemon.telegramEnabled {
            let tg = TelegramBridge(secretStore: secretStore)
            self.telegramBridge = tg
            try? await tg.start { [weak self] msg in
                guard let self else { return "Daemon unavailable" }
                return await self.handleBridgeMessage(source: "telegram", msg: msg)
            }
        }
        if configuration.daemon.discordEnabled {
            let dc = DiscordBridge(secretStore: secretStore)
            self.discordBridge = dc
            try? await dc.start { [weak self] msg in
                guard let self else { return "Daemon unavailable" }
                return await self.handleBridgeMessage(source: "discord", msg: msg)
            }
        }
        if configuration.daemon.slackEnabled {
            let sl = SlackBridge(secretStore: secretStore)
            self.slackBridge = sl
            try? await sl.start { [weak self] msg in
                guard let self else { return "Daemon unavailable" }
                return await self.handleBridgeMessage(source: "slack", msg: msg)
            }
        }
        logger.info("SwiftCode daemon active (RSS: \(String(format: "%.1f", ProcessMemoryReporter.currentRSSMegabytes())) MB)")
    }

    public func stop() async {
        await cronScheduler.stop()
        await telegramBridge?.stop()
        await discordBridge?.stop()
        await slackBridge?.stop()
        await server?.stop()
        server = nil
    }

    public func boundPort() async -> Int? {
        await server?.boundPort
    }

    public func statusSnapshot() -> DaemonStatusSnapshot {
        var bridges: [String] = []
        if telegramBridge != nil { bridges.append("telegram") }
        if discordBridge != nil { bridges.append("discord") }
        if slackBridge != nil { bridges.append("slack") }
        if AppleShortcutsBridge().isAvailable() && configuration.daemon.shortcutsEnabled {
            bridges.append("apple-shortcuts")
        }
        return DaemonStatusSnapshot(
            running: server != nil,
            activeBridges: bridges,
            processedTasks: processedTasks,
            uptimeSeconds: Int(Date().timeIntervalSince(startedAt)),
            residentMemoryMB: ProcessMemoryReporter.currentRSSMegabytes()
        )
    }

    public func dispatch(task: InboundAgentTask) async -> TaskDispatchResult {
        processedTasks += 1
        let root = task.workspacePath.map { URL(fileURLWithPath: $0) } ?? workspaceRoot
        var cfg = configuration
        cfg.defaultMode = task.mode
        let orchestrator = OrchestratorActor(
            workspaceRoot: root,
            configuration: cfg,
            approvalGate: ApprovalGate(policy: cfg.permissions) { _ in .allowOnce }
        )
        do {
            let reply = try await orchestrator.runTurn(userPrompt: task.prompt, maxIterations: 6)
            return TaskDispatchResult(accepted: true, summary: reply, sessionID: orchestrator.sessionID.uuidString)
        } catch {
            return TaskDispatchResult(accepted: false, summary: error.localizedDescription, sessionID: orchestrator.sessionID.uuidString)
        }
    }

    private func handleBridgeMessage(source: String, msg: BridgeMessage) async -> String {
        let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/status" {
            let snap = statusSnapshot()
            return "SwiftCode running • tasks=\(snap.processedTasks) • RSS=\(String(format: "%.1f", snap.residentMemoryMB))MB"
        }
        let mode: AgentMode = trimmed.hasPrefix("/build ") ? .build : .plan
        let prompt = trimmed.hasPrefix("/build ") ? String(trimmed.dropFirst(7)) : trimmed
        let result = await dispatch(task: InboundAgentTask(source: "\(source):\(msg.senderName)", prompt: prompt, mode: mode))
        return result.summary.isEmpty ? "Completed (\(result.accepted ? "ok" : "error"))" : result.summary
    }
}
