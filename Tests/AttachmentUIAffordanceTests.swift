// AttachmentUIAffordanceTests — regression test for issue #3
//
// When `auge` is not installed, `augeService` is nil. Previously, InputBar
// simply hid the paperclip button, which made users think the feature was
// removed. The correct UX is to always show the button and, when auge is
// missing, show an install hint on click.
//
// https://github.com/Arthur-Ficial/apfel-chat/issues/3

import Foundation
import Testing

@Suite("AttachmentUIAffordance")
struct AttachmentUIAffordanceTests {
    private static let inputBar: String = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // Tests/
        url.deleteLastPathComponent() // repo root
        url.appendPathComponent("Sources/Views/InputBar.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    @Test("InputBar does not hide the paperclip behind `if viewModel.augeService != nil`")
    func paperclipAlwaysVisible() {
        // This is the exact line that caused issue #3 — gating the button on
        // augeService being non-nil made the UI look like the feature was
        // ripped out. The fix shows it regardless and prompts on click.
        #expect(
            !Self.inputBar.contains("if viewModel.augeService != nil {"),
            "InputBar must not gate the paperclip button on augeService being non-nil; always render it and handle the nil case on click"
        )
    }

    @Test("InputBar still renders a paperclip button")
    func paperclipRendered() {
        #expect(
            Self.inputBar.contains("paperclip"),
            "InputBar must render a paperclip button so users can always see the attachment affordance"
        )
    }

    @Test("InputBar references install hint text when auge is missing")
    func installHintPresent() {
        // We expect the install hint to mention `brew install` and `auge`
        // so users know exactly how to get the feature.
        let hasHint = Self.inputBar.contains("brew install")
            && Self.inputBar.contains("auge")
        #expect(
            hasHint,
            "InputBar must reference how to install auge (brew install Arthur-Ficial/tap/auge) so users know how to unlock image analysis"
        )
    }
}
