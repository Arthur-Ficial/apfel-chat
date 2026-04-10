import Foundation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    var messages: [Message] = []
    var currentInput: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?
    var conversationId: String?
    var systemPrompt: String?
    var settings: ModelSettings = ModelSettings()
    var autoSpeak: Bool = AppDefaults.autoSpeak
    var ttsLanguage: String = AppDefaults.ttsLanguage
    var contextWindow: Int?
    var augeService: AugeService?
    var isAnalyzingImage: Bool = false
    var showFilePicker: Bool = false
    var serviceStatusMessage: String?
    var isLoadingConversation: Bool = false
    private(set) var contextCutoffIndex: Int?
    /// IDs of messages that fall outside the context window (for O(1) lookup in views).
    private(set) var outOfContextMessageIds: Set<String> = []
    /// ID of the first in-context message (used to place the divider in ChatView).
    var contextCutoffMessageId: String? {
        guard let cutoff = contextCutoffIndex, cutoff < messages.count else { return nil }
        return messages[cutoff].id
    }
    var contextTruncationNotice: String?
    /// Incremented each time buffered streaming tokens are flushed to the UI.
    private(set) var streamTick: Int = 0

    var isServiceReady: Bool { chatService != nil }

    @ObservationIgnored private var shownTruncationForConversations: Set<String> = []
    @ObservationIgnored private var chatService: ChatService?
    private let persistence: ChatPersistence
    var speechInput: (any SpeechInput)?
    var speechOutput: (any SpeechOutput)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var conversationCache: [String: [Message]] = [:]
    @ObservationIgnored var onConversationListInvalidation: (@MainActor () async -> Void)?

    private let streamFlushInterval: TimeInterval = 0.05
    private let scrollSignalInterval: TimeInterval = 0.12

    init(
        chatService: ChatService? = nil,
        persistence: ChatPersistence,
        speechInput: (any SpeechInput)? = nil,
        speechOutput: (any SpeechOutput)? = nil
    ) {
        self.chatService = chatService
        self.persistence = persistence
        self.speechInput = speechInput
        self.speechOutput = speechOutput
        self.serviceStatusMessage = chatService == nil ? "Starting on-device AI..." : nil
    }

    func configureService(_ chatService: ChatService, contextWindow: Int?) {
        self.chatService = chatService
        self.contextWindow = contextWindow
        self.serviceStatusMessage = nil
    }

    func configureSpeech(
        speechInput: (any SpeechInput)?,
        speechOutput: (any SpeechOutput)?
    ) {
        self.speechInput = speechInput
        self.speechOutput = speechOutput
    }

    func configureVision(_ augeService: AugeService?) {
        self.augeService = augeService
    }

    func setServiceStatus(_ status: String?) {
        serviceStatusMessage = status
    }

    func recomputeContextCutoff() {
        guard let window = contextWindow, !messages.isEmpty else {
            contextCutoffIndex = nil
            outOfContextMessageIds = []
            return
        }

        var total = 0
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            total += messages[i].tokenCount ?? 0
            if total > window {
                let newCutoff = i + 1
                let convId = conversationId ?? ""
                if contextCutoffIndex == nil && !shownTruncationForConversations.contains(convId) {
                    shownTruncationForConversations.insert(convId)
                    contextTruncationNotice = "Older messages are now outside the context window"
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(4))
                        contextTruncationNotice = nil
                    }
                }
                contextCutoffIndex = newCutoff
                outOfContextMessageIds = Set(messages[0..<newCutoff].map(\.id))
                return
            }
        }

        contextCutoffIndex = nil
        outOfContextMessageIds = []
    }

    func send() async {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let convId = conversationId else { return }
        guard let chatService else {
            errorMessage = serviceStatusMessage ?? "Starting on-device AI..."
            return
        }

        currentInput = ""
        errorMessage = nil

        let isFirstUserMessage = !messages.contains(where: { $0.role == .user })
        let userMsg = Message(conversationId: convId, role: .user, content: text)
        messages.append(userMsg)
        cache(messages, for: convId)
        try? await persistence.addMessage(userMsg, to: convId)
        refreshConversationList()

        await streamAssistantResponse(
            using: chatService,
            apiMessages: buildAPIMessages(for: convId),
            conversationId: convId,
            titleSeed: text,
            shouldGenerateTitle: isFirstUserMessage
        )
    }

    func switchTo(conversationId: String) {
        if let currentConversationId = self.conversationId {
            cache(messages, for: currentConversationId)
        }

        streamTask?.cancel()
        loadTask?.cancel()
        self.conversationId = conversationId
        errorMessage = nil
        contextTruncationNotice = nil
        contextCutoffIndex = nil
        outOfContextMessageIds = []

        if let cached = conversationCache[conversationId] {
            messages = cached
            recomputeContextCutoff()
            isLoadingConversation = false
        } else {
            isLoadingConversation = !messages.isEmpty
        }

        loadTask = Task { [weak self] in
            await self?.loadMessages(for: conversationId)
        }
    }

    func loadMessages(for targetConversationId: String? = nil) async {
        guard let convId = targetConversationId ?? conversationId else {
            isLoadingConversation = false
            return
        }

        do {
            let loaded = try await persistence.messages(for: convId)
            guard !Task.isCancelled else { return }
            conversationCache[convId] = loaded
            guard conversationId == convId else { return }
            messages = loaded
            isLoadingConversation = false
            recomputeContextCutoff()
        } catch {
            guard !Task.isCancelled else { return }
            isLoadingConversation = false
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        messages = []
        errorMessage = nil
        contextTruncationNotice = nil
        if let convId = conversationId {
            conversationCache[convId] = []
        }
    }

    // MARK: - Speech

    func toggleListening() async {
        guard let stt = speechInput else { return }
        if stt.isListening {
            let transcript = stt.stopListening()
            if !transcript.isEmpty {
                currentInput = transcript
                await send()
            }
        } else {
            let granted = await stt.requestPermissions()
            if granted {
                stt.startListening()
            }
        }
    }

    func speakLastResponse() {
        guard let tts = speechOutput else { return }
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        tts.speak(lastAssistant.content, languageCode: ttsLanguage)
    }

    // MARK: - Image Analysis

    func handleImageDrop(urls: [URL]) async {
        guard chatService != nil else {
            errorMessage = serviceStatusMessage ?? "Starting on-device AI..."
            return
        }
        guard let url = urls.first, let auge = augeService else { return }
        guard let convId = conversationId else { return }

        isAnalyzingImage = true
        let result = await auge.analyze(imagePath: url.path)
        isAnalyzingImage = false

        var summary = result.summary
        if let window = contextWindow {
            let maxChars = window * 4
            let currentChars = messages.reduce(0) { $0 + $1.content.count }
            let available = maxChars - currentChars - 500
            if summary.count > available && available > 200 {
                summary = String(summary.prefix(available)) + "\n... (truncated to fit context window)"
            }
        }

        let isFirstUserMessage = !messages.contains(where: { $0.role == .user })
        let imageMsg = Message(conversationId: convId, role: .user, content: summary)
        messages.append(imageMsg)
        cache(messages, for: convId)
        try? await persistence.addMessage(imageMsg, to: convId)
        refreshConversationList()

        errorMessage = nil

        if let chatService {
            await streamAssistantResponse(
                using: chatService,
                apiMessages: buildAPIMessages(for: convId),
                conversationId: convId,
                titleSeed: summary,
                shouldGenerateTitle: isFirstUserMessage
            )
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
    }

    // MARK: - AI-Powered Title Generation

    private func generateTitle(from firstMessage: String, conversationId: String) async {
        guard let chatService else { return }

        let titlePrompt = Message(
            conversationId: conversationId,
            role: .user,
            content: "Generate a very short title (3-5 words max, no quotes) for a conversation that starts with: \(firstMessage)"
        )
        let systemMsg = Message(
            conversationId: conversationId,
            role: .system,
            content: "You are a title generator. Respond with ONLY the title, nothing else. 3-5 words maximum. No quotes, no punctuation at the end."
        )

        var title = ""
        let stream = chatService.send(messages: [systemMsg, titlePrompt], settings: ModelSettings())
        do {
            for try await delta in stream {
                if let text = delta.text { title += text }
            }
        } catch {
            let words = firstMessage.split(separator: " ").prefix(6).joined(separator: " ")
            title = words.count > 40 ? String(words.prefix(40)) + "..." : words
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let conv = Conversation(id: conversationId, title: cleanTitle)
        try? await persistence.updateConversation(conv)
        refreshConversationList()
    }

    private func buildAPIMessages(for conversationId: String) -> [Message] {
        var apiMessages: [Message] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(Message(conversationId: conversationId, role: .system, content: sys))
        }
        apiMessages.append(contentsOf: messages)
        return apiMessages
    }

    private func streamAssistantResponse(
        using chatService: ChatService,
        apiMessages: [Message],
        conversationId: String,
        titleSeed: String,
        shouldGenerateTitle: Bool
    ) async {
        isStreaming = true

        let assistantMessage = Message(
            conversationId: conversationId,
            role: .assistant,
            content: "",
            isStreaming: true
        )
        messages.append(assistantMessage)
        cache(messages, for: conversationId)

        let assistantID = assistantMessage.id
        let start = Date()
        let task = Task { [weak self] in
            guard let self else { return }

            let stream = chatService.send(messages: apiMessages, settings: settings)

            do {
                var streamBuffer = ""
                var lastFlush = Date()
                var lastScrollSignal = Date.distantPast

                for try await delta in stream {
                    try Task.checkCancellation()

                    if let deltaText = delta.text {
                        streamBuffer += deltaText
                        let now = Date()
                        if now.timeIntervalSince(lastFlush) >= streamFlushInterval {
                            flushStreamBuffer(&streamBuffer, assistantID: assistantID, conversationId: conversationId)
                            lastFlush = now
                            if now.timeIntervalSince(lastScrollSignal) >= scrollSignalInterval {
                                streamTick += 1
                                lastScrollSignal = now
                            }
                        }
                    }

                    if let usage = delta.usage,
                       let assistantIdx = displayedAssistantIndex(id: assistantID, conversationId: conversationId) {
                        messages[assistantIdx].tokenCount = usage.totalTokens
                        cache(messages, for: conversationId)
                    }
                }

                flushStreamBuffer(&streamBuffer, assistantID: assistantID, conversationId: conversationId)
                streamTick += 1

                guard let assistantIdx = finalizeAssistantMessage(
                    assistantID: assistantID,
                    conversationId: conversationId,
                    startedAt: start
                ) else { return }

                try? await persistence.addMessage(messages[assistantIdx], to: conversationId)
                refreshConversationList()

                if conversationId == self.conversationId {
                    recomputeContextCutoff()
                }

                if autoSpeak, let tts = speechOutput, !messages[assistantIdx].content.isEmpty {
                    tts.speak(messages[assistantIdx].content, languageCode: ttsLanguage)
                }

                if shouldGenerateTitle {
                    Task { [weak self] in
                        await self?.generateTitle(from: titleSeed, conversationId: conversationId)
                    }
                }
            } catch is CancellationError {
                await finishCancelledStream(
                    assistantID: assistantID,
                    conversationId: conversationId,
                    startedAt: start
                )
            } catch {
                await finishErroredStream(
                    assistantID: assistantID,
                    conversationId: conversationId,
                    startedAt: start,
                    error: error
                )
            }
        }

        streamTask = task
        await task.value
        streamTask = nil
        isStreaming = false
    }

    private func flushStreamBuffer(
        _ streamBuffer: inout String,
        assistantID: String,
        conversationId: String
    ) {
        guard !streamBuffer.isEmpty else { return }
        guard let assistantIdx = displayedAssistantIndex(id: assistantID, conversationId: conversationId) else { return }
        messages[assistantIdx].content += streamBuffer
        streamBuffer = ""
        cache(messages, for: conversationId)
    }

    private func finalizeAssistantMessage(
        assistantID: String,
        conversationId: String,
        startedAt: Date
    ) -> Int? {
        guard let assistantIdx = displayedAssistantIndex(id: assistantID, conversationId: conversationId) else {
            return nil
        }

        messages[assistantIdx].isStreaming = false
        messages[assistantIdx].durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        if messages[assistantIdx].content.isEmpty {
            messages.remove(at: assistantIdx)
            cache(messages, for: conversationId)
            return nil
        }

        cache(messages, for: conversationId)
        return assistantIdx
    }

    private func finishCancelledStream(
        assistantID: String,
        conversationId: String,
        startedAt: Date
    ) async {
        guard let assistantIdx = finalizeAssistantMessage(
            assistantID: assistantID,
            conversationId: conversationId,
            startedAt: startedAt
        ) else { return }

        try? await persistence.addMessage(messages[assistantIdx], to: conversationId)
        refreshConversationList()
        if conversationId == self.conversationId {
            recomputeContextCutoff()
        }
    }

    private func finishErroredStream(
        assistantID: String,
        conversationId: String,
        startedAt: Date,
        error: Error
    ) async {
        if let assistantIdx = finalizeAssistantMessage(
            assistantID: assistantID,
            conversationId: conversationId,
            startedAt: startedAt
        ) {
            try? await persistence.addMessage(messages[assistantIdx], to: conversationId)
            refreshConversationList()
        }

        if conversationId == self.conversationId {
            recomputeContextCutoff()
            errorMessage = error.localizedDescription
        }
    }

    private func displayedAssistantIndex(id: String, conversationId: String) -> Int? {
        guard self.conversationId == conversationId else { return nil }
        return messages.firstIndex { $0.id == id }
    }

    private func cache(_ messages: [Message], for conversationId: String) {
        conversationCache[conversationId] = messages
    }

    private func refreshConversationList() {
        guard let onConversationListInvalidation else { return }
        Task { await onConversationListInvalidation() }
    }
}
