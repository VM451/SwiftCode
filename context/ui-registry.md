# UI Registry (CLI / ANSI TUI)

## TerminalRenderer
- Where: `Sources/swiftcode/TUI/TerminalRenderer.swift`
- Role: Renders mode header (`PLAN`/`BUILD`), highlighted streaming output, inline diffs, interactive HITL `[y/a/p/n/e]` approval prompts, Private Cloud Compute quota alerts, and accurate context-budget footer bar.

## InteractiveTUILoop
- Where: `Sources/swiftcode/TUI/InteractiveTUILoop.swift`
- Role: POSIX input loop handling `/` slash commands (`/plan`, `/build`, `/model [local|pcc|icloud]`, `/undo`, `/checkpoints`, `/diff`, `/export`, `/status`, `/help`, `/quit`) and `@` workspace mentions.

## PCCDesktopNotifier
- Where: `Sources/swiftcode/PCCDesktopNotifier.swift`
- Role: Sends native macOS Notification Center alerts from the pure-Swift CLI when Apple Private Cloud Compute nears or reaches its quota limit, and opens Apple iCloud+ / quota options on request.
