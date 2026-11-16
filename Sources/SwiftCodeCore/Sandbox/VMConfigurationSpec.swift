import Foundation

/// Specification and readiness check for Apple `Virtualization.framework` micro-VMs (FR-6.2).
public struct VMConfigurationSpec: Codable, Sendable, Equatable {
    public let name: String
    public let cpuCount: Int
    public let memorySizeMB: Int
    public let kernelPath: String
    public let initrdPath: String?
    public let diskImagePath: String?
    public let commandLine: String
    public let workspaceDirectory: String

    public init(
        name: String = "ubuntu-swift6",
        cpuCount: Int = 2,
        memorySizeMB: Int = 2048,
        kernelPath: String,
        initrdPath: String? = nil,
        diskImagePath: String? = nil,
        commandLine: String = "console=hvc0 root=/dev/vda rw",
        workspaceDirectory: String
    ) {
        self.name = name
        self.cpuCount = cpuCount
        self.memorySizeMB = memorySizeMB
        self.kernelPath = kernelPath
        self.initrdPath = initrdPath
        self.diskImagePath = diskImagePath
        self.commandLine = commandLine
        self.workspaceDirectory = workspaceDirectory
    }
}

/// Readiness diagnostics returned by `MicroVMRunner`.
public struct VMReadinessReport: Codable, Sendable, Equatable {
    public let virtualizationSupported: Bool
    public let imageDirectory: String
    public let kernelFound: Bool
    public let initrdFound: Bool
    public let diskImageFound: Bool
    public let notes: [String]

    public var isReadyToBoot: Bool {
        virtualizationSupported && kernelFound
    }
}
