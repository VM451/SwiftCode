# Project Overview

- What: SwiftCode — ultra-fast, single-binary, 100% native Swift 6 AI agent harness synthesizing OpenClaw, OpenCode, Codex CLI, Cline, and OpenHands.
- State: Active full-stack engineering build (Phases 1–4).
- Users: Native Apple/Swift engineers, terminal-first systems developers, autonomous workflow/DevOps builders.
- In scope: `SwiftCodeCore`, `SwiftCodeDaemon`, `swiftcode` CLI/TUI, `SwiftCodeApp` macOS 27+ companion app, Swift Testing suite.
- Out of scope: Web tech (HTML/CSS/JS/TS/Electron/WebViews), Python/Node/Rust toolchains, cloud telemetry.
- Goals: <15ms CLI startup, <25MB idle CLI RSS, <40MB daemon RSS, 100% Swift 6 strict concurrency, full Plan/Build + ShadowGit + Sandbox + MCP + Virtualization + Bridges + SwiftUI App.
- Glossary: Plan Mode (read-only tool subset); Build Mode (mutating tools + self-healing loop); Shadow-Git (isolated `.swiftcode/shadow.git` checkpoints); SkillKit (`SwiftCodeSkill` plugins).
