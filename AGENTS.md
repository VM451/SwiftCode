# AGENTS.md

Agent entry point for **SwiftCode**. Durable context lives in `context/` — read this file first, then the context files you need. Update affected `context/` files after every code change.

## Session protocol

1. Read `context/project-overview.md` and `context/progress-trackers.md` first.
2. Read `context/architecture.md` + `context/code-standard.md` before touching code; add `context/library-docs.md` for dependencies and `context/ui-*.md` for ANSI TUI conventions.
3. Build and run Swift Testing suite (`swift test`) and verify the `swiftcode` CLI binary.
4. Update affected `context/` files before finishing.

## Context map

- Product: `context/project-overview.md`
- System: `context/architecture.md`, `context/library-docs.md`
- Plan: `context/build-plan.md`, `context/progress-trackers.md`
- Standards: `context/code-standard.md`
- UI: `context/ui-rule.md`, `context/ui-registry.md`, `context/ui-token.md`

## Context maintenance (auto-update, no prompt needed)

- Product/scope change → `project-overview.md`; structure/flow change → `architecture.md`; dependency change → `library-docs.md`; phase/feature status → `build-plan.md`; convention change → `code-standard.md`; UI component/token/rule → `ui-*.md`.
- Always append a dated entry to `context/progress-trackers.md`. Never rewrite history.

## Setup commands

- Resolve SPM deps: `swift package resolve`
- Build CLI & core: `swift build`
- Release CLI build: `swift build -c release --product swiftcode`

## Testing

- Run core tests: `swift test`
- Targeted suite: `swift test --filter <SuiteName>`

## Code style

- Stack: Pure Swift 6.2+ (`-strict-concurrency=complete`), SPM, CLI-only distribution (zero GUI app target).
- Zero web tech (no HTML, CSS, JS, TS, Electron, WebViews, Node.js, Python, or Rust).
- File guardrail: `<= 300` lines (`wc -l`), healthy `<= 200`, one primary type per file (`Filename.swift`).

## Project structure

- `Sources/SwiftCodeCore/`: Platform-agnostic Swift 6 agent engine, LLM providers, tools, ShadowGit, Sandbox, AST/LSP, MCP, SkillKit.
- `Sources/SwiftCodeDaemon/`: SwiftNIO Unix socket / webhook server, CronScheduler, Telegram/Discord/Slack/Shortcuts bridges.
- `Sources/swiftcode/`: Pure Swift CLI (`swift-argument-parser`), desktop PCC quota notifier, & raw `termios` ANSI TUI.
- `Tests/SwiftCodeCoreTests/`: Swift Testing (`@Test`, `#expect`, `#require`) suite.

## Boundaries

- Never store plaintext API keys in config; use Keychain (`Security.framework`) or AES-GCM (`swift-crypto`).
- Never pollute user's `.git`; checkpoints live strictly in `.swiftcode/shadow.git`.
- Never create subfolders inside `context/` — nine flat markdown files only.
