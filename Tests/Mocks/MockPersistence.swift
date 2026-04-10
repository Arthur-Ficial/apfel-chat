import Foundation
@testable import apfel_chat

actor MockPersistence: ChatPersistence {
    var conversations: [Conversation] = []
    var messageStore: [String: [Message]] = [:]

    func createConversation(title: String) async throws -> Conversation {
        let conv = Conversation(title: title)
        conversations.append(conv)
        messageStore[conv.id] = []
        return conv
    }

    func listConversations() async throws -> [Conversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteConversation(id: String) async throws {
        conversations.removeAll { $0.id == id }
        messageStore.removeValue(forKey: id)
    }

    func addMessage(_ msg: Message, to conversationId: String) async throws {
        messageStore[conversationId, default: []].append(msg)
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].updatedAt = Date()
        }
    }

    func messages(for conversationId: String) async throws -> [Message] {
        messageStore[conversationId] ?? []
    }

    func updateConversation(_ conv: Conversation) async throws {
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx] = conv
        }
    }

    func searchConversations(query: String) async throws -> [Conversation] {
        let lowered = query.lowercased()
        let matchingIDs = Set(messageStore.values.flatMap { $0 }.compactMap { message in
            message.content.lowercased().contains(lowered) ? message.conversationId : nil
        })

        return conversations.filter {
            $0.title.lowercased().contains(lowered) || matchingIDs.contains($0.id)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func search(query: String) async throws -> [Message] {
        let lowered = query.lowercased()
        return messageStore.values.flatMap { $0 }.filter {
            $0.content.lowercased().contains(lowered)
        }
    }
}
