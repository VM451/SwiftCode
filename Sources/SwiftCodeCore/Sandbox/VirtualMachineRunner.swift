import Foundation
#if os(macOS) && canImport(Virtualization)
import Virtualization
#endif

/// Ephemeral micro-VM lifecycle orchestrator built directly on Apple's `Virtualization.framework` (FR-6.2).
public actor MicroVMRunner {
    private let imageRoot: URL

    public init(imageDirectory: String = "~/.swiftcode/vm-images/ubuntu-swift6") {
        let expanded = (imageDirectory as NSString).expandingTildeInPath
        self.imageRoot = URL(fileURLWithPath: expanded, isDirectory: true)
    }

    public func checkReadiness() -> VMReadinessReport {
        let fm = FileManager.default
        let kernel = imageRoot.appendingPathComponent("vmlinuz")
        let initrd = imageRoot.appendingPathComponent("initrd.img")
        let disk = imageRoot.appendingPathComponent("rootfs.ext4")

        #if os(macOS) && canImport(Virtualization)
        let supported = VZVirtualMachine.isSupported
        #else
        let supported = false
        #endif

        let kernelFound = fm.fileExists(atPath: kernel.path)
        let initrdFound = fm.fileExists(atPath: initrd.path)
        let diskFound = fm.fileExists(atPath: disk.path)

        var notes: [String] = []
        if !supported {
            notes.append("Apple Virtualization.framework is unavailable on this host or entitlement is missing.")
        }
        if !kernelFound {
            notes.append("Place Linux kernel at \(kernel.path) (or run `swiftcode vm init` to scaffold image dir).")
        }
        return VMReadinessReport(
            virtualizationSupported: supported,
            imageDirectory: imageRoot.path,
            kernelFound: kernelFound,
            initrdFound: initrdFound,
            diskImageFound: diskFound,
            notes: notes
        )
    }

    /// Scaffolds `~/.swiftcode/vm-images/<name>/manifest.json` ready for Linux kernel/rootfs artifacts.
    public func initializeImageDirectory(workspaceRoot: URL) throws -> URL {
        try FileManager.default.createDirectory(at: imageRoot, withIntermediateDirectories: true)
        let spec = VMConfigurationSpec(
            kernelPath: imageRoot.appendingPathComponent("vmlinuz").path,
            initrdPath: imageRoot.appendingPathComponent("initrd.img").path,
            diskImagePath: imageRoot.appendingPathComponent("rootfs.ext4").path,
            workspaceDirectory: workspaceRoot.path
        )
        let manifestURL = imageRoot.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(spec).write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    /// Lists image directories present under `~/.swiftcode/vm-images/`.
    public func listImages() -> [String] {
        let parent = imageRoot.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else {
            return []
        }
        return entries.sorted()
    }

    /// Cleans ephemeral VM runtime scratch files.
    public func clean() throws {
        let scratch = imageRoot.appendingPathComponent("ephemeral", isDirectory: true)
        if FileManager.default.fileExists(atPath: scratch.path) {
            try FileManager.default.removeItem(at: scratch)
        }
    }

    #if os(macOS) && canImport(Virtualization)
    /// Builds and validates a `VZVirtualMachineConfiguration` with VirtioFS workspace sharing and vsock.
    public func buildVZConfiguration(spec: VMConfigurationSpec) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        config.cpuCount = max(1, min(spec.cpuCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount))
        let bytes = UInt64(max(512, spec.memorySizeMB)) * 1024 * 1024
        config.memorySize = min(bytes, VZVirtualMachineConfiguration.maximumAllowedMemorySize)

        let kernelURL = URL(fileURLWithPath: spec.kernelPath)
        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootLoader.commandLine = spec.commandLine
        if let initrd = spec.initrdPath, FileManager.default.fileExists(atPath: initrd) {
            bootLoader.initialRamdiskURL = URL(fileURLWithPath: initrd)
        }
        config.bootLoader = bootLoader

        let workspaceDir = VZSharedDirectory(url: URL(fileURLWithPath: spec.workspaceDirectory), readOnly: false)
        let share = VZSingleDirectoryShare(directory: workspaceDir)
        let fsDevice = VZVirtioFileSystemDeviceConfiguration(tag: "workspace")
        fsDevice.share = share
        config.directorySharingDevices = [fsDevice]

        if let diskPath = spec.diskImagePath, FileManager.default.fileExists(atPath: diskPath) {
            let attachment = try VZDiskImageStorageDeviceAttachment(
                url: URL(fileURLWithPath: diskPath),
                readOnly: false
            )
            config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]
        }

        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [network]
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        config.socketDevices = [VZVirtioSocketDeviceConfiguration()]

        try config.validate()
        return config
    }
    #endif
}
