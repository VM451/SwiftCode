import Foundation
import SwiftCodeCore

/// Delivers native macOS Notification Center alerts from the pure-Swift CLI when Apple Private Cloud Compute nears or hits quota.
enum PCCDesktopNotifier {
    static func notifyIfNeeded(_ notice: PCCQuotaNotice) {
        guard notice.state.isLimitReached || notice.state.isApproachingLimit else { return }
        #if os(macOS)
        let env = ProcessInfo.processInfo.environment
        guard env["SWIFTCODE_DISABLE_DESKTOP_NOTIFICATIONS"] == nil,
              env["XCTestConfigurationFilePath"] == nil,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript") else {
            return
        }

        let title = notice.state.isLimitReached
            ? "Apple Private Cloud Compute Limit Reached"
            : "Apple Private Cloud Compute Quota Low"
        let subtitle: String = if let days = notice.state.daysUntilReset(), days > 0 {
            "Wait \(days) \(days == 1 ? "day" : "days") · iCloud+ plan applies"
        } else {
            "Quota depends on Apple iCloud+ · Local unlimited"
        }
        let body = notice.message

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "on run argv",
                "-e", "display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)",
                "-e", "end run",
                "--",
                body,
                title,
                subtitle,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        #endif
    }

    @MainActor
    static func openICloudQuotaOptions(using inspector: any AppleFoundationModelInspector = LiveAppleFoundationModelInspector()) {
        if inspector.presentLimitIncreaseSuggestionIfAvailable() {
            return
        }
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        #endif
    }
}
