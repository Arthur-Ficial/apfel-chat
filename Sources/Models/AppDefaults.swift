import Foundation

enum AppDefaults {
    static let temperature: Double = 0.7
    static let maxTokens: Int? = nil
    static let seed: Int? = nil
    static let jsonMode = false
    static let autoSpeak = false
    static let baseURL = "http://127.0.0.1:11440"
    static let modelName = "apple-foundationmodel"
    static let ttsLanguage = "en-US"
    static let serverPortStart = 11440
    static let apiPort: UInt16 = 11441
}
