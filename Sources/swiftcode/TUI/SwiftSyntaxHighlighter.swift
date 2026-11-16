import Foundation

/// Pure-Swift ANSI syntax highlighter for streamed Swift/code snippets in the terminal (TUI §5.1).
public enum SwiftSyntaxHighlighter {
    private static let reset = "\u{001B}[0m"
    private static let magenta = "\u{001B}[1;35m"
    private static let cyan = "\u{001B}[36m"
    private static let green = "\u{001B}[32m"
    private static let dim = "\u{001B}[2m"

    private static let keywords: Set<String> = [
        "import", "struct", "class", "actor", "enum", "protocol", "extension",
        "func", "init", "deinit", "let", "var", "public", "private", "internal",
        "fileprivate", "open", "async", "await", "throws", "try", "catch",
        "return", "guard", "if", "else", "switch", "case", "default", "for",
        "while", "in", "some", "any", "Sendable", "nonisolated", "isolated",
    ]

    public static func highlightLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") {
            return "\(dim)\(line)\(reset)"
        }
        var output = ""
        var currentWord = ""
        var inString = false

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            if keywords.contains(currentWord) {
                output += "\(magenta)\(currentWord)\(reset)"
            } else if let first = currentWord.first, first.isUppercase {
                output += "\(cyan)\(currentWord)\(reset)"
            } else {
                output += currentWord
            }
            currentWord = ""
        }

        for ch in line {
            if ch == "\"" {
                flushWord()
                if inString {
                    output += "\"\(reset)"
                    inString = false
                } else {
                    output += "\(green)\""
                    inString = true
                }
            } else if inString {
                output.append(ch)
            } else if ch.isLetter || ch.isNumber || ch == "_" {
                currentWord.append(ch)
            } else {
                flushWord()
                output.append(ch)
            }
        }
        flushWord()
        if inString { output += reset }
        return output
    }
}
