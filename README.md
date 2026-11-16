# SwiftCode

Ultra-fast, single-binary, **100% pure Swift 6** AI agent harness synthesizing the best capabilities of OpenClaw, OpenCode, Codex CLI, Cline, and OpenHands — with zero Node.js, Python, Rust, HTML, CSS, JavaScript, or WebViews.

## Highlights

- **Modal Agent Engine (`OrchestratorActor`)**: Strict `Plan` (read-only) vs. `Build` (mutating + self-healing `swift build`/`swift test` verification loop) with immutable `AgentEvent` streaming.
- **Model-Agnostic Routing (`LLMProvider`)**: Built-in **Apple Foundation Models** defaulting to on-device `Apple Foundation (Local)` (`SystemLanguageModel.default`, unlimited, ~4K context window) with selectable `Apple Private Cloud Compute` (~32K context window + iCloud+-dependent quota limit notifications with reset-day guidance & `LimitIncreaseSuggestion`), plus `URLSession.bytes` SSE streaming for Anthropic, OpenAI / OpenRouter / Groq / vLLM, Google Gemini, Ollama, and Apple Silicon `mlx-local` with exponential backoff and automatic fallback.
- **Human-in-the-Loop & Shadow-Git (`ApprovalGate`, `ShadowGitManager`)**: Granular permission policies, unified diff previews, and isolated `.swiftcode/shadow.git` snapshots for instant `/undo` and `/rollback` without touching `.git`.
- **OS Sandboxing & Ephemeral Micro-VMs (`SandboxExecutor`, `MicroVMRunner`)**: macOS `sandbox-exec` Seatbelt profiles / Linux `unshare`, POSIX `killpg` zombie prevention, POSIX `flock` workspace locks, and Apple `Virtualization.framework` Linux micro-VMs via VirtioFS & vsock.
- **AST, SourceKit-LSP & Native MCP**: `apple/swift-syntax` AST outline & symbol search, JSON-RPC SourceKit-LSP client, pure-Swift MCP stdio/HTTP client & `--mcp-server` mode, and `SwiftCodeSkill` native Swift / `.dylib` plugins.
- **Always-On Daemon & Chat Bridges (`SwiftCodeDaemon`)**: Low-RAM SwiftNIO Unix socket (`~/.swiftcode/daemon.sock`) & HMAC-SHA256 webhook HTTP server, `CronScheduler`, `launchd`/`systemd` installer, and native Telegram / Discord / Slack / Apple Shortcuts bridges.
- **Zero Web Tech & CLI-First**: Single pure-Swift `swiftcode` CLI & raw `termios` ANSI TUI with macOS Notification Center alerts for Apple Private Cloud Compute quota limits (no bloated GUI wrapper).

## Quick Start

```bash
# Build CLI + Core + Daemon
swift build -c release

# Run test suite
swift test

# Inspect cold-start / toolchain readiness
.build/release/swiftcode doctor

# Initialize ~/.swiftcode/config.json
.build/release/swiftcode config init

# Store API key securely in macOS Keychain / AES-GCM vault
.build/release/swiftcode key set ANTHROPIC_API_KEY sk-ant-...

# Start interactive ANSI TUI
.build/release/swiftcode
```

## CLI Commands

| Command | Purpose |
|---|---|
| `swiftcode` | Interactive raw-`termios` ANSI TUI (`/plan`, `/build`, `/model [local\|pcc\|icloud]`, `/undo`, `@file:`, `@symbol:`) |
| `swiftcode model [local\|pcc] [--icloud]` | Inspect or set the default Apple Foundation Model (`local` ~4K default vs `pcc` ~32K + iCloud+ quota check) |
| `swiftcode run "<prompt>"` | Headless execution (`--mode plan\|build`, `--model local\|pcc\|...`, `--sandbox seatbelt\|vm\|none`, `--yes`, `--json`) |
| `swiftcode resume [id]` | List or export SQLite + FTS5 persisted sessions |
| `swiftcode undo [--steps N]` | Rollback workspace to an earlier Shadow-Git checkpoint |
| `swiftcode checkpoint [list\|capture\|diff\|rollback]` | Manage `.swiftcode/shadow.git` snapshots |
| `swiftcode daemon [start\|status\|install]` | Run or install `launchd` / `systemd` background daemon |
| `swiftcode vm [status\|init\|list\|clean]` | Manage Apple `Virtualization.framework` micro-VM images |
| `swiftcode mcp [serve\|list]` | Start pure-Swift MCP stdio server or list configured servers |
| `swiftcode ast <path>` | Print `SwiftSyntax` AST symbol outline |
| `swiftcode key [set\|get\|delete\|list]` | Manage credentials in Keychain / AES-256-GCM vault |
| `swiftcode doctor` | Verify Apple Foundation Models (Local & PCC), Keychain, Seatbelt, Virtualization, MLX, and RSS memory |
