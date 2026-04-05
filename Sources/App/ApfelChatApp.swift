import SwiftUI

@main
struct ApfelChatApp: App {
    @State private var serverManager = ServerManager()
    @State private var chatService: ApfelChatService?
    @State private var persistence: SQLitePersistence?
    @State private var conversationListVM: ConversationListViewModel?
    @State private var chatVM: ChatViewModel?
    @State private var settingsVM = SettingsViewModel()
    @State private var serverError: String?
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady, let listVM = conversationListVM, let chatVM = chatVM {
                    mainContent(listVM: listVM, chatVM: chatVM)
                } else if let error = serverError {
                    errorView(error)
                } else {
                    loadingView
                }
            }
            .frame(minWidth: 700, minHeight: 500)
            .task { await startup() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
    }

    private func mainContent(listVM: ConversationListViewModel, chatVM: ChatViewModel) -> some View {
        NavigationSplitView {
            ConversationListView(viewModel: listVM) { conversationId in
                chatVM.conversationId = conversationId
                Task { await chatVM.loadMessages() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await listVM.createConversation() } }) {
                        Image(systemName: "plus")
                    }
                    .help("New Chat")
                }
            }
        } detail: {
            ChatView(viewModel: chatVM)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { settingsVM.showSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")
                    }
                }
        }
        .navigationTitle("apfel chat")
        .sheet(isPresented: $settingsVM.showSettings) {
            SettingsPanel(viewModel: settingsVM)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Starting on-device AI...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                serverError = nil
                Task { await startup() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }

    private func startup() async {
        do {
            let db = try SQLitePersistence()
            self.persistence = db

            guard let port = await serverManager.start() else {
                if case .failed(let msg) = serverManager.state {
                    serverError = msg
                } else {
                    serverError = "Failed to start server"
                }
                return
            }

            let service = ApfelChatService(port: port)
            self.chatService = service

            let stt = OnDeviceSpeechInput()
            let tts = OnDeviceSpeechOutput()

            let listVM = ConversationListViewModel(persistence: db)
            let chatVM = ChatViewModel(chatService: service, persistence: db, speechInput: stt, speechOutput: tts)
            chatVM.settings = settingsVM.toModelSettings()

            await listVM.loadConversations()

            if listVM.conversations.isEmpty {
                await listVM.createConversation()
            }
            if let first = listVM.conversations.first {
                listVM.selectedId = first.id
                chatVM.conversationId = first.id
                await chatVM.loadMessages()
            }

            self.conversationListVM = listVM
            self.chatVM = chatVM
            self.isReady = true
        } catch {
            serverError = "Database error: \(error.localizedDescription)"
        }
    }
}
