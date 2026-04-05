import Foundation
@testable import apfel_chat

@MainActor
final class MockSpeechInput: SpeechInput {
    var isListening = false
    var transcript = ""
    var errorMessage: String?
    var permissionGranted = true
    var mockTranscript = "Hello from voice"

    func requestPermissions() async -> Bool {
        permissionGranted
    }

    func startListening() {
        isListening = true
        transcript = mockTranscript
    }

    func stopListening() -> String {
        isListening = false
        return transcript
    }
}
