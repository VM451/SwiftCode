import Foundation

/// Generates and installs `launchd` (macOS) or `systemd` (Linux) user service descriptors (FR-8.1).
public enum ServiceInstaller {
    public static func launchdPlist(executablePath: String, workingDirectory: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>dev.swiftcode.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>daemon</string>
                <string>start</string>
            </array>
            <key>WorkingDirectory</key>
            <string>\(workingDirectory)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/swiftcode-daemon.out.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/swiftcode-daemon.err.log</string>
        </dict>
        </plist>
        """
    }

    public static func systemdUnit(executablePath: String, workingDirectory: String) -> String {
        """
        [Unit]
        Description=SwiftCode Always-On Agent Daemon
        After=network-online.target

        [Service]
        ExecStart=\(executablePath) daemon start
        WorkingDirectory=\(workingDirectory)
        Restart=always
        RestartSec=3

        [Install]
        WantedBy=default.target
        """
    }

    public static func install(
        executablePath: String,
        workingDirectory: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        #if os(macOS)
        let dir = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("dev.swiftcode.daemon.plist")
        try launchdPlist(executablePath: executablePath, workingDirectory: workingDirectory)
            .write(to: target, atomically: true, encoding: .utf8)
        return target
        #else
        let dir = homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("systemd", isDirectory: true)
            .appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("swiftcode.service")
        try systemdUnit(executablePath: executablePath, workingDirectory: workingDirectory)
            .write(to: target, atomically: true, encoding: .utf8)
        return target
        #endif
    }
}
