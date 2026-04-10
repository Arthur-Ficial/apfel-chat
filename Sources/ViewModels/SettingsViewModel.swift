import AppKit
import Foundation
import SwiftUI

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(newVersion: String)
    case installing(newVersion: String)
    case installed(newVersion: String)
    case error(message: String)
}

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
    var appearance: String = AppDefaults.appearance  // "system", "light", "dark"
    var showSettings: Bool = false

    var updateState: UpdateState = .idle
    var brewUpgradeOutput: String = ""

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var isHomebrewInstall: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/Caskroom/apfel-chat") ||
        FileManager.default.fileExists(atPath: "/usr/local/Caskroom/apfel-chat")
    }

    var resolvedColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Version comparison

    static func isVersionNewer(_ versionB: String, than versionA: String) -> Bool {
        let partsA = versionA.split(separator: ".").compactMap { Int($0) }
        let partsB = versionB.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let a = i < partsA.count ? partsA[i] : 0
            let b = i < partsB.count ? partsB[i] : 0
            if b != a { return b > a }
        }
        return false
    }

    // MARK: - Update check

    func checkForUpdate() async {
        guard updateState != .checking else { return }
        updateState = .checking
        brewUpgradeOutput = ""

        let url = URL(string: "https://api.github.com/repos/Arthur-Ficial/apfel-chat/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("apfel-chat/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                updateState = .error(message: "Unexpected response from GitHub")
                return
            }
            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            updateState = Self.isVersionNewer(latest, than: currentVersion)
                ? .updateAvailable(newVersion: latest)
                : .upToDate
        } catch {
            updateState = .error(message: "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Install update

    func installUpdate() {
        guard case .updateAvailable(let version) = updateState else { return }
        if isHomebrewInstall {
            runBrewUpgrade(version: version)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/Arthur-Ficial/apfel-chat/releases/latest")!)
        }
    }

    private func runBrewUpgrade(version: String) {
        updateState = .installing(newVersion: version)
        brewUpgradeOutput = "Running brew upgrade apfel-chat...\n"

        Task.detached { [weak self] in
            guard let self else { return }

            let brewPath: String
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
                brewPath = "/opt/homebrew/bin/brew"
            } else if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
                brewPath = "/usr/local/bin/brew"
            } else {
                await MainActor.run { self.updateState = .error(message: "brew not found") }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["upgrade", "apfel-chat"]
            process.environment = ProcessInfo.processInfo.environment
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            do { try process.run() } catch {
                await MainActor.run {
                    self.updateState = .error(message: "Failed to run brew: \(error.localizedDescription)")
                }
                return
            }

            process.waitUntilExit()
            let output = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "") +
                         (String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")

            await MainActor.run {
                self.brewUpgradeOutput = output.isEmpty ? "Done." : output
                if process.terminationStatus == 0 {
                    self.updateState = .installed(newVersion: version)
                } else {
                    self.updateState = .error(message: "brew upgrade failed (exit \(process.terminationStatus))")
                }
            }
        }
    }

    // MARK: - Relaunch

    func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open '\(bundlePath)'"]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Settings persistence

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
        defaults.set(appearance, forKey: "ac_appearance")
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
        if defaults.object(forKey: "ac_permissive") != nil {
            permissive = defaults.bool(forKey: "ac_permissive")
        }
        if let a = defaults.string(forKey: "ac_appearance"), !a.isEmpty { appearance = a }
    }
}
