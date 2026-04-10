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
    private(set) var contextCutoffIndex: Int?
    /// IDs of messages that fall outside the context window (for O(1) lookup in views).
    private(set) var outOfContextMessageIds: Set<String> = []
    /// ID of the first in-context message (used to place the divider in ChatView).
    var contextCutoffMessageId: String? {
        guard let cutoff = contextCutoffIndex, cutoff < messages.count else { return nil }
        return messages[cutoff].id
    }
    var contextTruncationNotice: String?
    private var shownTruncationForConversations: Set<String> = []
    /// Incremented each time buffered streaming tokens are flushed to the UI (≈60fps).
    /// ChatView observes this Int instead of comparing the full content string each frame.
    private(set) var streamTick: Int = 0

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
                // Show one-time notice when cutoff first appears in this conversation
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
                outOfContextMessageIds = Set(messages[0..<newCutoff].map { $0.id })
                return
            }
        }
        contextCutoffIndex = nil
        outOfContextMessageIds = []
    }

    private let chatService: ChatService
    private let persistence: ChatPersistence
    let speechInput: (any SpeechInput)?
    let speechOutput: (any SpeechOutput)?
    private var loadTask: Task<Void, Never>?

    init(
        chatService: ChatService,
        persistence: ChatPersistence,
        speechInput: (any SpeechInput)? = nil,
        speechOutput: (any SpeechOutput)? = nil
    ) {
        self.chatService = chatService
        self.persistence = persistence
        self.speechInput = speechInput
        self.speechOutput = speechOutput
    }

    func send() async {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let convId = conversationId else { return }

        currentInput = ""
        errorMessage = nil

        let userMsg = Message(conversationId: convId, role: .user, content: text)
        messages.append(userMsg)
        try? await persistence.addMessage(userMsg, to: convId)

        let isFirstMessage = messages.filter({ $0.role == .user }).count == 1

        // Build API messages including system prompt
        var apiMessages: [Message] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(Message(conversationId: convId, role: .system, content: sys))
        }
        apiMessages.append(contentsOf: messages)

        // Stream response
        isStreaming = true
        let assistantMsg = Message(conversationId: convId, role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let assistantIdx = messages.count - 1
        let start = Date()

        let stream = chatService.send(messages: apiMessages, settings: settings)

        do {
            // Batch token updates to ~60fps to avoid a SwiftUI re-render per token.
            var streamBuffer = ""
            var lastFlush = Date()
            for try await delta in stream {
                if let deltaText = delta.text {
                    streamBuffer += deltaText
                    let now = Date()
                    if now.timeIntervalSince(lastFlush) >= 0.016 {
                        messages[assistantIdx].content += streamBuffer
                        streamBuffer = ""
                        lastFlush = now
                        streamTick += 1
                    }
                }
                if let usage = delta.usage {
                    messages[assistantIdx].tokenCount = usage.totalTokens
                }
            }
            if !streamBuffer.isEmpty {
                messages[assistantIdx].content += streamBuffer
                streamTick += 1
            }
            messages[assistantIdx].isStreaming = false
            messages[assistantIdx].durationMs = Int(Date().timeIntervalSince(start) * 1000)
            try? await persistence.addMessage(messages[assistantIdx], to: convId)
            recomputeContextCutoff()

            // Auto-speak the response if enabled
            if autoSpeak, let tts = speechOutput, !messages[assistantIdx].content.isEmpty {
                tts.speak(messages[assistantIdx].content, languageCode: ttsLanguage)
            }

            // Auto-title after first exchange (deferred so it doesn't block UI)
            if isFirstMessage {
                let capturedText = text
                let capturedConvId = convId
                Task { [weak self] in
                    await self?.generateTitle(from: capturedText, conversationId: capturedConvId)
                }
            }
        } catch {
            // If assistant message is empty, remove it; otherwise keep partial content
            if messages[assistantIdx].content.isEmpty {
                messages.remove(at: assistantIdx)
            } else {
                messages[assistantIdx].isStreaming = false
            }
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }

    /// Switch to a conversation: cancel any in-flight load, clear immediately, load in background.
    func switchTo(conversationId: String) {
        loadTask?.cancel()
        self.conversationId = conversationId
        messages = []
        errorMessage = nil
        contextTruncationNotice = nil
        contextCutoffIndex = nil
        loadTask = Task { await loadMessages() }
    }

    func loadMessages() async {
        guard let convId = conversationId else { return }
        do {
            let loaded = try await persistence.messages(for: convId)
            guard !Task.isCancelled else { return }
            messages = loaded
            recomputeContextCutoff()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        messages = []
        errorMessage = nil
        contextTruncationNotice = nil
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
        guard let url = urls.first, let auge = augeService else { return }
        guard let convId = conversationId else { return }

        isAnalyzingImage = true
        let result = await auge.analyze(imagePath: url.path)
        isAnalyzingImage = false

        // Truncate if it would blow the context window
        var summary = result.summary
        if let window = contextWindow {
            let maxChars = window * 4 // rough token-to-char ratio
            let currentChars = messages.reduce(0) { $0 + $1.content.count }
            let available = maxChars - currentChars - 500 // leave room for response
            if summary.count > available && available > 200 {
                summary = String(summary.prefix(available)) + "\n... (truncated to fit context window)"
            }
        }

        let isFirstMessage = messages.filter({ $0.role == .user }).isEmpty

        // Add as a user message with the analysis and immediately stream a reply
        let imageMsg = Message(conversationId: convId, role: .user, content: summary)
        messages.append(imageMsg)
        try? await persistence.addMessage(imageMsg, to: convId)

        errorMessage = nil

        var apiMessages: [Message] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(Message(conversationId: convId, role: .system, content: sys))
        }
        apiMessages.append(contentsOf: messages)

        isStreaming = true
        let assistantMsg = Message(conversationId: convId, role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let assistantIdx = messages.count - 1
        let start = Date()

        let stream = chatService.send(messages: apiMessages, settings: settings)

        do {
            var streamBuffer = ""
            var lastFlush = Date()
            for try await delta in stream {
                if let deltaText = delta.text {
                    streamBuffer += deltaText
                    let now = Date()
                    if now.timeIntervalSince(lastFlush) >= 0.016 {
                        messages[assistantIdx].content += streamBuffer
                        streamBuffer = ""
                        lastFlush = now
                        streamTick += 1
                    }
                }
                if let usage = delta.usage {
                    messages[assistantIdx].tokenCount = usage.totalTokens
                }
            }
            if !streamBuffer.isEmpty {
                messages[assistantIdx].content += streamBuffer
                streamTick += 1
            }
            messages[assistantIdx].isStreaming = false
            messages[assistantIdx].durationMs = Int(Date().timeIntervalSince(start) * 1000)
            try? await persistence.addMessage(messages[assistantIdx], to: convId)
            recomputeContextCutoff()

            if autoSpeak, let tts = speechOutput, !messages[assistantIdx].content.isEmpty {
                tts.speak(messages[assistantIdx].content, languageCode: ttsLanguage)
            }

            if isFirstMessage {
                let capturedSummary = summary
                let capturedConvId = convId
                Task { [weak self] in
                    await self?.generateTitle(from: capturedSummary, conversationId: capturedConvId)
                }
            }
        } catch {
            if messages[assistantIdx].content.isEmpty {
                messages.remove(at: assistantIdx)
            } else {
                messages[assistantIdx].isStreaming = false
            }
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }

    // MARK: - AI-Powered Title Generation

    private func generateTitle(from firstMessage: String, conversationId: String) async {
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
            // Fallback: truncate first message
            let words = firstMessage.split(separator: " ").prefix(6).joined(separator: " ")
            title = words.count > 40 ? String(words.prefix(40)) + "..." : words
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        // Update directly — no need to list all conversations
        let conv = Conversation(id: conversationId, title: cleanTitle)
        try? await persistence.updateConversation(conv)
    }
}
