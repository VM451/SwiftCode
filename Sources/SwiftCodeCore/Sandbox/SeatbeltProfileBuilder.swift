import Foundation

/// Builds macOS Seatbelt (`.sb`) sandbox-exec profiles restricting writes and network egress (FR-6.1).
public enum SeatbeltProfileBuilder {
    public static func build(policy: SandboxPolicy) -> String {
        let workspace = escapePath(policy.workspaceRoot.standardizedFileURL.path)
        let home = escapePath(FileManager.default.homeDirectoryForCurrentUser.path)
        let extraReads = policy.additionalReadPaths
            .map { "(subpath \"\(escapePath($0))\")" }
            .joined(separator: "\n        ")

        let networkRule = policy.allowNetwork
            ? "(allow network*)"
            : "(deny network*)"

        return """
        (version 1)
        (deny default)
        (import "system.sb")

        (allow process*)
        (allow sysctl-read)
        (allow mach-lookup)
        (allow ipc-posix-shm)
        \(networkRule)

        ; Read system toolchains, SwiftPM caches, and developer directories
        (allow file-read*
            (subpath "/usr")
            (subpath "/bin")
            (subpath "/sbin")
            (subpath "/System")
            (subpath "/Library")
            (subpath "/Applications/Xcode.app")
            (subpath "/private/var/db")
            (subpath "/private/etc")
            (subpath "/dev")
            (subpath "\(home)/.swiftpm")
            (subpath "\(home)/Library/Caches/org.swift.swiftpm")
            (subpath "\(home)/Library/Developer")
            (subpath "\(workspace)")
            \(extraReads)
        )

        ; Allow writes strictly inside workspace and temporary scratch dirs
        (allow file-write*
            (subpath "\(workspace)")
            (subpath "/tmp")
            (subpath "/private/tmp")
            (subpath "/private/var/folders")
            (subpath "/dev/null")
        )
        """
    }

    private static func escapePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
