import Foundation

/// Parsed Server-Sent Event frame (`event:` + `data:`).
public struct SSEEvent: Sendable, Equatable {
    public let event: String?
    public let data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// Pure-Swift incremental Server-Sent Events parser with zero dependencies.
public struct SSEParser: Sendable {
    private var currentEvent: String?
    private var dataLines: [String] = []

    public init() {}

    /// Consumes a single decoded line (without trailing newline) and returns a completed event if blank line reached.
    public mutating func feed(line rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") {
            return nil
        }
        if line.hasPrefix("event:") {
            let value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            currentEvent = value
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") {
                value.removeFirst()
            }
            dataLines.append(value)
        }
        return nil
    }

    /// Flushes any buffered event at EOF.
    public mutating func flush() -> SSEEvent? {
        guard !dataLines.isEmpty else {
            currentEvent = nil
            return nil
        }
        let payload = dataLines.joined(separator: "\n")
        let event = SSEEvent(event: currentEvent, data: payload)
        currentEvent = nil
        dataLines.removeAll(keepingCapacity: true)
        return event
    }
}
