# Architecture

- Components:
  - `SwiftCodeCore`: `OrchestratorActor` (`AgentEvent` stream, Plan/Build FSM, self-healing verification), `SubAgentActor` + `SwarmCoordinator` (git worktrees), `ContextCompactor` + `ProjectRulesLoader` + `MemoryStore` (SQLite/FTS5 + Markdown), `LLMProvider` adapters (`Anthropic`, `OpenAI`, `Gemini`, `Ollama`, `MLXLocal`), `ToolRegistry` + built-in tools (`SwiftSyntax`, `LSPClient`, `MCPClient`), `ApprovalGate`, `ShadowGitManager`, `SecretRedactor`, `SeatbeltSandbox`, `MicroVMRunner` (`Virtualization.framework`), `SkillRegistry`.
  - `SwiftCodeDaemon`: `DaemonServer` (`SwiftNIO` Unix socket + HMAC webhook HTTP), `CronScheduler`, `TelegramBridge`, `DiscordBridge`, `SlackBridge`, `AppleShortcutsBridge`.
  - `swiftcode`: `swift-argument-parser` CLI + raw `termios` ANSI TUI with `@` mentions, `/` slash commands, inline diffs.
  - `SwiftCodeApp`: macOS 27.0+ SwiftUI/AppKit companion (`MenuBarExtra`, `NavigationSplitView`, `NSTextView` diff inspector, Swift Charts telemetry, Keychain vault).
- Data flow: User/Webhook/Chat -> `OrchestratorActor` -> `ApprovalGate` + `ShadowGitManager` -> `ToolRegistry` / `SeatbeltSandbox` / `MicroVMRunner` -> `AgentEvent` `AsyncStream` -> CLI TUI / SwiftUI / Chat Bridges.
- Key decisions:
  - 2026-11-16: Swift 6.2 tools-version with strict concurrency; Package targets macOS 15+ & Linux, companion Xcode app targets macOS 27.0+ with Liquid Glass.
