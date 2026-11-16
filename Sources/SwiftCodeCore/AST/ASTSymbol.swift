import Foundation

/// Symbol kinds extracted via `SwiftSyntax`.
public enum ASTSymbolKind: String, Codable, Sendable, CaseIterable {
    case `struct`
    case `class`
    case `actor`
    case `enum`
    case `protocol`
    case `extension`
    case function
    case initializer
    case property
}

/// AST symbol entry with exact file location and signature.
public struct ASTSymbol: Codable, Sendable, Equatable {
    public let name: String
    public let kind: ASTSymbolKind
    public let signature: String
    public let relativePath: String
    public let startLine: Int
    public let endLine: Int

    public init(
        name: String,
        kind: ASTSymbolKind,
        signature: String,
        relativePath: String,
        startLine: Int,
        endLine: Int
    ) {
        self.name = name
        self.kind = kind
        self.signature = signature
        self.relativePath = relativePath
        self.startLine = startLine
        self.endLine = endLine
    }
}
