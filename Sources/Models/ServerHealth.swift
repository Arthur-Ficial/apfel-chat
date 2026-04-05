import Foundation

struct ServerHealth: Codable, Sendable {
    let status: String
    let version: String?
    let contextWindow: Int?
    let modelAvailable: Bool
    let supportedLanguages: [String]?

    enum CodingKeys: String, CodingKey {
        case status, version
        case contextWindow = "context_window"
        case modelAvailable = "model_available"
        case supportedLanguages = "supported_languages"
    }
}
