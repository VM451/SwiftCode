import Foundation

/// Loads, merges, and persists `SwiftCodeConfiguration` under `~/.swiftcode/config.json`.
public struct ConfigurationStore: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var baseDirectoryURL: URL {
        homeDirectory.appendingPathComponent(".swiftcode", isDirectory: true)
    }

    public var configFileURL: URL {
        baseDirectoryURL.appendingPathComponent("config.json")
    }

    public var stateDatabaseURL: URL {
        baseDirectoryURL.appendingPathComponent("state.db")
    }

    public var memoryDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("memory", isDirectory: true)
    }

    /// Loads global config merged with optional `<workspace>/.swiftcode/config.json`.
    public func load(workspaceRoot: URL? = nil) -> SwiftCodeConfiguration {
        let global = decodeFile(at: configFileURL) ?? SwiftCodeConfiguration()
        guard let workspaceRoot else { return global }
        let localURL = workspaceRoot
            .appendingPathComponent(".swiftcode", isDirectory: true)
            .appendingPathComponent("config.json")
        return decodeFile(at: localURL) ?? global
    }

    /// Persists configuration cleanly with sorted keys for human diffing.
    public func save(_ configuration: SwiftCodeConfiguration, to url: URL? = nil) throws {
        let target = url ?? configFileURL
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: target, options: .atomic)
    }

    /// Ensures `~/.swiftcode/` subdirectories exist (`memory`, `vm-images`, `skills`).
    public func ensureDirectories() throws {
        let fm = FileManager.default
        for subdir in ["", "memory", "vm-images", "skills"] {
            let dir = subdir.isEmpty ? baseDirectoryURL : baseDirectoryURL.appendingPathComponent(subdir, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func decodeFile(at url: URL) -> SwiftCodeConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SwiftCodeConfiguration.self, from: data)
    }
}
