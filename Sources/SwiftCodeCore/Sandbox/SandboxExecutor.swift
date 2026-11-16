import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Result of a sandboxed shell execution.
public struct SandboxCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public let durationMS: Int

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool, durationMS: Int) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.durationMS = durationMS
    }
}

/// Executes shell commands inside OS sandboxes with process-group zombie cleanup (FR-6.1, EC-1).
public actor SandboxExecutor {
    public init() {}

    public func execute(
        command: String,
        policy: SandboxPolicy,
        timeoutSeconds: TimeInterval = 60,
        environmentOverrides: [String: String] = [:]
    ) async throws -> SandboxCommandResult {
        let started = ContinuousClock.now
        let process = Process()
        process.currentDirectoryURL = policy.workspaceRoot
        process.environment = sanitizedEnvironment(overrides: environmentOverrides)

        var tempProfileURL: URL?
        defer {
            if let tempProfileURL { try? FileManager.default.removeItem(at: tempProfileURL) }
        }

        #if os(macOS)
        if policy.tier == .seatbelt && FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") {
            let profile = SeatbeltProfileBuilder.build(policy: policy)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sh-seatbelt-\(UUID().uuidString).sb")
            try profile.write(to: url, atomically: true, encoding: .utf8)
            tempProfileURL = url
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-f", url.path, "/bin/sh", "-c", command]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
        }
        #else
        if policy.tier == .seatbelt && FileManager.default.isExecutableFile(atPath: "/usr/bin/unshare") && !policy.allowNetwork {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unshare")
            process.arguments = ["--net", "--user", "--map-root-user", "/bin/sh", "-c", command]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
        }
        #endif

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let pid = process.processIdentifier
        _ = setpgid(pid, pid)

        let exitState = try await waitForExitOrTimeout(process: process, pid: pid, timeoutSeconds: timeoutSeconds)
        let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)

        return SandboxCommandResult(
            exitCode: exitState.exitCode,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: exitState.timedOut,
            durationMS: max(0, ms)
        )
    }

    private func waitForExitOrTimeout(
        process: Process,
        pid: pid_t,
        timeoutSeconds: TimeInterval
    ) async throws -> (exitCode: Int32, timedOut: Bool) {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while process.isRunning {
            if Task.isCancelled || ContinuousClock.now >= deadline {
                terminateProcessGroup(pid: pid)
                return (process.terminationStatus, !Task.isCancelled)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        return (process.terminationStatus, false)
    }

    /// EC-1: Sends SIGINT to process group, waits up to 2 seconds, then escalates to SIGKILL.
    private func terminateProcessGroup(pid: pid_t) {
        let pgid = getpgid(pid)
        let target = pgid > 0 ? -pgid : -pid
        _ = kill(target, SIGINT)
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return }
            usleep(50_000)
        }
        _ = kill(target, SIGKILL)
    }

    private func sanitizedEnvironment(overrides: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        let safeKeys = ["PATH", "HOME", "USER", "TMPDIR", "LANG", "LC_ALL", "DEVELOPER_DIR", "SDKROOT"]
        for key in safeKeys {
            if let value = ProcessInfo.processInfo.environment[key] {
                env[key] = value
            }
        }
        for (k, v) in overrides {
            env[k] = v
        }
        return env
    }
}
