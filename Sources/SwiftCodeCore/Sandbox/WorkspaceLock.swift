import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// POSIX `flock` workspace guard preventing concurrent mutating Build sessions from colliding (EC-3).
public actor WorkspaceLock {
    private let lockURL: URL
    private var fileDescriptor: Int32?

    public init(workspaceRoot: URL) {
        self.lockURL = workspaceRoot
            .appendingPathComponent(".swiftcode", isDirectory: true)
            .appendingPathComponent("workspace.lock")
    }

    /// Attempts a non-blocking exclusive lock; returns `false` if another Build session owns the workspace.
    public func acquire() throws -> Bool {
        if fileDescriptor != nil { return true }
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw NSError(domain: "WorkspaceLock", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Unable to open lock file at \(lockURL.path)",
            ])
        }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            self.fileDescriptor = fd
            let pidString = "\(ProcessInfo.processInfo.processIdentifier)\n"
            _ = ftruncate(fd, 0)
            _ = pidString.withCString { ptr in write(fd, ptr, strlen(ptr)) }
            return true
        } else {
            close(fd)
            return false
        }
    }

    public func release() {
        if let fd = fileDescriptor {
            _ = flock(fd, LOCK_UN)
            close(fd)
            self.fileDescriptor = nil
        }
    }

    deinit {
        if let fd = fileDescriptor {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
    }
}
