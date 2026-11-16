import Foundation

/// Helper assembling system instructions and handling verification prompt formatting for `OrchestratorActor`.
enum OrchestratorPromptBuilder {
    static func systemPrompt(mode: AgentMode, workspaceRoot: URL, rulesLoader: ProjectRulesLoader) -> String {
        let rules = rulesLoader.loadRules(workspaceRoot: workspaceRoot)
        let modeDirective = switch mode {
        case .plan:
            "You are in PLAN MODE (read-only). Inspect code cleanly and produce an actionable Markdown plan. Mutating tools are disabled."
        case .build:
            "You are in BUILD MODE. Implement changes safely using workspace tools, respect coding standards, and verify builds."
        }
        return [
            "You are SwiftCode, a 100% native Swift 6 AI coding assistant.",
            "Workspace root: \(workspaceRoot.path)",
            modeDirective,
            rules.isEmpty ? nil : rules,
        ].compactMap { $0 }.joined(separator: "\n\n")
    }

    static func buildToolCalls(order: [String], map: [String: (name: String, args: String)]) -> [ToolCall] {
        order.compactMap { id -> ToolCall? in
            guard let pair = map[id] else { return nil }
            return ToolCall(id: id, name: pair.name, argumentsJSON: pair.args.isEmpty ? "{}" : pair.args)
        }
    }
}
