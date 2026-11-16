import Foundation

/// Renders `FileDiff` and raw unified diff text with ANSI colors and line numbers for TUI output.
public enum ANSIDiffRenderer {
    private static let reset = "\u{001B}[0m"
    private static let boldCyan = "\u{001B}[1;36m"
    private static let dim = "\u{001B}[2m"
    private static let green = "\u{001B}[32m"
    private static let red = "\u{001B}[31m"
    private static let yellow = "\u{001B}[33m"

    public static func render(_ diff: FileDiff) -> String {
        guard !diff.hunks.isEmpty else {
            return "\(dim)No line differences in \(diff.path)\(reset)"
        }
        var lines: [String] = [
            "\(boldCyan)diff \(diff.path)\(reset) \(green)+\(diff.additions)\(reset) \(red)-\(diff.deletions)\(reset)"
        ]
        for hunk in diff.hunks {
            lines.append("\(yellow)@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@\(reset)")
            for line in hunk.lines {
                let oldStr = line.oldLineNumber.map { String(format: "%4d", $0) } ?? "    "
                let newStr = line.newLineNumber.map { String(format: "%4d", $0) } ?? "    "
                switch line.kind {
                case .context:
                    lines.append("\(dim)\(oldStr) \(newStr)\(reset)   \(line.text)")
                case .addition:
                    lines.append("\(green)\(oldStr) \(newStr) + \(line.text)\(reset)")
                case .deletion:
                    lines.append("\(red)\(oldStr) \(newStr) - \(line.text)\(reset)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
