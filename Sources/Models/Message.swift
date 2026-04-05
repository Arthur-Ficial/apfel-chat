import Foundation

enum Role: String, Codable, Sendable {
    case user, assistant, system
}

struct Message: Identifiable, Codable, Sendable {
    let id: String
    let conversationId: String
    let role: Role
    var content: String
    let timestamp: Date
    var tokenCount: Int?
    var durationMs: Int?
    var isStreaming: Bool

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: Role,
        content: String,
        timestamp: Date = Date(),
        tokenCount: Int? = nil,
        durationMs: Int? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenCount = tokenCount
        self.durationMs = durationMs
        self.isStreaming = isStreaming
    }
}
