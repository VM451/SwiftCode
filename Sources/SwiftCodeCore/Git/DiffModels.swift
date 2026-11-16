import Foundation

/// Kind of line within a unified diff hunk.
public enum DiffLineKind: String, Codable, Sendable {
    case context
    case addition
    case deletion
}

/// Single line inside a unified diff hunk with 1-based line coordinates.
public struct DiffLine: Codable, Sendable, Equatable {
    public let kind: DiffLineKind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let text: String

    public init(kind: DiffLineKind, oldLineNumber: Int?, newLineNumber: Int?, text: String) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
    }
}

/// Contiguous hunk inside a `FileDiff`.
public struct DiffHunk: Codable, Sendable, Equatable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// Pure-Swift structured diff representation for terminal ANSI and SwiftUI `NSTextView` rendering.
public struct FileDiff: Codable, Sendable, Equatable {
    public let path: String
    public let hunks: [DiffHunk]
    public let additions: Int
    public let deletions: Int
    public let unifiedText: String

    public init(path: String, hunks: [DiffHunk], additions: Int, deletions: Int, unifiedText: String) {
        self.path = path
        self.hunks = hunks
        self.additions = additions
        self.deletions = deletions
        self.unifiedText = unifiedText
    }
}
