import Foundation

/// Inspector panel tab modes in `DiffInspectorView`.
enum InspectorTab: String, CaseIterable, Hashable {
    case diff = "Diff"
    case telemetry = "Telemetry"
    case mcp = "MCP & VM"
}

/// Token chart bar item rendered by `Swift Charts`.
struct TokenMetricPoint: Identifiable, Sendable, Equatable {
    var id: String { label }
    let label: String
    let count: Int
}
