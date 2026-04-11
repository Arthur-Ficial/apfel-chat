import Foundation

enum StartupWelcomeContent {
    static let title = "Welcome to apfel-chat"
    static let subtitle = "Private AI chat. Fast. Local."
    static let summary = "A full AI chat app that runs entirely on your Mac. Multi-conversation history, voice input, image analysis, markdown rendering. Apple's on-device model. No API keys. No data ever leaves your machine."
    static let engineSummary = "Powered by apfel, the on-device AI engine built on top of Apple Intelligence."
    static let bullets = [
        "Works offline, even in airplane mode",
        "Everything runs on your device. No network calls. No data leaves your Mac.",
        "No account, no sign-up, no monthly bill"
    ]

    static let appURL = URL(string: "https://apfel-chat.franzai.com/")!
    static let engineURL = URL(string: "https://apfel.franzai.com/")!
}
