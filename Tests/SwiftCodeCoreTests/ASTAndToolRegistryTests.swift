import Foundation
import Testing
@testable import SwiftCodeCore

private struct SampleSkill: SwiftCodeSkill {
    let identifier = "dev.swiftcode.sample"
    let version = "1.0.0"
    let tools: [any SwiftCodeTool] = [EchoSkillTool()]
    let systemPromptAppend: String? = "Sample skill loaded."
}

private struct EchoSkillTool: SwiftCodeTool {
    let name = "echoSkill"
    let description = "Echo input"
    let riskLevel: ToolRiskLevel = .readOnly
    let inputSchemaJSON = "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}}}"

    func execute(argumentsJSON: String, context: ToolContext) async throws -> ToolOutput {
        .success("echo:\(argumentsJSON)")
    }
}

struct ASTAndToolRegistryTests {
    @Test func swiftASTInspectorExtractsSymbolsAndLines() {
        let code = """
        import Foundation

        public actor SampleEngine {
            public init() {}
            public func compute(value: Int) -> Int {
                value * 2
            }
        }
        """
        let symbols = SwiftASTInspector().outline(source: code, relativePath: "SampleEngine.swift")
        #expect(symbols.contains { $0.kind == .actor && $0.name == "SampleEngine" && $0.startLine == 3 })
        #expect(symbols.contains { $0.kind == .function && $0.name == "compute" && $0.startLine == 5 })
    }

    @Test func toolRegistryStrictlyFiltersPlanVsBuildMode() async {
        let registry = ToolRegistry.makeDefault()
        let planDefs = await registry.definitions(for: .plan)
        let buildDefs = await registry.definitions(for: .build)

        #expect(planDefs.contains { $0.name == "readFile" })
        #expect(planDefs.contains { $0.name == "astOutline" })
        #expect(planDefs.contains { $0.name == "writeFile" } == false)
        #expect(planDefs.contains { $0.name == "executeShell" } == false)
        #expect(buildDefs.contains { $0.name == "writeFile" })
        #expect(buildDefs.contains { $0.name == "executeShell" })
    }

    @Test func readFileGuardsBinaryPayloadsAndPatchFileAppliesEdits() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binURL = tempDir.appendingPathComponent("blob.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02]).write(to: binURL)

        let ctx = ToolContext(
            sessionID: UUID(),
            workspaceRoot: tempDir,
            mode: .build,
            sandboxPolicy: SandboxPolicy(tier: .none, workspaceRoot: tempDir)
        )

        let binOut = try await ReadFileTool().execute(argumentsJSON: "{\"path\":\"blob.png\"}", context: ctx)
        #expect(binOut.metadata["binary"] == "true")
        #expect(binOut.content.contains("sha256="))

        let writeOut = try await WriteFileTool().execute(
            argumentsJSON: "{\"path\":\"Hello.swift\",\"content\":\"func greet() {\\n    print(\\\"hi\\\")\\n}\"}",
            context: ctx
        )
        #expect(writeOut.isError == false)

        let patchOut = try await PatchFileTool().execute(
            argumentsJSON: "{\"path\":\"Hello.swift\",\"search\":\"print(\\\"hi\\\")\",\"replace\":\"print(\\\"bye\\\")\"}",
            context: ctx
        )
        #expect(patchOut.isError == false)
        let updated = try String(contentsOf: tempDir.appendingPathComponent("Hello.swift"), encoding: .utf8)
        #expect(updated.contains("bye"))
    }

    @Test func skillRegistryRegistersCustomToolsAndPrompt() async {
        let tools = ToolRegistry.makeDefault()
        let skills = SkillRegistry()
        await skills.register(SampleSkill(), into: tools)

        let allowed = await tools.isPermitted(toolName: "echoSkill", in: .plan)
        #expect(allowed)
        let prompt = await skills.combinedSystemPromptAdditions()
        #expect(prompt.contains("Sample skill loaded."))
    }
}
