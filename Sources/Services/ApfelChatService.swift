import Foundation

final class ApfelChatService: ChatService, @unchecked Sendable {
    var baseURL: URL
    var modelName: String

    init(baseURL: URL, modelName: String = AppDefaults.modelName) {
        self.baseURL = baseURL
        self.modelName = modelName
    }

    init(port: Int, modelName: String = AppDefaults.modelName) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.modelName = modelName
    }

    struct ChatRequest: Encodable {
        let model: String
        let messages: [RequestMessage]
        let stream: Bool
        let temperature: Double?
        let max_tokens: Int?
        let seed: Int?
        let response_format: ResponseFormat?

        struct RequestMessage: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable {
            let type: String
        }
    }

    func buildRequest(messages: [Message], settings: ModelSettings) -> ChatRequest {
        let apiMessages = messages.map {
            ChatRequest.RequestMessage(role: $0.role.rawValue, content: $0.content)
        }
        return ChatRequest(
            model: modelName,
            messages: apiMessages,
            stream: true,
            temperature: settings.temperature,
            max_tokens: settings.maxTokens,
            seed: settings.seed,
            response_format: settings.jsonMode ? .init(type: "json_object") : nil
        )
    }

    func send(messages: [Message], settings: ModelSettings) -> AsyncThrowingStream<StreamDelta, Error> {
        let request = buildRequest(messages: messages, settings: settings)
        let url = URL(string: "/v1/chat/completions", relativeTo: baseURL)!

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, httpResponse) = try await URLSession.shared.bytes(for: urlRequest)

                    if let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode,
                       statusCode >= 400 {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.finish(
                            throwing: ChatServiceError.serverError(
                                Self.userFacingError(errorText)
                            )
                        )
                        return
                    }

                    var sawDone = false
                    for try await line in bytes.lines {
                        if sawDone { continue }
                        if line.hasPrefix("data: [DONE]") {
                            // The answer is complete for the consumer. Keep draining to EOF
                            // instead of breaking out: dropping the byte stream mid-body makes
                            // URLSession cancel the task and log NSURLErrorCancelled (-999)
                            // for every successful response (#7).
                            sawDone = true
                            continuation.finish()
                            continue
                        }
                        if let error = SSEParser.parseError(line: line) {
                            continuation.finish(
                                throwing: ChatServiceError.streamError(
                                    Self.userFacingError(error.message)
                                )
                            )
                            return
                        }
                        if let delta = SSEParser.parse(line: line) {
                            continuation.yield(delta)
                        }
                    }

                    if !sawDone {
                        // The body ended without the [DONE] terminator: whatever was
                        // streamed so far is partial. Say so instead of presenting it
                        // as a finished answer.
                        continuation.finish(
                            throwing: ChatServiceError.streamError(
                                "The response ended before it was complete. Try again."
                            )
                        )
                    }
                } catch is CancellationError {
                    // The consumer stopped listening; nothing left to report to.
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(
                        throwing: ChatServiceError.streamError(
                            "The response stream was cancelled before it finished."
                        )
                    )
                } catch {
                    continuation.finish(
                        throwing: ChatServiceError.connectionFailed(
                            "Connection failed: \(error.localizedDescription)"
                        )
                    )
                }
            }
            // Only a consumer-side cancellation (Stop button, switching conversation)
            // tears down the request. A normal finish must NOT cancel, or the drain
            // above would trigger the very -999 it exists to avoid.
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    func healthCheck() async throws -> ServerHealth {
        let url = URL(string: "/health", relativeTo: baseURL)!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ChatServiceError.connectionFailed("Server returned non-200 status")
        }
        return try JSONDecoder().decode(ServerHealth.self, from: data)
    }

    static func userFacingError(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("guardrail") || lowered.contains("safety") {
            return "Content blocked by on-device safety filters. Try rephrasing."
        }
        if lowered.contains("context") && lowered.contains("exceed") {
            return "Input exceeds the context window. Shorten your conversation or start a new chat."
        }
        if lowered.contains("rate limit") {
            return "Rate limited. Wait a moment and try again."
        }
        if lowered.contains("concurrent") || lowered.contains("capacity") {
            return "Server at max capacity. Try again in a moment."
        }
        return raw
    }
}
