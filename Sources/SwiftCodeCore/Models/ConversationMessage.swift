import Foundation

/// Role of a message within an agent conversation.
public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Base64-encoded image attachment for multimodal providers.
public struct ImageAttachment: Codable, Sendable, Equatable {
    public let mimeType: String
    public let base64Data: String

    public init(mimeType: String, base64Data: String) {
        self.mimeType = mimeType
        self.base64Data = base64Data
    }
}

/// Immutable turn record inside an agent conversation history.
public struct ConversationMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let reasoning: String?
    public let toolCalls: [ToolCall]
    public let toolCallID: String?
    public let toolName: String?
    public let attachments: [ImageAttachment]
    public let createdAt: Date
    public let isPinned: Bool

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        reasoning: String? = nil,
        toolCalls: [ToolCall] = [],
        toolCallID: String? = nil,
        toolName: String? = nil,
        attachments: [ImageAttachment] = [],
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.attachments = attachments
        self.createdAt = createdAt
        self.isPinned = isPinned
    }
}
