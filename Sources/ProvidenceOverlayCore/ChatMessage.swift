import Foundation

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Pure helper namespace for chat history manipulation. Extracted to
/// ProvidenceOverlayCore so it's trivially testable without pulling in
/// the full overlay app target.
public enum ChatHistory {
    /// Returns messages trimmed to the last `limit` entries (limit clamped to >= 1).
    public static func trimmed(_ messages: [ChatMessage], limit: Int) -> [ChatMessage] {
        let cap = max(1, limit)
        if messages.count <= cap {
            return messages
        }
        return Array(messages.suffix(cap))
    }
}
