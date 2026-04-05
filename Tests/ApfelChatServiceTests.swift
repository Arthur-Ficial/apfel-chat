import Testing
import Foundation
@testable import apfel_chat

@Suite("ApfelChatService")
struct ApfelChatServiceTests {

    @Test("Builds correct request body")
    func requestBody() throws {
        let service = ApfelChatService(baseURL: URL(string: "http://127.0.0.1:11440")!)
        let messages = [
            Message(conversationId: "c1", role: .system, content: "Be helpful"),
            Message(conversationId: "c1", role: .user, content: "Hello"),
        ]
        let settings = ModelSettings(temperature: 0.7, maxTokens: 1000)
        let request = service.buildRequest(messages: messages, settings: settings)

        #expect(request.model == "apple-foundationmodel")
        #expect(request.stream == true)
        #expect(request.messages.count == 2)
        #expect(request.messages[0].role == "system")
        #expect(request.messages[0].content == "Be helpful")
        #expect(request.messages[1].role == "user")
        #expect(request.messages[1].content == "Hello")
        #expect(request.temperature == 0.7)
        #expect(request.max_tokens == 1000)
    }

    @Test("Builds request with nil settings")
    func requestNilSettings() throws {
        let service = ApfelChatService(baseURL: URL(string: "http://127.0.0.1:11440")!)
        let messages = [Message(conversationId: "c1", role: .user, content: "Hi")]
        let settings = ModelSettings()
        let request = service.buildRequest(messages: messages, settings: settings)

        #expect(request.temperature == nil)
        #expect(request.max_tokens == nil)
        #expect(request.seed == nil)
        #expect(request.response_format == nil)
    }

    @Test("JSON mode sets response_format")
    func jsonMode() throws {
        let service = ApfelChatService(baseURL: URL(string: "http://127.0.0.1:11440")!)
        let messages = [Message(conversationId: "c1", role: .user, content: "Hi")]
        let settings = ModelSettings(jsonMode: true)
        let request = service.buildRequest(messages: messages, settings: settings)

        #expect(request.response_format?.type == "json_object")
    }

    @Test("User-facing error messages")
    func errorMessages() {
        #expect(ApfelChatService.userFacingError("guardrail triggered").contains("safety"))
        #expect(ApfelChatService.userFacingError("context length exceeded").contains("context"))
        #expect(ApfelChatService.userFacingError("rate limit reached").contains("Rate"))
        #expect(ApfelChatService.userFacingError("some unknown error") == "some unknown error")
    }
}
