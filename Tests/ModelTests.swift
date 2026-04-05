import Testing
import Foundation
@testable import apfel_chat

@Suite("Data Models")
struct ModelTests {

    @Test("Conversation roundtrips through JSON")
    func conversationCodable() throws {
        let conv = Conversation(
            id: "test-123",
            title: "Hello World",
            systemPrompt: "You are helpful",
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000),
            modelSettings: ModelSettings(temperature: 0.7, maxTokens: 1000, seed: nil, jsonMode: false)
        )
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        #expect(decoded.id == "test-123")
        #expect(decoded.title == "Hello World")
        #expect(decoded.systemPrompt == "You are helpful")
        #expect(decoded.modelSettings?.temperature == 0.7)
        #expect(decoded.modelSettings?.maxTokens == 1000)
    }

    @Test("Message roundtrips through JSON")
    func messageCodable() throws {
        let msg = Message(
            id: "msg-1",
            conversationId: "conv-1",
            role: .user,
            content: "Hello",
            timestamp: Date(timeIntervalSince1970: 1000),
            tokenCount: 5,
            durationMs: nil,
            isStreaming: false
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.id == "msg-1")
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello")
        #expect(decoded.tokenCount == 5)
    }

    @Test("ModelSettings defaults are nil")
    func modelSettingsDefaults() {
        let settings = ModelSettings()
        #expect(settings.temperature == nil)
        #expect(settings.maxTokens == nil)
        #expect(settings.seed == nil)
        #expect(settings.jsonMode == false)
    }

    @Test("ServerHealth decodes from JSON")
    func serverHealthDecoding() throws {
        let json = """
        {"status":"ok","version":"0.8.1","context_window":4096,"model_available":true,"supported_languages":["en","de"]}
        """
        let data = json.data(using: .utf8)!
        let health = try JSONDecoder().decode(ServerHealth.self, from: data)
        #expect(health.status == "ok")
        #expect(health.version == "0.8.1")
        #expect(health.contextWindow == 4096)
        #expect(health.modelAvailable == true)
        #expect(health.supportedLanguages == ["en", "de"])
    }

    @Test("Role raw values match API")
    func roleRawValues() {
        #expect(Role.user.rawValue == "user")
        #expect(Role.assistant.rawValue == "assistant")
        #expect(Role.system.rawValue == "system")
    }
}
