import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Manages built-in and dynamically loaded `.dylib` / `.so` `SwiftCodeSkill` plugins (FR-9.1).
public actor SkillRegistry {
    private var skills: [String: any SwiftCodeSkill] = [:]
    private var loadedHandleAddresses: [UInt] = []

    public init(skills: [any SwiftCodeSkill] = []) {
        for skill in skills {
            self.skills[skill.identifier] = skill
        }
    }

    public func register(_ skill: any SwiftCodeSkill, into toolRegistry: ToolRegistry? = nil) async {
        skills[skill.identifier] = skill
        if let toolRegistry {
            await toolRegistry.register(skill: skill)
        }
    }

    public func allSkills() -> [any SwiftCodeSkill] {
        skills.values.sorted { $0.identifier < $1.identifier }
    }

    public func combinedSystemPromptAdditions() -> String {
        allSkills()
            .compactMap(\.systemPromptAppend)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Loads a compiled dynamic skill library (`.dylib` on macOS, `.so` on Linux) exporting `createSwiftCodeSkill`.
    public func loadDynamicPlugin(at url: URL, into toolRegistry: ToolRegistry? = nil) async throws -> any SwiftCodeSkill {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen failure"
            throw NSError(domain: "SkillRegistry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load plugin \(url.lastPathComponent): \(reason)",
            ])
        }
        guard let symbol = dlsym(handle, "createSwiftCodeSkill") else {
            dlclose(handle)
            throw NSError(domain: "SkillRegistry", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Plugin \(url.lastPathComponent) missing @_cdecl(\"createSwiftCodeSkill\") entry point.",
            ])
        }

        typealias FactoryFn = @convention(c) () -> UnsafeMutableRawPointer
        let factory = unsafeBitCast(symbol, to: FactoryFn.self)
        let boxPtr = factory()
        let box = Unmanaged<SwiftCodeSkillPluginBox>.fromOpaque(boxPtr).takeRetainedValue()
        loadedHandleAddresses.append(UInt(bitPattern: handle))
        await register(box.skill, into: toolRegistry)
        return box.skill
    }
}
