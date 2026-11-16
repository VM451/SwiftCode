import Foundation
import SwiftParser
import SwiftSyntax

/// Pure-Swift AST inspector powered by `apple/swift-syntax` (FR-4.1).
public struct SwiftASTInspector: Sendable {
    public init() {}

    /// Extracts all top-level and nested declarations with exact 1-based line ranges.
    public func outline(source: String, relativePath: String) -> [ASTSymbol] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: relativePath, tree: tree)
        let visitor = CollectorVisitor(relativePath: relativePath, converter: converter)
        visitor.walk(tree)
        return visitor.symbols
    }

    public func outline(fileURL: URL, relativeTo root: URL? = nil) throws -> [ASTSymbol] {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let rel = root.map {
            fileURL.standardizedFileURL.path.replacingOccurrences(of: $0.standardizedFileURL.path + "/", with: "")
        } ?? fileURL.lastPathComponent
        return outline(source: source, relativePath: rel)
    }

    /// Searches all `.swift` files under `workspaceRoot` for declarations matching `query`.
    public func findSymbol(named query: String, in workspaceRoot: URL, maxFiles: Int = 500) -> [ASTSymbol] {
        let lower = query.lowercased()
        let swiftFiles = enumerateSwiftFiles(in: workspaceRoot, limit: maxFiles)
        var matches: [ASTSymbol] = []
        for url in swiftFiles {
            guard let symbols = try? outline(fileURL: url, relativeTo: workspaceRoot) else { continue }
            for sym in symbols where sym.name.lowercased().contains(lower) {
                matches.append(sym)
            }
        }
        return matches
    }

    private func enumerateSwiftFiles(in root: URL, limit: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let path = url.path
            if path.contains("/.build/") || path.contains("/DerivedData/") {
                continue
            }
            if url.pathExtension == "swift" {
                files.append(url)
                if files.count >= limit { break }
            }
        }
        return files
    }
}

private final class CollectorVisitor: SyntaxVisitor {
    let relativePath: String
    let converter: SourceLocationConverter
    var symbols: [ASTSymbol] = []

    init(relativePath: String, converter: SourceLocationConverter) {
        self.relativePath = relativePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .struct, node: node, signature: "struct \(node.name.text)")
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .class, node: node, signature: "class \(node.name.text)")
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .actor, node: node, signature: "actor \(node.name.text)")
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .enum, node: node, signature: "enum \(node.name.text)")
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .protocol, node: node, signature: "protocol \(node.name.text)")
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        record(name: name, kind: .extension, node: node, signature: "extension \(name)")
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let params = node.signature.parameterClause.trimmedDescription
        let ret = node.signature.returnClause?.trimmedDescription ?? ""
        let sig = "func \(node.name.text)\(params)\(ret.isEmpty ? "" : " \(ret)")"
        record(name: node.name.text, kind: .function, node: node, signature: sig)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let sig = "init\(node.signature.parameterClause.trimmedDescription)"
        record(name: "init", kind: .initializer, node: node, signature: sig)
        return .visitChildren
    }

    private func record(name: String, kind: ASTSymbolKind, node: some SyntaxProtocol, signature: String) {
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia).line
        symbols.append(ASTSymbol(
            name: name,
            kind: kind,
            signature: signature,
            relativePath: relativePath,
            startLine: start,
            endLine: max(start, end)
        ))
    }
}
