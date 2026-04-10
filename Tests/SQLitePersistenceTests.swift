import Testing
import Foundation
@testable import apfel_chat

@Suite("SQLite Persistence")
struct SQLitePersistenceTests {
    private func makeInMemory() throws -> SQLitePersistence {
        try SQLitePersistence(path: ":memory:")
    }

    @Test("Create and list conversations")
    func createAndList() async throws {
        let db = try makeInMemory()
        let conv1 = try await db.createConversation(title: "First chat")
        let conv2 = try await db.createConversation(title: "Second chat")
        let list = try await db.listConversations()
        #expect(list.count == 2)
        #expect(list[0].id == conv2.id)
        #expect(list[1].id == conv1.id)
    }

    @Test("Delete conversation removes it and its messages")
    func deleteConversation() async throws {
        let db = try makeInMemory()
        let conv = try await db.createConversation(title: "To delete")
        let msg = Message(conversationId: conv.id, role: .user, content: "Hello")
        try await db.addMessage(msg, to: conv.id)
        try await db.deleteConversation(id: conv.id)
        let list = try await db.listConversations()
        #expect(list.isEmpty)
        let msgs = try await db.messages(for: conv.id)
        #expect(msgs.isEmpty)
    }

    @Test("Add and retrieve messages in order")
    func addAndRetrieveMessages() async throws {
        let db = try makeInMemory()
        let conv = try await db.createConversation(title: "Chat")
        let msg1 = Message(conversationId: conv.id, role: .user, content: "Hello")
        let msg2 = Message(conversationId: conv.id, role: .assistant, content: "Hi there")
        try await db.addMessage(msg1, to: conv.id)
        try await db.addMessage(msg2, to: conv.id)
        let msgs = try await db.messages(for: conv.id)
        #expect(msgs.count == 2)
        #expect(msgs[0].role == .user)
        #expect(msgs[0].content == "Hello")
        #expect(msgs[1].role == .assistant)
        #expect(msgs[1].content == "Hi there")
    }

    @Test("Update conversation title")
    func updateConversation() async throws {
        let db = try makeInMemory()
        var conv = try await db.createConversation(title: "Old title")
        conv.title = "New title"
        try await db.updateConversation(conv)
        let list = try await db.listConversations()
        #expect(list[0].title == "New title")
    }

    @Test("Search finds messages across conversations")
    func searchMessages() async throws {
        let db = try makeInMemory()
        let conv1 = try await db.createConversation(title: "Chat 1")
        let conv2 = try await db.createConversation(title: "Chat 2")
        try await db.addMessage(
            Message(conversationId: conv1.id, role: .user, content: "Tell me about Swift"),
            to: conv1.id
        )
        try await db.addMessage(
            Message(conversationId: conv2.id, role: .user, content: "Swift is great"),
            to: conv2.id
        )
        try await db.addMessage(
            Message(conversationId: conv2.id, role: .user, content: "Python too"),
            to: conv2.id
        )
        let results = try await db.search(query: "swift")
        #expect(results.count == 2)
    }

    @Test("Conversation search uses titles and indexed message content")
    func searchConversations() async throws {
        let db = try makeInMemory()
        let conv1 = try await db.createConversation(title: "Swift chat")
        let conv2 = try await db.createConversation(title: "Other")
        try await db.addMessage(
            Message(conversationId: conv2.id, role: .user, content: "Tell me about performance tuning"),
            to: conv2.id
        )

        let titleMatches = try await db.searchConversations(query: "Swift")
        #expect(titleMatches.count == 1)
        #expect(titleMatches[0].id == conv1.id)

        let contentMatches = try await db.searchConversations(query: "performance")
        #expect(contentMatches.count == 1)
        #expect(contentMatches[0].id == conv2.id)
    }

    @Test("Update message content")
    func updateMessage() async throws {
        let db = try makeInMemory()
        let conv = try await db.createConversation(title: "Chat")
        let msg = Message(conversationId: conv.id, role: .assistant, content: "Partial")
        try await db.addMessage(msg, to: conv.id)
        var updated = msg
        updated.content = "Full response here"
        updated.tokenCount = 42
        try await db.updateMessage(updated)
        let msgs = try await db.messages(for: conv.id)
        #expect(msgs[0].content == "Full response here")
        #expect(msgs[0].tokenCount == 42)
    }
}
