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

// MARK: - Streaming lifecycle over a real loopback HTTP connection (#7)

/// Fails fast instead of hanging: a RED lifecycle test must not wait on URLSession's 60s timeout.
private func withDeadline<T: Sendable>(
    _ seconds: TimeInterval = 5,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DeadlineExceeded(seconds: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct DeadlineExceeded: Error, CustomStringConvertible {
    let seconds: TimeInterval
    var description: String { "operation did not finish within \(seconds)s" }
}

@Suite("ApfelChatService streaming lifecycle")
struct ApfelChatServiceStreamingTests {

    private static func chunk(_ text: String) -> String {
        #"{"choices":[{"delta":{"content":"\#(text)"},"finish_reason":null,"index":0}]}"#
    }
    private static let stopChunk = #"{"choices":[{"delta":{},"finish_reason":"stop","index":0}]}"#

    @Test("A stream that ends with [DONE] delivers every delta and finishes cleanly")
    func completeStream() async throws {
        let server = try FakeSSEServer(
            chunks: [Self.chunk("Hello"), Self.chunk(" world"), Self.stopChunk],
            ending: .done
        )
        let service = ApfelChatService(baseURL: server.baseURL)
        let messages = [Message(conversationId: "c1", role: .user, content: "Hi")]

        let (text, finishReason) = try await withDeadline {
            var text = ""
            var finishReason: String?
            for try await delta in service.send(messages: messages, settings: ModelSettings()) {
                if let t = delta.text { text += t }
                if let f = delta.finishReason { finishReason = f }
            }
            return (text, finishReason)
        }

        #expect(text == "Hello world")
        #expect(finishReason == "stop")
        #expect(server.receivedRequest.contains("POST /v1/chat/completions"))
    }

    @Test("A body that ends without [DONE] is surfaced as an error, not a finished answer")
    func truncatedStreamIsAnError() async throws {
        let server = try FakeSSEServer(
            chunks: [Self.chunk("Partial")],
            ending: .endWithoutDone
        )
        let service = ApfelChatService(baseURL: server.baseURL)
        let messages = [Message(conversationId: "c1", role: .user, content: "Hi")]

        let (text, thrown) = try await withDeadline { () -> (String, Error?) in
            var text = ""
            do {
                for try await delta in service.send(messages: messages, settings: ModelSettings()) {
                    if let t = delta.text { text += t }
                }
            } catch {
                return (text, error)
            }
            return (text, nil)
        }

        #expect(text == "Partial")
        let error = try #require(thrown as? ChatServiceError)
        guard case .streamError(let message) = error else {
            Issue.record("expected streamError, got \(error)")
            return
        }
        #expect(message.lowercased().contains("before it"))
    }

    @Test("Cancelling the consumer cancels the HTTP request instead of orphaning it")
    func cancelPropagatesToNetwork() async throws {
        let server = try FakeSSEServer(
            chunks: [Self.chunk("First"), Self.chunk(" second")],
            ending: .hangUntilClientCloses
        )
        let service = ApfelChatService(baseURL: server.baseURL)
        let messages = [Message(conversationId: "c1", role: .user, content: "Hi")]

        let gotFirstDelta = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var received = 0
            do {
                for try await delta in service.send(messages: messages, settings: ModelSettings()) {
                    if delta.text != nil {
                        received += 1
                        if received == 1 { gotFirstDelta.continuation.yield(()) }
                    }
                }
            } catch {
                // Cancellation may surface as an error or as a clean end; both are fine here.
            }
        }

        try await withDeadline {
            var iterator = gotFirstDelta.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        consumer.cancel()
        try await withDeadline { _ = await consumer.value }

        let closed = await Task.detached { server.waitForClientDisconnect(timeout: 3) }.value
        #expect(closed, "server still saw an open connection 3s after the consumer cancelled")
    }
}
