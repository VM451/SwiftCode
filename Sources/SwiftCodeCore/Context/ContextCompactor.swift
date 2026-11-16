import Foundation

/// Monitors context budget and summarizes older turns at threshold utilization (FR-3.2).
public actor ContextCompactor {
    public struct CompactionOutcome: Sendable, Equatable {
        public let compactedMessages: [ConversationMessage]
        public let beforeTokens: Int
        public let afterTokens: Int
        public let didCompact: Bool
    }

    private let maxTokens: Int
    private let thresholdRatio: Double
    private let keepRecentTurns: Int

    public init(maxTokens: Int = 200_000, thresholdRatio: Double = 0.80, keepRecentTurns: Int = 6) {
        self.maxTokens = max(100, maxTokens)
        self.thresholdRatio = min(0.98, max(0.20, thresholdRatio))
        self.keepRecentTurns = max(2, keepRecentTurns)
    }

    /// Estimates total tokens across system prompt + messages (`~4 chars/token` conservative heuristic).
    public func estimateTokens(systemPrompt: String, messages: [ConversationMessage]) -> Int {
        let totalChars = systemPrompt.count + messages.reduce(0) { sum, msg in
            sum + msg.content.count + (msg.reasoning?.count ?? 0) + msg.toolCalls.reduce(0) { $0 + $1.argumentsJSON.count } + 32
        }
        return max(1, totalChars / 4)
    }

    /// Compacts non-pinned older messages into a dense `<compacted_history>` block when utilization >= threshold.
    public func compactIfNeeded(
        systemPrompt: String,
        messages: [ConversationMessage],
        utilityProvider: (any LLMProvider)? = nil,
        utilityModel: String? = nil
    ) async -> CompactionOutcome {
        let before = estimateTokens(systemPrompt: systemPrompt, messages: messages)
        let threshold = Int(Double(maxTokens) * thresholdRatio)
        guard before >= threshold, messages.count > keepRecentTurns else {
            return CompactionOutcome(compactedMessages: messages, beforeTokens: before, afterTokens: before, didCompact: false)
        }

        let splitIndex = max(0, messages.count - keepRecentTurns)
        let older = Array(messages[..<splitIndex])
        let pinned = older.filter(\.isPinned)
        let compressible = older.filter { !$0.isPinned }
        let recent = Array(messages[splitIndex...])

        guard !compressible.isEmpty else {
            return CompactionOutcome(compactedMessages: messages, beforeTokens: before, afterTokens: before, didCompact: false)
        }

        let summaryText = await summarize(compressible, provider: utilityProvider, model: utilityModel)
        let summaryMessage = ConversationMessage(
            role: .system,
            content: "<compacted_history>\n\(summaryText)\n</compacted_history>",
            isPinned: true
        )
        let result = pinned + [summaryMessage] + recent
        let after = estimateTokens(systemPrompt: systemPrompt, messages: result)
        return CompactionOutcome(compactedMessages: result, beforeTokens: before, afterTokens: after, didCompact: true)
    }

    private func summarize(
        _ messages: [ConversationMessage],
        provider: (any LLMProvider)?,
        model: String?
    ) async -> String {
        let transcript = messages.map { msg in
            let header = "[\(msg.role.rawValue)]"
            return "\(header) \(msg.content.prefix(600))"
        }.joined(separator: "\n")

        if let provider, let model {
            let req = LLMRequest(
                model: model,
                systemPrompt: "Summarize the technical facts, edited files, decisions, and pending errors concisely.",
                messages: [ConversationMessage(role: .user, content: transcript)],
                maxTokens: 1024,
                temperature: 0.1
            )
            var collected = ""
            do {
                for try await chunk in provider.streamCompletion(request: req) {
                    if case .textDelta(let delta) = chunk { collected += delta }
                }
                if !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return collected
                }
            } catch {
                // Fall back to deterministic local extraction on network/key absence
            }
        }

        let highlights = messages.compactMap { msg -> String? in
            let body = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return "- (\(msg.role.rawValue)): \(body.prefix(240))"
        }
        return highlights.prefix(20).joined(separator: "\n")
    }
}
