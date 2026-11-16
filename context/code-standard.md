# Code Standard

- Style: Swift 6 strict concurrency (`Sendable`, `actor`, `@MainActor`, zero unbacked `@unchecked Sendable`, structured `withTaskGroup`).
- File limits: `<= 300` lines per Swift file (`wc -l`), healthy `<= 200`. One primary type per file (`Filename.swift`).
- Naming: Clear Apple-idiomatic Swift naming (`OrchestratorActor`, `ShadowGitManager`, `TerminalRenderer`, `AppleFoundationModelProvider`).
- Testing: Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`, struct suites, zero `XCTestCase`, in-memory fakes/temp dirs, <= 5s per suite).
- Security: Zero plaintext credentials; redact secrets via `SecretRedactor` before outbound LLM requests; `killpg` cleanup for subprocesses; `flock` workspace locks.
