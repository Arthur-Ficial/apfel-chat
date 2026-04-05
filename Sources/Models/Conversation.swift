import Foundation

struct Conversation: Identifiable, Codable, Sendable {
    let id: String
    var title: String
    var systemPrompt: String?
    let createdAt: Date
    var updatedAt: Date
    var modelSettings: ModelSettings?

    init(
        id: String = UUID().uuidString,
        title: String,
        systemPrompt: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelSettings: ModelSettings? = nil
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelSettings = modelSettings
    }
}
