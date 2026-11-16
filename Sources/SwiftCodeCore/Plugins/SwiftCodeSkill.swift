import Foundation

/// Extensible pure-Swift plugin contract for SkillKit (PRD §6 / FR-9.1).
public protocol SwiftCodeSkill: Sendable {
    var identifier: String { get }
    var version: String { get }
    var tools: [any SwiftCodeTool] { get }
    var systemPromptAppend: String? { get }
}

/// C-ABI reference box returned by `@_cdecl("createSwiftCodeSkill")` dynamic plugin libraries.
public final class SwiftCodeSkillPluginBox: Sendable {
    public let skill: any SwiftCodeSkill

    public init(_ skill: any SwiftCodeSkill) {
        self.skill = skill
    }
}
