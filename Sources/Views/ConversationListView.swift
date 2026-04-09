import SwiftUI

struct ConversationListView: View {
    @Bindable var viewModel: ConversationListViewModel
    var onSelect: (String) -> Void

    @State private var editingId: String?
    @State private var editTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search...", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onChange(of: viewModel.searchQuery) {
                    Task { await viewModel.search(query: viewModel.searchQuery) }
                }

            List(selection: $viewModel.selectedId) {
                if viewModel.conversations.isEmpty && !viewModel.searchQuery.isEmpty {
                    Text("No results for \"\(viewModel.searchQuery)\"")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
                ForEach(viewModel.conversations) { conv in
                    if editingId == conv.id {
                        TextField("Title", text: $editTitle)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                Task {
                                    await viewModel.renameConversation(id: conv.id, title: editTitle)
                                    editingId = nil
                                }
                            }
                            .tag(conv.id)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .font(.body)
                                .lineLimit(1)
                            Text(conv.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(conv.id)
                        .contextMenu {
                            Button("Rename") {
                                editTitle = conv.title
                                editingId = conv.id
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.deleteConversation(id: conv.id) }
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let conv = viewModel.conversations[index]
                        Task { await viewModel.deleteConversation(id: conv.id) }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedId) { _, newId in
                if let id = newId { onSelect(id) }
            }
        }
        .frame(minWidth: 220)
    }
}
