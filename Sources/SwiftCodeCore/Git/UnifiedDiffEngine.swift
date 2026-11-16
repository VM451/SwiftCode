import Foundation

/// Pure-Swift LCS line diff generator producing unified diffs and structured hunks (FR-2.3).
public enum UnifiedDiffEngine {
    public static func diff(
        path: String,
        original: String,
        updated: String,
        contextLines: Int = 3
    ) -> FileDiff {
        let oldLines = splitLines(original)
        let newLines = splitLines(updated)
        let ops = computeLineOps(oldLines: oldLines, newLines: newLines)
        let hunks = buildHunks(from: ops, contextLines: contextLines)

        var adds = 0
        var dels = 0
        for op in ops {
            switch op.kind {
            case .addition: adds += 1
            case .deletion: dels += 1
            case .context: break
            }
        }

        let header = ["--- a/\(path)", "+++ b/\(path)"]
        var body: [String] = []
        for hunk in hunks {
            body.append("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
            for line in hunk.lines {
                let prefix = switch line.kind {
                case .context: " "
                case .addition: "+"
                case .deletion: "-"
                }
                body.append(prefix + line.text)
            }
        }

        let unified = hunks.isEmpty ? "" : (header + body).joined(separator: "\n")
        return FileDiff(path: path, hunks: hunks, additions: adds, deletions: dels, unifiedText: unified)
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func computeLineOps(oldLines: [String], newLines: [String]) -> [DiffLine] {
        let m = oldLines.count
        let n = newLines.count
        if m == 0 && n == 0 { return [] }
        // Guard against pathological O(m*n) memory on giant files by falling back to prefix/suffix trim.
        if m * n > 2_000_000 {
            return fallbackDiff(oldLines: oldLines, newLines: newLines)
        }

        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                if oldLines[i] == newLines[j] {
                    lcs[i][j] = lcs[i + 1][j + 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var result: [DiffLine] = []
        var i = 0
        var j = 0
        while i < m && j < n {
            if oldLines[i] == newLines[j] {
                result.append(DiffLine(kind: .context, oldLineNumber: i + 1, newLineNumber: j + 1, text: oldLines[i]))
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                result.append(DiffLine(kind: .deletion, oldLineNumber: i + 1, newLineNumber: nil, text: oldLines[i]))
                i += 1
            } else {
                result.append(DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: j + 1, text: newLines[j]))
                j += 1
            }
        }
        while i < m {
            result.append(DiffLine(kind: .deletion, oldLineNumber: i + 1, newLineNumber: nil, text: oldLines[i]))
            i += 1
        }
        while j < n {
            result.append(DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: j + 1, text: newLines[j]))
            j += 1
        }
        return result
    }

    private static func fallbackDiff(oldLines: [String], newLines: [String]) -> [DiffLine] {
        var prefix = 0
        while prefix < oldLines.count && prefix < newLines.count && oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var oldEnd = oldLines.count
        var newEnd = newLines.count
        while oldEnd > prefix && newEnd > prefix && oldLines[oldEnd - 1] == newLines[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        var ops: [DiffLine] = []
        for idx in 0..<prefix {
            ops.append(DiffLine(kind: .context, oldLineNumber: idx + 1, newLineNumber: idx + 1, text: oldLines[idx]))
        }
        for idx in prefix..<oldEnd {
            ops.append(DiffLine(kind: .deletion, oldLineNumber: idx + 1, newLineNumber: nil, text: oldLines[idx]))
        }
        for idx in prefix..<newEnd {
            ops.append(DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: idx + 1, text: newLines[idx]))
        }
        for offset in 0..<(oldLines.count - oldEnd) {
            ops.append(DiffLine(
                kind: .context,
                oldLineNumber: oldEnd + offset + 1,
                newLineNumber: newEnd + offset + 1,
                text: oldLines[oldEnd + offset]
            ))
        }
        return ops
    }

    private static func buildHunks(from ops: [DiffLine], contextLines: Int) -> [DiffHunk] {
        let changeIndices = ops.indices.filter { ops[$0].kind != .context }
        guard !changeIndices.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        for idx in changeIndices {
            let low = max(0, idx - contextLines)
            let high = min(ops.count - 1, idx + contextLines)
            if let last = ranges.last, low <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, high)
            } else {
                ranges.append(low...high)
            }
        }

        return ranges.map { range in
            let slice = Array(ops[range])
            let oldStart = slice.compactMap(\.oldLineNumber).first ?? 1
            let newStart = slice.compactMap(\.newLineNumber).first ?? 1
            let oldCount = slice.filter { $0.kind != .addition }.count
            let newCount = slice.filter { $0.kind != .deletion }.count
            return DiffHunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: slice)
        }
    }
}
