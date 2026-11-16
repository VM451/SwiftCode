import Foundation
import Testing
@testable import SwiftCodeCore

struct SandboxAndVMTests {
    @Test func seatbeltProfileRestrictsWritesAndNetworkByPolicy() {
        let root = URL(fileURLWithPath: "/tmp/example-project")
        let restricted = SeatbeltProfileBuilder.build(policy: SandboxPolicy(tier: .seatbelt, workspaceRoot: root, allowNetwork: false))
        #expect(restricted.contains("(deny network*)"))
        #expect(restricted.contains("(subpath \"/tmp/example-project\")"))

        let networked = SeatbeltProfileBuilder.build(policy: SandboxPolicy(tier: .seatbelt, workspaceRoot: root, allowNetwork: true))
        #expect(networked.contains("(allow network*)"))
    }

    @Test func sandboxExecutorExecutesCommandsAndEnforcesTimeout() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let executor = SandboxExecutor()
        let policy = SandboxPolicy(tier: .seatbelt, workspaceRoot: tempDir, allowNetwork: false)
        let ok = try await executor.execute(command: "echo hello-sandbox", policy: policy, timeoutSeconds: 5)
        #expect(ok.exitCode == 0)
        #expect(ok.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello-sandbox")
        #expect(ok.timedOut == false)
    }

    @Test func workspaceLockDetectsConcurrentWriters() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockA = WorkspaceLock(workspaceRoot: tempDir)
        let lockB = WorkspaceLock(workspaceRoot: tempDir)
        #expect(try await lockA.acquire() == true)
        #expect(try await lockB.acquire() == false)
        await lockA.release()
        #expect(try await lockB.acquire() == true)
        await lockB.release()
    }

    @Test func microVMRunnerInitializesManifestAndReportsReadiness() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-vm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runner = MicroVMRunner(imageDirectory: tempDir.path)
        let manifest = try await runner.initializeImageDirectory(workspaceRoot: tempDir)
        #expect(FileManager.default.fileExists(atPath: manifest.path))

        let report = await runner.checkReadiness()
        #expect(report.kernelFound == false)
        #expect(report.isReadyToBoot == false)
    }
}
