import Foundation

enum SSEParser {
    struct SSEError: Sendable {
        let message: String
        let type: String?
    }

    private struct ChunkResponse: Decodable {
        let id: String?
        let choices: [Choice]?
        let usage: UsageBlock?

        struct Choice: Decodable {
            let delta: Delta?
            let finish_reason: String?
        }
        struct Delta: Decodable {
            let content: String?
        }
        struct UsageBlock: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
            let total_tokens: Int
        }
    }

    private struct ErrorResponse: Decodable {
        let error: ErrorDetail
        struct ErrorDetail: Decodable {
            let message: String
            let type: String?
        }
    }

    static func parse(line: String) -> StreamDelta? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }

        if (try? JSONDecoder().decode(ErrorResponse.self, from: data)) != nil {
            return nil
        }

        guard let chunk = try? JSONDecoder().decode(ChunkResponse.self, from: data) else {
            return nil
        }

        if let usage = chunk.usage {
            return StreamDelta(
                text: nil, finishReason: nil,
                usage: TokenUsage(
                    promptTokens: usage.prompt_tokens,
                    completionTokens: usage.completion_tokens,
                    totalTokens: usage.total_tokens
                )
            )
        }

        if let choice = chunk.choices?.first {
            return StreamDelta(
                text: choice.delta?.content,
                finishReason: choice.finish_reason,
                usage: nil
            )
        }

        return nil
    }

    static func parseError(line: String) -> SSEError? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let errorResp = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return nil
        }
        return SSEError(message: errorResp.error.message, type: errorResp.error.type)
    }
}
