import Foundation

protocol ChatService: Sendable {
    func send(messages: [Message], settings: ModelSettings) -> AsyncThrowingStream<StreamDelta, Error>
    func healthCheck() async throws -> ServerHealth
}
