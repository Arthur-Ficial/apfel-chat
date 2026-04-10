import Foundation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    var temperature: Double?
    var maxTokens: Int? = AppDefaults.maxTokens
    var seed: Int? = AppDefaults.seed
    var jsonMode: Bool = AppDefaults.jsonMode
    var baseURL: String = AppDefaults.baseURL
    var modelName: String = AppDefaults.modelName
    var ttsLanguage: String = AppDefaults.ttsLanguage
    var autoSpeak: Bool = AppDefaults.autoSpeak
    var permissive: Bool = true   // pass --permissive to apfel (reduces false refusals)
    var showSettings: Bool = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func toModelSettings() -> ModelSettings {
        ModelSettings(temperature: temperature, maxTokens: maxTokens, seed: seed, jsonMode: jsonMode)
    }

    func save() {
        if let t = temperature { defaults.set(t, forKey: "ac_temperature") }
        else { defaults.removeObject(forKey: "ac_temperature") }
        if let m = maxTokens { defaults.set(m, forKey: "ac_maxTokens") }
        else { defaults.removeObject(forKey: "ac_maxTokens") }
        if let s = seed { defaults.set(s, forKey: "ac_seed") }
        else { defaults.removeObject(forKey: "ac_seed") }
        defaults.set(jsonMode, forKey: "ac_jsonMode")
        defaults.set(baseURL, forKey: "ac_baseURL")
        defaults.set(modelName, forKey: "ac_modelName")
        defaults.set(ttsLanguage, forKey: "ac_ttsLanguage")
        defaults.set(autoSpeak, forKey: "ac_autoSpeak")
        defaults.set(permissive, forKey: "ac_permissive")
    }

    func load() {
        if defaults.object(forKey: "ac_temperature") != nil {
            temperature = defaults.double(forKey: "ac_temperature")
        }
        if defaults.object(forKey: "ac_maxTokens") != nil {
            maxTokens = defaults.integer(forKey: "ac_maxTokens")
        }
        if defaults.object(forKey: "ac_seed") != nil {
            seed = defaults.integer(forKey: "ac_seed")
        }
        jsonMode = defaults.bool(forKey: "ac_jsonMode")
        if let url = defaults.string(forKey: "ac_baseURL"), !url.isEmpty { baseURL = url }
        if let model = defaults.string(forKey: "ac_modelName"), !model.isEmpty { modelName = model }
        if let lang = defaults.string(forKey: "ac_ttsLanguage"), !lang.isEmpty { ttsLanguage = lang }
        autoSpeak = defaults.bool(forKey: "ac_autoSpeak")
        // Default permissive = true; only override if explicitly set to false
        if defaults.object(forKey: "ac_permissive") != nil {
            permissive = defaults.bool(forKey: "ac_permissive")
        }
    }
}
