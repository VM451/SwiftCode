# Progress Trackers

## 2026-11-16 - Initial Project Kickoff & Context Setup

- Done: Initialized git repository, verified Xcode 27.2 / Swift 6.4.2 / macOS 27.2 SDK frameworks (`Virtualization`, `Security`, `SQLite3`, `SwiftUI`, `AppKit`), verified local SPM dependency cache (`swift-argument-parser 1.8.2`, `swift-syntax 604.0.0`, `swift-nio 2.105.0`, `swift-log 1.17.0`, `swift-metrics 2.13.0`, `swift-crypto 5.1.1`), created `Package.swift`, `AGENTS.md`, and 9 flat `context/` files.
- Decisions: `Package.swift` targets macOS 15+ and Linux for broad CLI/server portability while `SwiftCodeApp` Xcode project targets macOS 27.0+ for Liquid Glass and modern AppKit segmented controls.
- Risks: `Virtualization.framework` guest execution requires user-supplied or downloaded Linux kernel/initrd assets; provide full validation, configuration, and graceful diagnostics via `swiftcode vm`.
- Next: Implement `SwiftCodeCore` subsystems (Config, Security, Models, Providers, Git, Sandbox, AST, Tools, MCP, Plugins, Agent), `SwiftCodeDaemon`, `swiftcode` CLI/TUI, tests, and `SwiftCodeApp`.

## 2026-11-16 - Full Phase 1-4 Implementation & Verification

- Done: Implemented `SwiftCodeCore` (models, config, Keychain + AES-GCM secret vaults, SecretRedactor, ProjectRulesLoader, SQLite FTS5 `MemoryStore`, `ContextCompactor`, `OrchestratorActor` + `SubAgentActor` + `SwarmCoordinator`, Anthropic/OpenAI/Gemini/Ollama/MLX providers, `ShadowGitManager` + `UnifiedDiffEngine`, `SandboxExecutor` + `WorkspaceLock` + `MicroVMRunner`, `SwiftASTInspector` + `LSPClient`, `MCPStdioClient`/`MCPHTTPClient`/`MCPStdioServer`, `SkillRegistry`), `SwiftCodeDaemon` (`DaemonServer` SwiftNIO + HMAC webhooks, `CronScheduler`, Telegram/Discord/Slack/Shortcuts bridges, `ServiceInstaller`), `swiftcode` CLI/raw-`termios` ANSI TUI, and `SwiftCodeApp` (macOS 27.0+ MVVM Liquid Glass companion app with SwiftData & Swift Charts).
- Verified: `swift test` passed 26/26 tests across 8 suites (0.640s); release `swiftcode` binary built (28.17 MB, 11.96 ms median `--version`, 12.17 MB RSS in `doctor`); `SwiftCodeAppTests` passed 3/3 tests; `SwiftCodeApp` built (`sdk 27.2`, `minos 27.0`) and verified silently in background via `cua-driver` (`self_activation_suppressed: true`).
- Next: Ready for release packaging or extending external MCP server integrations.

## 2026-11-16 - Project Rename: SwiftHarness -> SwiftCode

- Done: Renamed package, targets (`SwiftCodeCore`, `SwiftCodeDaemon`, `swiftcode`, `SwiftCodeCoreTests`, `SwiftCodeApp`, `SwiftCodeAppTests`), bundle/service IDs (`dev.swiftcode.*`), config/checkpoint paths (`.swiftcode/`, `~/.swiftcode/`), primary types (`SwiftCodeConfiguration`, `SwiftCodeTool`, `SwiftCodeSkill`, `SwiftCodeCLI`, `SwiftCodeAppContainer`), regenerated `SwiftCodeApp.xcodeproj`, and updated docs/context.
- Next: Verify `swift test`, release `swiftcode` binary, and `SwiftCodeApp` `ess-xcode-run` + `SwiftCodeAppTests`.
