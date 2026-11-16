import Foundation

/// Scans outbound payloads for API keys, private keys, and high-entropy secrets (FR-5.3).
public struct SecretRedactor: Sendable {
    public struct RedactionResult: Sendable, Equatable {
        public let text: String
        public let redactedCount: Int
    }

    private let exemptPrefixes: [String]

    public init(exemptPrefixes: [String] = []) {
        self.exemptPrefixes = exemptPrefixes
    }

    /// Redacts sensitive tokens, PEM blocks, and `.env` secrets before external LLM API calls.
    public func redact(_ input: String) -> RedactionResult {
        var output = input
        var count = 0

        let patterns: [(String, String)] = [
            // PEM private keys
            ("-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----", "[REDACTED:PRIVATE_KEY]"),
            // Anthropic, OpenAI, Stripe, GitHub, Google, Slack known token prefixes
            ("\\bsk-ant-[A-Za-z0-9_\\-]{16,}\\b", "[REDACTED:ANTHROPIC_KEY]"),
            ("\\bsk-(?:proj-|live-|test-)?[A-Za-z0-9_\\-]{20,}\\b", "[REDACTED:API_KEY]"),
            ("\\bAIza[0-9A-Za-z_\\-]{24,}\\b", "[REDACTED:GOOGLE_KEY]"),
            ("\\bgh[pousr]_[A-Za-z0-9]{20,}\\b", "[REDACTED:GITHUB_TOKEN]"),
            ("\\bxox[abpr]-[A-Za-z0-9\\-]{16,}\\b", "[REDACTED:SLACK_TOKEN]"),
            ("(?i)bearer\\s+[A-Za-z0-9._\\-]{24,}", "Bearer [REDACTED:TOKEN]"),
            // .env style secret assignments
            ("(?m)^([A-Z0-9_]*(?:API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY)[A-Z0-9_]*)\\s*=\\s*['\"]?([^\\s'\"]{8,})['\"]?", "$1=[REDACTED:ENV_SECRET]"),
        ]

        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            let matches = regex.matches(in: output, range: range)
            var filteredMatches = 0
            for match in matches {
                if let swiftRange = Range(match.range, in: output) {
                    let snippet = String(output[swiftRange])
                    if exemptPrefixes.contains(where: { snippet.hasPrefix($0) }) {
                        continue
                    }
                    filteredMatches += 1
                }
            }
            if filteredMatches > 0 {
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: replacement)
                count += filteredMatches
            }
        }

        // High-entropy token pass for long base64/hex secrets attached to secret-like keys
        output = redactHighEntropyAssignments(in: output, count: &count)
        return RedactionResult(text: output, redactedCount: count)
    }

    private func redactHighEntropyAssignments(in text: String, count: inout Int) -> String {
        let pattern = "(?i)(api[_-]?key|secret|token|password)[\"']?\\s*[:=]\\s*[\"']([A-Za-z0-9+/=_\\-]{24,})[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() where match.numberOfRanges >= 3 {
            let valueRange = match.range(at: 2)
            let token = ns.substring(with: valueRange)
            if shannonEntropy(token) >= 3.6, !exemptPrefixes.contains(where: { token.hasPrefix($0) }),
               let swiftRange = Range(valueRange, in: result) {
                result.replaceSubrange(swiftRange, with: "[REDACTED:HIGH_ENTROPY]")
                count += 1
            }
        }
        return result
    }

    private func shannonEntropy(_ value: String) -> Double {
        guard !value.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for ch in value { counts[ch, default: 0] += 1 }
        let len = Double(value.count)
        return counts.values.reduce(0.0) { total, freq in
            let p = Double(freq) / len
            return total - p * log2(p)
        }
    }
}
