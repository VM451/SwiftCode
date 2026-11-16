import Foundation
import SwiftCodeCore

/// Pure-Swift ANSI terminal renderer for header bar, streaming markdown/code, HITL prompts, and footer (§5.1).
public actor TerminalRenderer {
    private let reset = "\u{001B}[0m"
    private let bold = "\u{001B}[1m"
    private let dim = "\u{001B}[2m"
    private let cyan = "\u{001B}[36m"
    private let amber = "\u{001B}[33m"
    private let green = "\u{001B}[32m"
    private let red = "\u{001B}[31m"
    private var insideCodeBlock = false

    public init() {}

    public func renderHeader(workspace: URL, branch: String, mode: AgentMode, model: String) {
        let width = max(60, min(120, TerminalRawMode.terminalWidth()))
        let badge = mode == .plan ? "\u{001B}[1;46;30m PLAN \(reset)" : "\u{001B}[1;43;30m BUILD \(reset)"
        let rule = String(repeating: "─", count: width)
        print("\(dim)\(rule)\(reset)")
        print("\(badge) \(bold)SwiftCode\(reset)  \(cyan)\(workspace.lastPathComponent)\(reset) (\(branch))  •  model: \(amber)\(model)\(reset)")
        print("\(dim)Slash: /plan  /build  /undo  /checkpoints  /diff  /export  /status  /help  /quit   |   Mentions: @file: @symbol: @git:diff\(reset)")
        print("\(dim)\(rule)\(reset)")
    }

    public func renderEvent(_ event: AgentEvent) {
        switch event.kind {
        case .reasoningTokenDelta(let delta):
            print("\(dim)\(delta)\(reset)", terminator: "")
            fflush(stdout)
        case .assistantTokenDelta(let delta):
            if delta.contains("```") {
                insideCodeBlock.toggle()
            }
            if insideCodeBlock {
                print(SwiftSyntaxHighlighter.highlightLine(delta), terminator: "")
            } else {
                print(delta, terminator: "")
            }
            fflush(stdout)
        case .toolCallProposed(let call, let risk):
            print("\n\(cyan)→ Proposing\(reset) \(bold)\(call.name)\(reset) [\(risk.displayName)]")
        case .toolExecutionStarted(let call):
            print("\(dim)⚙ Running \(call.name)...\(reset)")
        case .toolExecutionCompleted(_, let name, let output, let ms):
            let mark = output.isError ? "\(red)✗\(reset)" : "\(green)✓\(reset)"
            let linePreview = output.content.split(separator: "\n").first.map(String.init) ?? ""
            print("\(mark) \(bold)\(name)\(reset) \(dim)(\(ms)ms)\(reset) \(linePreview.prefix(100))")
            if let diff = output.metadata["diff"], !diff.isEmpty {
                let parsed = UnifiedDiffEngine.diff(path: name, original: "", updated: "")
                _ = parsed
                print(diff)
            }
        case .checkpointCreated(let hash, let label):
            print("\(dim)⚑ Checkpoint \(hash.prefix(8)): \(label)\(reset)")
        case .compactionTriggered(let before, let after):
            print("\(amber)♻ Context compacted: \(before) → \(after) tokens\(reset)")
        case .modeChanged(let from, let to):
            print("\(cyan)⇄ Mode switched: \(from.rawValue.uppercased()) → \(to.rawValue.uppercased())\(reset)")
        case .verificationStarted(let command):
            print("\(cyan)🧪 Verifying: \(command)\(reset)")
        case .verificationCompleted(let passed, let summary):
            let tag = passed ? "\(green)PASS\(reset)" : "\(red)FAIL\(reset)"
            print("\(tag) \(summary.prefix(300))")
        case .errorEncountered(let message):
            print("\n\(red)Error: \(message)\(reset)")
        case .turnCompleted(let usage):
            print("")
            renderFooter(usage: usage)
        default:
            break
        }
    }

    public func renderFooter(usage: TokenUsage, contextLimit: Int = 200_000, checkpoints: Int = 0) {
        let ratio = min(1.0, Double(usage.totalTokens) / Double(max(1, contextLimit)))
        let filled = Int((ratio * 10.0).rounded())
        let bar = String(repeating: "|", count: filled) + String(repeating: "-", count: max(0, 10 - filled))
        let cost = String(format: "$%.4f", usage.estimatedCostUSD)
        print("\(dim)In: \(usage.inputTokens) | Out: \(usage.outputTokens) | Cached: \(usage.cachedTokens) | \(cost) | Context [\(bar)] \(Int(ratio * 100))% | Checkpoints: \(checkpoints)\(reset)")
    }

    public func promptApproval(_ request: ApprovalRequest) -> ApprovalResolution {
        print("\n\(amber)⚠ Approval Required:\(reset) \(bold)\(request.summary)\(reset)")
        if let diff = request.diffPreview, !diff.isEmpty {
            print(diff)
        } else {
            print("\(dim)\(request.call.argumentsJSON.prefix(600))\(reset)")
        }
        print("\(bold)[y]\(reset) Allow Once  \(bold)[a]\(reset) Allow Session  \(bold)[p]\(reset) Always Allow Pattern  \(bold)[n]\(reset) Deny  \(bold)[e]\(reset) Edit Args")
        print("Choice: ", terminator: "")
        fflush(stdout)
        let key = TerminalRawMode.readSingleKey() ?? "n"
        print(key)
        switch key.lowercased() {
        case "y": return .allowOnce
        case "a": return .allowForSession
        case "p":
            print("Enter glob pattern (e.g. git diff *): ", terminator: "")
            let pat = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? request.call.name
            return .alwaysAllowPattern(pat)
        case "e":
            print("Enter replacement JSON args: ", terminator: "")
            let json = readLine() ?? request.call.argumentsJSON
            return .editArguments(json)
        default:
            print("Feedback (optional): ", terminator: "")
            let note = readLine() ?? "Denied by user"
            return .deny(note.isEmpty ? "Denied by user" : note)
        }
    }
}
