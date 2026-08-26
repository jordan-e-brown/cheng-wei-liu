import Foundation

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ConversationSessionSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
}

struct ChatRequest: Codable, Sendable {
    let sessionID: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case message
    }
}

struct ChatResponse: Codable, Sendable {
    let sessionID: String
    let reply: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case reply
    }
}

struct SessionListResponse: Codable, Sendable {
    let sessions: [ConversationSessionSummary]
}

struct SessionMessagesResponse: Codable, Sendable {
    let sessionID: String
    let messages: [ServerMessage]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case messages
    }
}

struct ServerMessage: Codable, Sendable {
    let role: String
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case role, content
        case createdAt = "created_at"
    }
}

struct HealthResponse: Codable, Sendable {
    let ok: Bool
    let model: String
    let headroom: Bool
}

struct MemoryResponse: Codable, Sendable {
    let memory: String
}
