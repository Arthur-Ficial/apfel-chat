import Testing
import Foundation
@testable import apfel_chat

@Suite("ConversationListViewModel")
@MainActor
struct ConversationListViewModelTests {

    private func makeVM() async throws -> (ConversationListViewModel, MockPersistence) {
        let persistence = MockPersistence()
        let vm = ConversationListViewModel(persistence: persistence)
        return (vm, persistence)
    }

    @Test("Create new conversation")
    func createConversation() async throws {
        let (vm, _) = try await makeVM()
        await vm.createConversation()
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations[0].title == "New Chat")
        #expect(vm.selectedId == vm.conversations[0].id)
    }

    @Test("Delete conversation")
    func deleteConversation() async throws {
        let (vm, _) = try await makeVM()
        await vm.createConversation()
        let id = vm.conversations[0].id
        await vm.deleteConversation(id: id)
        #expect(vm.conversations.isEmpty)
        #expect(vm.selectedId == nil)
    }

    @Test("Rename conversation")
    func renameConversation() async throws {
        let (vm, _) = try await makeVM()
        await vm.createConversation()
        let id = vm.conversations[0].id
        await vm.renameConversation(id: id, title: "My Chat")
        #expect(vm.conversations[0].title == "My Chat")
    }

    @Test("Load conversations on refresh")
    func loadConversations() async throws {
        let persistence = MockPersistence()
        _ = try await persistence.createConversation(title: "Existing")
        let vm = ConversationListViewModel(persistence: persistence)
        await vm.loadConversations()
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations[0].title == "Existing")
    }

    @Test("Search filters results")
    func searchConversations() async throws {
        let (vm, persistence) = try await makeVM()
        let conv = try await persistence.createConversation(title: "Chat")
        try await persistence.addMessage(
            Message(conversationId: conv.id, role: .user, content: "Tell me about Swift"),
            to: conv.id
        )
        await vm.loadConversations()
        await vm.search(query: "Swift")
        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults[0].id == conv.id)
    }
}
