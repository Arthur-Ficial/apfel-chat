import Foundation
@testable import apfel_chat

@MainActor
final class MockSpeechOutput: SpeechOutput {
    var isSpeaking = false
    var lastSpokenText: String?
    var lastLanguageCode: String?

    func speak(_ text: String, languageCode: String) {
        isSpeaking = true
        lastSpokenText = text
        lastLanguageCode = languageCode
    }

    func stop() {
        isSpeaking = false
    }
}
