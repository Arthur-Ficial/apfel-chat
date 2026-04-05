struct TokenUsage: Sendable, Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}
