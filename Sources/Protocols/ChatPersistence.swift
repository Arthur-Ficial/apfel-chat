import Foundation

protocol ChatPersistence: Sendable {
    func createConversation(title: String) async throws -> Conversation
    func listConversations() async throws -> [Conversation]
    func deleteConversation(id: String) async throws
    func addMessage(_ msg: Message, to conversationId: String) async throws
    func messages(for conversationId: String) async throws -> [Message]
    func updateConversation(_ conv: Conversation) async throws
    func search(query: String) async throws -> [Message]
}
