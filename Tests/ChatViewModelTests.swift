import Testing
import Foundation
@testable import apfel_chat

@Suite("ChatViewModel")
@MainActor
struct ChatViewModelTests {

    private func makeVM() -> (ChatViewModel, MockChatService, MockPersistence) {
        let chatService = MockChatService()
        let persistence = MockPersistence()
        let sttInput = MockSpeechInput()
        let ttsOutput = MockSpeechOutput()
        let vm = ChatViewModel(
            chatService: chatService,
            persistence: persistence,
            speechInput: sttInput,
            speechOutput: ttsOutput
        )
        vm.conversationId = "test-conv"
        return (vm, chatService, persistence)
    }

    @Test("Send message appends user and streams assistant response")
    func sendMessage() async throws {
        let (vm, chatService, _) = makeVM()
        chatService.streamResponses = ["Hello", " world"]
        vm.currentInput = "Hi there"
        await vm.send()

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "Hi there")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "Hello world")
        #expect(vm.currentInput == "")
        #expect(vm.isStreaming == false)
    }

    @Test("Send with empty input does nothing")
    func sendEmpty() async throws {
        let (vm, chatService, _) = makeVM()
        vm.currentInput = ""
        await vm.send()
        #expect(vm.messages.isEmpty)
        #expect(chatService.sendCallCount == 0)
    }

    @Test("Send with whitespace-only input does nothing")
    func sendWhitespace() async throws {
        let (vm, chatService, _) = makeVM()
        vm.currentInput = "   \n  "
        await vm.send()
        #expect(vm.messages.isEmpty)
        #expect(chatService.sendCallCount == 0)
    }

    @Test("Error during streaming shows error")
    func streamingError() async throws {
        let (vm, chatService, _) = makeVM()
        chatService.shouldError = true
        vm.currentInput = "Hello"
        await vm.send()

        #expect(vm.messages.count == 1) // just user message
        #expect(vm.errorMessage != nil)
        #expect(vm.isStreaming == false)
    }

    @Test("Clear removes all messages")
    func clearMessages() async throws {
        let (vm, _, _) = makeVM()
        vm.currentInput = "Test"
        await vm.send()
        #expect(!vm.messages.isEmpty)
        vm.clear()
        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test("Load messages from persistence")
    func loadMessages() async throws {
        let (vm, _, persistence) = makeVM()
        let conv = try await persistence.createConversation(title: "Test")
        vm.conversationId = conv.id
        try await persistence.addMessage(
            Message(conversationId: conv.id, role: .user, content: "Saved msg"),
            to: conv.id
        )
        await vm.loadMessages()
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].content == "Saved msg")
    }

    @Test("Settings passed to chat service")
    func settingsPassthrough() async throws {
        let (vm, chatService, _) = makeVM()
        // Pre-populate so this isn't the first user message (avoids title generation overwrite)
        vm.messages.append(Message(conversationId: "test-conv", role: .user, content: "Earlier"))
        vm.messages.append(Message(conversationId: "test-conv", role: .assistant, content: "Previous"))
        vm.settings = ModelSettings(temperature: 0.5, maxTokens: 500)
        vm.currentInput = "Hello"
        await vm.send()
        #expect(chatService.lastSettings?.temperature == 0.5)
        #expect(chatService.lastSettings?.maxTokens == 500)
    }

    @Test("System prompt prepended to messages sent to service")
    func systemPromptPrepended() async throws {
        let (vm, chatService, _) = makeVM()
        // Pre-populate so this isn't the first user message (avoids title generation overwrite)
        vm.messages.append(Message(conversationId: "test-conv", role: .user, content: "Earlier"))
        vm.messages.append(Message(conversationId: "test-conv", role: .assistant, content: "Previous"))
        vm.systemPrompt = "You are a helpful bot"
        vm.currentInput = "Hello"
        await vm.send()
        // First message in lastMessages should be system
        #expect(chatService.lastMessages.first?.role == .system)
        #expect(chatService.lastMessages.first?.content == "You are a helpful bot")
    }

    @Test("Speech input toggles listening")
    func speechToggle() async throws {
        let (vm, _, _) = makeVM()
        let stt = vm.speechInput as! MockSpeechInput

        stt.mockTranscript = "Voice input text"

        // Start listening
        await vm.toggleListening()
        #expect(stt.isListening == true)

        // Stop listening - should populate transcript
        await vm.toggleListening()
        #expect(stt.isListening == false)
    }

    @Test("Send without conversationId does nothing")
    func sendNoConversation() async throws {
        let (vm, chatService, _) = makeVM()
        vm.conversationId = nil
        vm.currentInput = "Hello"
        await vm.send()
        #expect(vm.messages.isEmpty)
        #expect(chatService.sendCallCount == 0)
    }

    @Test("AI title generation after first message")
    func aiTitleGeneration() async throws {
        let (vm, chatService, persistence) = makeVM()
        // Create the conversation in persistence so title can be updated
        let conv = try await persistence.createConversation(title: "New Chat")
        vm.conversationId = conv.id
        chatService.streamResponses = ["Response"]

        vm.currentInput = "Tell me about quantum physics"
        await vm.send()

        // The mock service was called twice: once for chat, once for title generation
        #expect(chatService.sendCallCount == 2)

        // Check that the conversation title was updated in persistence
        let convs = try await persistence.listConversations()
        let updated = convs.first(where: { $0.id == conv.id })
        #expect(updated != nil)
        // Title should not be "New Chat" anymore (AI generated something)
        #expect(updated?.title != "New Chat")
    }

    @Test("Speak last response calls TTS")
    func speakLastResponse() async throws {
        let (vm, _, _) = makeVM()
        let tts = vm.speechOutput as! MockSpeechOutput

        vm.currentInput = "Hello"
        await vm.send()
        vm.speakLastResponse()

        #expect(tts.isSpeaking == true)
        #expect(tts.lastSpokenText == "Hello world")
    }

    @Test("Messages persisted after send")
    func messagesPersisted() async throws {
        let (vm, _, persistence) = makeVM()
        let conv = try await persistence.createConversation(title: "Test")
        vm.conversationId = conv.id

        vm.currentInput = "Hello"
        await vm.send()

        let stored = try await persistence.messages(for: conv.id)
        #expect(stored.count == 2)
        #expect(stored[0].role == .user)
        #expect(stored[1].role == .assistant)
    }
}
