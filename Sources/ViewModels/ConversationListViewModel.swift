import Foundation
import SwiftUI

@Observable
@MainActor
final class ConversationListViewModel {
    var conversations: [Conversation] = []
    var selectedId: String?
    var searchQuery: String = ""
    var searchResults: [Conversation] = []
    var isSearching: Bool = false
    var errorMessage: String?

    private let persistence: ChatPersistence
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    var displayedConversations: [Conversation] {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? conversations : searchResults
    }

    init(persistence: ChatPersistence) {
        self.persistence = persistence
    }

    func loadConversations() async {
        do {
            conversations = try await persistence.listConversations()
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createConversation() async {
        do {
            let conv = try await persistence.createConversation(title: "New Chat")
            conversations.insert(conv, at: 0)
            selectedId = conv.id
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteConversation(id: String) async {
        do {
            try await persistence.deleteConversation(id: id)
            conversations.removeAll { $0.id == id }
            searchResults.removeAll { $0.id == id }
            if selectedId == id {
                if conversations.isEmpty {
                    // Mirror startup: never leave the chat pane stranded on a deleted conversation.
                    if let conv = try? await persistence.createConversation(title: "New Chat") {
                        conversations.insert(conv, at: 0)
                        selectedId = conv.id
                    } else {
                        selectedId = nil
                    }
                } else {
                    selectedId = conversations.first?.id
                }
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
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        if trimmed.count < 2 {
            searchResults = conversations
                .filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
                .sorted { $0.updatedAt > $1.updatedAt }
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            await self.search(query: trimmed)
        }
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        do {
            let remoteMatches = try await persistence.searchConversations(query: trimmed)
            guard !Task.isCancelled else { return }
            let activeQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard activeQuery.isEmpty || activeQuery == trimmed else { return }
            let localMatches = conversations.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
            searchResults = merged(localMatches, remoteMatches)
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            isSearching = false
        }
    }

    private func merged(_ lhs: [Conversation], _ rhs: [Conversation]) -> [Conversation] {
        var deduped: [String: Conversation] = [:]
        for conversation in lhs + rhs {
            deduped[conversation.id] = conversation
        }
        return deduped.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
