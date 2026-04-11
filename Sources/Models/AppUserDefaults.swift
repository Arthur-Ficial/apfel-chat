import Foundation

enum AppUserDefaults {
    static let suiteEnvironmentKey = "APFEL_CHAT_DEFAULTS_SUITE"

    static func resolved() -> UserDefaults {
        if let suite = ProcessInfo.processInfo.environment[suiteEnvironmentKey],
           !suite.isEmpty,
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }
}
