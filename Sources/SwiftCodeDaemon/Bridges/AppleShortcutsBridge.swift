import Foundation

/// Native macOS Apple Shortcuts & AppleScript bridge for local automation (FR-8.2).
public struct AppleShortcutsBridge: Sendable {
    public let bridgeID = "apple-shortcuts"

    public init() {}

    public func isAvailable() -> Bool {
        #if os(macOS)
        FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts")
        #else
        false
        #endif
    }

    public func runShortcut(named name: String, input: String) -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        try? inPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #else
        return nil
        #endif
    }
}
