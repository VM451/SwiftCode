import Foundation

/// Core tool execution protocol (PRD §6).
public protocol SwiftCodeTool: Sendable {
    var name: String { get }
    var description: String { get }
    var riskLevel: ToolRiskLevel { get }
    var inputSchemaJSON: String { get }

    func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput
}

/// Shared JSON decoding helper for tool argument objects.
public enum ToolArgumentDecoder {
    public static func decodeObject(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ToolArgumentDecoder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Tool arguments must be a valid JSON object.",
            ])
        }
        return dict
    }

    public static func resolveSafePath(_ relativeOrAbsolute: String, workspaceRoot: URL) throws -> URL {
        let root = workspaceRoot.standardizedFileURL
        let candidate: URL = if relativeOrAbsolute.hasPrefix("/") {
            URL(fileURLWithPath: relativeOrAbsolute).standardizedFileURL
        } else {
            root.appendingPathComponent(relativeOrAbsolute).standardizedFileURL
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPrefix) else {
            throw NSError(domain: "ToolArgumentDecoder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Path '\(relativeOrAbsolute)' escapes workspace root '\(root.path)'.",
            ])
        }
        return candidate
    }
}
