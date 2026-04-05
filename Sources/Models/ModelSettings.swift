import Foundation

struct ModelSettings: Codable, Sendable, Equatable {
    var temperature: Double?
    var maxTokens: Int?
    var seed: Int?
    var jsonMode: Bool

    init(temperature: Double? = nil, maxTokens: Int? = nil, seed: Int? = nil, jsonMode: Bool = false) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.seed = seed
        self.jsonMode = jsonMode
    }
}
