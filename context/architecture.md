# Architecture

- Components:
  - `SwiftCodeCore`: `OrchestratorActor` (`AgentEvent` stream including `.pccQuotaNotice`, Plan/Build FSM, self-healing verification), `SubAgentActor` + `SwarmCoordinator` (git worktrees), `ContextCompactor` (dynamic 4K Local / 32K PCC context-limit awareness) + `ProjectRulesLoader` + `MemoryStore` (SQLite/FTS5 + Markdown), `LLMProvider` adapters (`AppleFoundationModelProvider` for Local & Private Cloud Compute, `Anthropic`, `OpenAI`, `Gemini`, `Ollama`, `MLXLocal`), `ToolRegistry` + built-in tools (`SwiftSyntax`, `LSPClient`, `MCPClient`), `ApprovalGate`, `ShadowGitManager`, `SecretRedactor`, `SeatbeltSandbox`, `MicroVMRunner` (`Virtualization.framework`), `SkillRegistry`.
  - `SwiftCodeDaemon`: `DaemonServer` (`SwiftNIO` Unix socket + HMAC webhook HTTP), `CronScheduler`, `TelegramBridge`, `DiscordBridge`, `SlackBridge`, `AppleShortcutsBridge`.
  - `swiftcode`: `swift-argument-parser` CLI + raw `termios` ANSI TUI + `PCCDesktopNotifier` (native macOS Notification Center alerts for PCC quota limits) with `@` mentions, `/` slash commands (`/plan`, `/build`, `/model`), inline diffs.
- Data flow: User/Webhook/Chat -> `OrchestratorActor` -> `ApprovalGate` + `ShadowGitManager` -> `ToolRegistry` / `SeatbeltSandbox` / `MicroVMRunner` -> `AgentEvent` `AsyncStream` -> CLI TUI / Daemon / Chat Bridges.
- Key decisions:
  - 2026-11-16: Swift 6.2 tools-version with strict concurrency; package targets macOS 15+ & Linux as a single pure-Swift CLI-only distribution (GUI companion app removed).
