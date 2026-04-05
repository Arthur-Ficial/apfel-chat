import SwiftUI
import AppKit

@main
struct ApfelChatApp: App {
    @State private var serverManager = ServerManager()

    init() {
        // CRITICAL: When running as a bare binary (not .app bundle),
        // macOS won't give us foreground/keyboard focus without this.
        // Without it, clicking the window does nothing — focus stays in the terminal.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    @State private var chatService: ApfelChatService?
    @State private var persistence: SQLitePersistence?
    @State private var conversationListVM: ConversationListViewModel?
    @State private var chatVM: ChatViewModel?
    @State private var settingsVM = SettingsViewModel()
    @State private var serverError: String?
    @State private var isReady = false
    @State private var controlServer: ChatControlServer?
    private let enableAPI = CommandLine.arguments.contains("--api")

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
                        HStack(spacing: 8) {
                            if chatVM.speechOutput != nil {
                                Button(action: {
                                    if chatVM.speechOutput?.isSpeaking == true {
                                        chatVM.speechOutput?.stop()
                                    } else {
                                        chatVM.speakLastResponse()
                                    }
                                }) {
                                    Image(systemName: chatVM.speechOutput?.isSpeaking == true ? "speaker.wave.3.fill" : "speaker.wave.2")
                                }
                                .help("Read last response aloud")
                            }
                            Button(action: { settingsVM.showSettings = true }) {
                                Image(systemName: "gearshape")
                            }
                            .help("Settings")
                        }
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

            var serverContextWindow: Int?
            if let health = try? await service.healthCheck() {
                serverContextWindow = health.contextWindow
            }

            let stt: any SpeechInput
            if let ohrPath = ServerManager.findOhrBinary() {
                stt = OhrSpeechInput(ohrPath: ohrPath, languageCode: settingsVM.ttsLanguage)
                printToStderr("apfel-chat: using ohr for speech input")
            } else {
                stt = OnDeviceSpeechInput()
                printToStderr("apfel-chat: using on-device speech input")
            }
            let tts = OnDeviceSpeechOutput()

            let listVM = ConversationListViewModel(persistence: db)
            let chatVM = ChatViewModel(chatService: service, persistence: db, speechInput: stt, speechOutput: tts)
            chatVM.settings = settingsVM.toModelSettings()
            chatVM.contextWindow = serverContextWindow

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

            if enableAPI {
                let ctrl = ChatControlServer(chatVM: chatVM, listVM: listVM, settingsVM: settingsVM)
                ctrl.start()
                self.controlServer = ctrl
            }
        } catch {
            serverError = "Database error: \(error.localizedDescription)"
        }
    }
}
