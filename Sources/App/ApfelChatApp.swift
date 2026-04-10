import SwiftUI
import AppKit

@main
struct ApfelChatApp: App {
    @State private var serverManager = ServerManager()

    init() {
        if !isRunningAsAppBundle() {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @State private var persistence: SQLitePersistence?
    @State private var conversationListVM: ConversationListViewModel?
    @State private var chatVM: ChatViewModel?
    @State private var settingsVM = SettingsViewModel()
    @State private var startupError: String?
    @State private var isReady = false
    @State private var controlServer: ChatControlServer?
    @State private var didStart = false
    private let enableAPI = CommandLine.arguments.contains("--api")

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady, let listVM = conversationListVM, let chatVM = chatVM {
                    mainContent(listVM: listVM, chatVM: chatVM)
                } else if let error = startupError {
                    errorView(error)
                } else {
                    loadingView
                }
            }
            .frame(minWidth: 700, minHeight: 500)
            .task {
                guard !didStart else { return }
                didStart = true
                await startup()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
    }

    private func mainContent(listVM: ConversationListViewModel, chatVM: ChatViewModel) -> some View {
        NavigationSplitView {
            ConversationListView(viewModel: listVM) { conversationId in
                chatVM.switchTo(conversationId: conversationId)
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
        .navigationTitle(windowTitle(listVM: listVM))
        .sheet(isPresented: $settingsVM.showSettings) {
            SettingsPanel(viewModel: settingsVM)
        }
        .onChange(of: settingsVM.showSettings) { _, isShowing in
            if !isShowing {
                chatVM.settings = settingsVM.toModelSettings()
                chatVM.ttsLanguage = settingsVM.ttsLanguage
            }
        }
        .preferredColorScheme(settingsVM.resolvedColorScheme)
    }

    private func windowTitle(listVM: ConversationListViewModel) -> String {
        guard let id = listVM.selectedId,
              let conv = listVM.conversations.first(where: { $0.id == id }),
              conv.title != "New Chat" else {
            return "apfel chat"
        }
        return conv.title
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Starting on-device AI...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
                startupError = nil
                Task { await startup() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func startup() async {
        do {
            let db = try SQLitePersistence()
            self.persistence = db

            let listVM = ConversationListViewModel(persistence: db)
            let chatVM = ChatViewModel(persistence: db)
            chatVM.settings = settingsVM.toModelSettings()
            chatVM.autoSpeak = settingsVM.autoSpeak
            chatVM.ttsLanguage = settingsVM.ttsLanguage
            chatVM.onConversationListInvalidation = {
                await listVM.loadConversations()
            }

            self.conversationListVM = listVM
            self.chatVM = chatVM
            self.isReady = true

            async let initialLoad: Void = loadInitialConversationState(listVM: listVM, chatVM: chatVM)
            async let serviceLoad: Void = connectServices(chatVM: chatVM)
            _ = await (initialLoad, serviceLoad)

            if enableAPI {
                let ctrl = ChatControlServer(chatVM: chatVM, listVM: listVM, settingsVM: settingsVM)
                ctrl.start()
                self.controlServer = ctrl
            }
        } catch {
            startupError = "Database error: \(error.localizedDescription)"
        }
    }

    private func loadInitialConversationState(
        listVM: ConversationListViewModel,
        chatVM: ChatViewModel
    ) async {
        await listVM.loadConversations()

        if listVM.conversations.isEmpty {
            await listVM.createConversation()
        }

        if let first = listVM.conversations.first {
            listVM.selectedId = first.id
            chatVM.switchTo(conversationId: first.id)
        }
    }

    private func connectServices(chatVM: ChatViewModel) async {
        chatVM.setServiceStatus("Starting on-device AI...")

        guard let port = await serverManager.start() else {
            if case .failed(let message) = serverManager.state {
                chatVM.setServiceStatus(message)
            } else {
                chatVM.setServiceStatus("Failed to start on-device AI")
            }
            return
        }

        let service = ApfelChatService(port: port)
        let health = try? await service.healthCheck()
        chatVM.configureService(service, contextWindow: health?.contextWindow)

        let stt: any SpeechInput
        if let ohrPath = ServerManager.findOhrBinary() {
            stt = OhrSpeechInput(ohrPath: ohrPath, languageCode: settingsVM.ttsLanguage)
            printToStderr("apfel-chat: using ohr for speech input")
        } else {
            stt = OnDeviceSpeechInput()
            printToStderr("apfel-chat: using on-device speech input")
        }

        chatVM.configureSpeech(
            speechInput: stt,
            speechOutput: OnDeviceSpeechOutput()
        )
        chatVM.configureVision(AugeService())
    }
}
