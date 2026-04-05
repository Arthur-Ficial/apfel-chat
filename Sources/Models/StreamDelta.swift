struct StreamDelta: Sendable {
    let text: String?
    let finishReason: String?
    let usage: TokenUsage?
}
