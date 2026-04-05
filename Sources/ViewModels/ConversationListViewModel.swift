import Foundation
import SwiftUI

@Observable
@MainActor
final class ConversationListViewModel {
    var conversations: [Conversation] = []
    var selectedId: String?
    var searchQuery: String = ""
    var searchResults: [Message] = []
    var errorMessage: String?

    private let persistence: ChatPersistence

    init(persistence: ChatPersistence) {
        self.persistence = persistence
    }

    func loadConversations() async {
        do {
            conversations = try await persistence.listConversations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createConversation() async {
        do {
            let conv = try await persistence.createConversation(title: "New Chat")
            conversations.insert(conv, at: 0)
            selectedId = conv.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteConversation(id: String) async {
        do {
            try await persistence.deleteConversation(id: id)
            conversations.removeAll { $0.id == id }
            if selectedId == id {
                selectedId = conversations.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameConversation(id: String, title: String) async {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = title
        do {
            try await persistence.updateConversation(conversations[idx])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try await persistence.search(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
