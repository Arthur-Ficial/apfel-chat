import Foundation
@testable import apfel_chat

final class MockChatService: ChatService, @unchecked Sendable {
    var healthResult: ServerHealth = ServerHealth(
        status: "ok", version: "0.8.1", contextWindow: 4096,
        modelAvailable: true, supportedLanguages: ["en"]
    )
    var streamResponses: [String] = ["Hello", " world"]
    var shouldError: Bool = false
    var sendCallCount = 0
    var lastMessages: [Message] = []
    var lastSettings: ModelSettings?

    func send(messages: [Message], settings: ModelSettings) -> AsyncThrowingStream<StreamDelta, Error> {
        sendCallCount += 1
        lastMessages = messages
        lastSettings = settings
        let responses = streamResponses
        let shouldError = shouldError
        return AsyncThrowingStream { continuation in
            if shouldError {
                continuation.finish(throwing: ChatServiceError.serverError("Mock error"))
                return
            }
            for text in responses {
                continuation.yield(StreamDelta(text: text, finishReason: nil, usage: nil))
            }
            continuation.yield(StreamDelta(
                text: nil,
                finishReason: "stop",
                usage: TokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
            ))
            continuation.finish()
        }
    }

    func healthCheck() async throws -> ServerHealth {
        if shouldError {
            throw ChatServiceError.connectionFailed("Mock connection failed")
        }
        return healthResult
    }
}
