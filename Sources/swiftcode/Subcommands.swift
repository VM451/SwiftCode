import ArgumentParser
import Foundation
import SwiftCodeCore
import SwiftCodeDaemon

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "daemon", abstract: "Manage the always-on background daemon")

    @Argument(help: "Action: start, status, or install.")
    var action: String = "status"

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cfg = ConfigurationStore().load(workspaceRoot: workspace)
        switch action {
        case "start":
            let service = DaemonService(workspaceRoot: workspace, configuration: cfg)
            try await service.start()
            print("SwiftCode daemon running on \(cfg.daemon.webhookHost):\(cfg.daemon.webhookPort). Press Ctrl+C to exit.")
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(30))
            }
        case "install":
            let execPath = ProcessInfo.processInfo.arguments.first ?? "/usr/local/bin/swiftcode"
            let url = try ServiceInstaller.install(executablePath: execPath, workingDirectory: workspace.path)
            print("Installed background service manifest at \(url.path)")
        default:
            print("Daemon config: \(cfg.daemon.webhookHost):\(cfg.daemon.webhookPort) | Socket: \(cfg.daemon.socketPath)")
        }
    }
}

struct VMCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "vm", abstract: "Manage Apple Virtualization.framework micro-VMs")

    @Argument(help: "Action: status, init, list, or clean.")
    var action: String = "status"

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cfg = ConfigurationStore().load(workspaceRoot: workspace)
        let runner = MicroVMRunner(imageDirectory: cfg.sandbox.vmImageDirectory)
        switch action {
        case "init":
            let manifest = try await runner.initializeImageDirectory(workspaceRoot: workspace)
            print("Initialized micro-VM directory manifest at \(manifest.path)")
        case "list":
            let imgs = await runner.listImages()
            print(imgs.isEmpty ? "No micro-VM images configured." : imgs.joined(separator: "\n"))
        case "clean":
            try await runner.clean()
            print("Cleaned ephemeral micro-VM scratch data.")
        default:
            let report = await runner.checkReadiness()
            print("Virtualization supported: \(report.virtualizationSupported)")
            print("Image dir: \(report.imageDirectory)")
            print("Kernel found: \(report.kernelFound) | Initrd: \(report.initrdFound) | Disk: \(report.diskImageFound)")
            for note in report.notes { print("Note: \(note)") }
        }
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Diagnose Swift toolchain, Keychain, sandbox, and VM readiness")

    func run() async throws {
        let store = SecretStoreFactory.makeDefault()
        let keys = (try? await store.listKeys()) ?? []
        let vm = await MicroVMRunner().checkReadiness()
        let inspector = LiveAppleFoundationModelInspector()
        let local = inspector.localAvailability()
        let pcc = await inspector.pccQuotaState()
        let cfg = ConfigurationStore().load()

        print("SwiftCode Doctor:")
        print("  Default Apple Model: \(cfg.defaultAppleModel.displayName) (\(cfg.defaultAppleModel.shortLabel))")
        print("  Apple Foundation (Local): available=\(local.available) context=\(local.contextSize) tok\(local.reason.map { " (\($0))" } ?? "")")
        print("  Apple Private Cloud Compute: available=\(pcc.isAvailable) limitReached=\(pcc.isLimitReached) approaching=\(pcc.isApproachingLimit)")
        if pcc.isLimitReached || !pcc.isAvailable {
            print("    PCC Note: \(pcc.formattedGuidance())")
        }
        print("  SecretStore keys configured: \(keys.isEmpty ? "none" : keys.joined(separator: ", "))")
        print("  macOS Seatbelt sandbox-exec: \(FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"))")
        print("  Virtualization.framework: \(vm.virtualizationSupported)")
        print("  Apple Silicon MLX ready: \(MLXLocalProvider.isAppleSiliconSupported)")
        print("  Current RSS memory: \(String(format: "%.2f", ProcessMemoryReporter.currentRSSMegabytes())) MB")
    }
}

struct ModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "model", abstract: "View or switch default Apple Foundation Model (local or pcc)")

    @Argument(help: "Optional variant to set as default: local or pcc.")
    var variant: String?

    @Flag(name: .long, help: "Open Apple iCloud+ / quota options in System Settings when Private Cloud Compute is limited.")
    var icloud = false

    func run() async throws {
        let store = ConfigurationStore()
        var cfg = store.load()
        if let variant {
            guard let parsed = AppleFoundationModelVariant.parseUserSelection(variant) else {
                throw ValidationError("Specify 'local' or 'pcc'.")
            }
            cfg.applyDefaultAppleModel(parsed)
            try store.save(cfg)
            print("Default Apple Foundation Model set to \(cfg.defaultAppleModel.displayName) (\(cfg.defaultAppleModel.shortLabel)).")
        } else {
            print("Default Apple Foundation Model: \(cfg.defaultAppleModel.displayName) (\(cfg.defaultAppleModel.shortLabel))")
        }
        let pcc = await LiveAppleFoundationModelInspector().pccQuotaState()
        print("PCC Status: \(pcc.formattedGuidance())")
        if pcc.isLimitReached || pcc.isApproachingLimit {
            PCCDesktopNotifier.notifyIfNeeded(PCCQuotaNotice(state: pcc))
        }
        if icloud {
            await PCCDesktopNotifier.openICloudQuotaOptions()
        }
    }
}

struct KeyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "key", abstract: "Manage API keys securely in Keychain / AES-GCM vault")

    @Argument(help: "Action: set, get, delete, or list.")
    var action: String

    @Argument(help: "Key name (e.g. ANTHROPIC_API_KEY).")
    var keyName: String?

    @Argument(help: "Secret value (when using set).")
    var value: String?

    func run() async throws {
        let store = SecretStoreFactory.makeDefault()
        switch action {
        case "set":
            guard let keyName, let value else { throw ValidationError("Usage: swiftcode key set <KEY> <VALUE>") }
            try await store.setSecret(value, forKey: keyName)
            print("Stored secret '\(keyName)' securely.")
        case "get":
            guard let keyName else { throw ValidationError("Key name required.") }
            if let val = try await store.getSecret(forKey: keyName) {
                print("\(keyName)=\(val.prefix(6))...(\(val.count) chars)")
            } else {
                print("Key '\(keyName)' not found.")
            }
        case "delete":
            guard let keyName else { throw ValidationError("Key name required.") }
            try await store.deleteSecret(forKey: keyName)
            print("Deleted '\(keyName)'.")
        default:
            let keys = try await store.listKeys()
            print(keys.isEmpty ? "No keys stored." : keys.joined(separator: "\n"))
        }
    }
}

struct ASTCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ast", abstract: "Print SwiftSyntax AST outline for a Swift file")

    @Argument(help: "Path to .swift file.")
    var path: String

    func run() async throws {
        let url = URL(fileURLWithPath: path)
        let symbols = try SwiftASTInspector().outline(fileURL: url)
        for sym in symbols {
            print("L\(sym.startLine)-\(sym.endLine) [\(sym.kind.rawValue)] \(sym.signature)")
        }
    }
}

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mcp", abstract: "Operate native MCP stdio server or test external MCP servers")

    @Argument(help: "Action: serve or list.")
    var action: String = "serve"

    func run() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if action == "serve" {
            await MCPStdioServer(workspaceRoot: workspace).runStdioLoop()
        } else {
            let cfg = ConfigurationStore().load(workspaceRoot: workspace)
            for server in cfg.mcpServers {
                print("\(server.name) (\(server.transport)) enabled=\(server.enabled)")
            }
        }
    }
}

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "config", abstract: "Initialize or display ~/.swiftcode/config.json")

    @Argument(help: "Action: init or show.")
    var action: String = "show"

    func run() async throws {
        let store = ConfigurationStore()
        if action == "init" {
            try store.ensureDirectories()
            let cfg = SwiftCodeConfiguration()
            try store.save(cfg)
            print("Initialized \(store.configFileURL.path)")
        } else {
            let cfg = store.load()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cfg)
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
