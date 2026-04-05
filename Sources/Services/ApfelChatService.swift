import Foundation

final class ApfelChatService: ChatService, @unchecked Sendable {
    var baseURL: URL
    var modelName: String

    init(baseURL: URL, modelName: String = "apple-foundationmodel") {
        self.baseURL = baseURL
        self.modelName = modelName
    }

    init(port: Int, modelName: String = "apple-foundationmodel") {
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
            Task {
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

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: [DONE]") { break }
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
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: ChatServiceError.connectionFailed(
                            "Connection failed: \(error.localizedDescription)"
                        )
                    )
                }
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
