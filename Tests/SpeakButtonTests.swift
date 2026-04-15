// SpeakButtonTests — per-message speak affordance
//
// Every assistant response must render a mini speaker icon in its
// metadata row so users can click to have that specific message read
// aloud. Previously, only an auto-speak toggle and a global "speak last"
// command existed — neither exposed a per-message control.

import Foundation
import Testing

@Suite("SpeakButton")
struct SpeakButtonTests {
    private static func source(_ relative: String) -> String {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // Tests/
        url.deleteLastPathComponent() // repo root
        url.appendPathComponent(relative)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("MessageBubble exposes an onSpeak closure parameter")
    func onSpeakParameter() {
        let src = Self.source("Sources/Views/MessageBubble.swift")
        #expect(
            src.contains("onSpeak"),
            "MessageBubble must accept an onSpeak callback so each message can render its own speaker control"
        )
    }

    @Test("MessageBubble renders a speaker.wave icon button when onSpeak is set")
    func speakerIconRendered() {
        let src = Self.source("Sources/Views/MessageBubble.swift")
        #expect(
            src.contains("speaker.wave"),
            "MessageBubble must render a 'speaker.wave' SF symbol icon as the speak button"
        )
    }

    @Test("ChatViewModel exposes toggleSpeak(for:) for per-message control")
    func toggleSpeakExists() {
        let src = Self.source("Sources/ViewModels/ChatViewModel.swift")
        #expect(
            src.contains("func toggleSpeak(for message: Message)"),
            "ChatViewModel must expose toggleSpeak(for:) so each MessageBubble can speak or stop its own content"
        )
    }

    @Test("ChatView passes the per-message speak closure to MessageBubble")
    func chatViewWiresSpeak() {
        let src = Self.source("Sources/Views/ChatView.swift")
        #expect(
            src.contains("onSpeak:"),
            "ChatView must pass an onSpeak closure to each MessageBubble (wired to viewModel.toggleSpeak(for:))"
        )
    }
}
