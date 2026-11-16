import Foundation
import Testing
@testable import SwiftCodeCore

struct DiffAndShadowGitTests {
    @Test func unifiedDiffEngineComputesAccurateHunksAndANSI() {
        let before = "line 1\nline 2\nline 3\n"
        let after = "line 1\nline TWO\nline 3\nline 4\n"
        let diff = UnifiedDiffEngine.diff(path: "Sample.swift", original: before, updated: after)
        #expect(diff.additions == 2)
        #expect(diff.deletions == 1)
        #expect(diff.unifiedText.contains("--- a/Sample.swift"))
        #expect(diff.unifiedText.contains("-line 2"))
        #expect(diff.unifiedText.contains("+line TWO"))

        let ansi = ANSIDiffRenderer.render(diff)
        #expect(ansi.contains("Sample.swift"))
        #expect(ansi.contains("\u{001B}["))
    }

    @Test func shadowGitCapturesSnapshotsAndRollsBackWithoutRealGit() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-shadow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("Main.swift")
        try "let version = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let shadow = ShadowGitManager(workspaceRoot: tempDir)
        let cp1 = try await shadow.captureSnapshot(label: "Initial v1")

        try "let version = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let extraURL = tempDir.appendingPathComponent("TempExtra.swift")
        try "let extra = true\n".write(to: extraURL, atomically: true, encoding: .utf8)

        let diffText = try await shadow.diff(against: cp1.commitHash)
        #expect(diffText.contains("-let version = 1"))
        #expect(diffText.contains("+let version = 2"))

        _ = try await shadow.captureSnapshot(label: "Before v3")
        try "let version = 3\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let restored = try await shadow.undo(steps: 1)
        #expect(restored != nil)

        try await shadow.rollback(to: cp1.commitHash)
        let contentAfterRollback = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contentAfterRollback == "let version = 1\n")
        #expect(FileManager.default.fileExists(atPath: extraURL.path) == false)
        // Must never create user-visible .git directory
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(".git").path) == false)
    }
}
