import Foundation

/// Execution isolation tier applied to shell commands and autonomous tasks.
public enum SandboxTier: String, Codable, Sendable, CaseIterable {
    case none
    case seatbelt
    case vm
}

/// Effective sandbox policy passed into tool execution contexts.
public struct SandboxPolicy: Codable, Sendable, Equatable {
    public let tier: SandboxTier
    public let workspaceRoot: URL
    public let allowNetwork: Bool
    public let additionalReadPaths: [String]
    public let vmImageDirectory: String?

    public init(
        tier: SandboxTier = .seatbelt,
        workspaceRoot: URL,
        allowNetwork: Bool = false,
        additionalReadPaths: [String] = [],
        vmImageDirectory: String? = nil
    ) {
        self.tier = tier
        self.workspaceRoot = workspaceRoot
        self.allowNetwork = allowNetwork
        self.additionalReadPaths = additionalReadPaths
        self.vmImageDirectory = vmImageDirectory
    }
}
