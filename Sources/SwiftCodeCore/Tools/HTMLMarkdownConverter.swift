import Foundation

/// Pure-Swift HTML-to-Markdown converter requiring zero browser engine or WebView (FR-4.1).
public enum HTMLMarkdownConverter {
    public static func convert(_ html: String) -> String {
        var text = html
        // Drop script/style/head blocks cleanly
        let stripPatterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<noscript[^>]*>.*?</noscript>",
        ]
        for pattern in stripPatterns {
            text = replacing(text, pattern: pattern, with: "")
        }

        // Convert headings, links, list items, and line breaks
        text = replacing(text, pattern: "(?is)<h([1-6])[^>]*>(.*?)</h\\1>", with: "\n## $2\n")
        text = replacing(text, pattern: "(?is)<pre[^>]*>(.*?)</pre>", with: "\n```\n$1\n```\n")
        text = replacing(text, pattern: "(?is)<code[^>]*>(.*?)</code>", with: "`$1`")
        text = replacing(text, pattern: "(?is)<li[^>]*>(.*?)</li>", with: "- $1\n")
        text = replacing(text, pattern: "(?is)<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", with: "[$2]($1)")
        text = replacing(text, pattern: "(?is)<(?:br|/p|/div|/tr|/section)[^>]*>", with: "\n")
        text = replacing(text, pattern: "(?is)<[^>]+>", with: "")

        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1 { collapsed.append("") }
            } else {
                blankRun = 0
                collapsed.append(line)
            }
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }
}
