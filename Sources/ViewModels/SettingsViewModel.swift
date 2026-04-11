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

enum UpdateCheckMode {
    case manual
    case automaticLaunch
}

#if DEBUG
enum DebugUpdateScenario: Equatable {
    case latestVersion(String)
    case error(String)
}
#endif

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
    var permissive: Bool = true
    var appearance: String = AppDefaults.appearance
    var showSettings: Bool = false
    var showStartupOverlay: Bool = false
    var checkUpdatesOnLaunch: Bool = true

    private(set) var lastSeenWelcomeVersion: String = ""
    private(set) var lastLaunchedVersion: String?

    var updateState: UpdateState = .idle
    var brewUpgradeOutput: String = ""

    #if DEBUG
    var debugUpdateScenario: DebugUpdateScenario?
    #endif

    var currentVersion: String {
        currentVersionProvider()
    }

    var isHomebrewInstall: Bool {
        installLocator.isHomebrewInstall
    }

    var resolvedColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var updateInstallButtonTitle: String {
        isHomebrewInstall ? "Install" : "Download"
    }

    var hasSeenStartupOverlay: Bool {
        !lastSeenWelcomeVersion.isEmpty
    }

    var showWelcomeOnNextStart: Bool {
        get { lastSeenWelcomeVersion.isEmpty }
        set { lastSeenWelcomeVersion = newValue ? "" : currentVersion }
    }

    private let defaults: UserDefaults
    private let updateChecker: any UpdateChecking
    private let currentVersionProvider: () -> String
    private let installLocator: any InstallLocating

    init(
        defaults: UserDefaults = AppUserDefaults.resolved(),
        updateChecker: any UpdateChecking = GitHubReleaseUpdateChecker(),
        currentVersionProvider: @escaping () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        },
        installLocator: any InstallLocating = DefaultInstallLocator()
    ) {
        self.defaults = defaults
        self.updateChecker = updateChecker
        self.currentVersionProvider = currentVersionProvider
        self.installLocator = installLocator
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

    // MARK: - Startup flow

    func prepareForAppLaunch() async {
        recordLaunchVersion()

        if !hasSeenStartupOverlay {
            showStartupOverlay = true
            return
        }

        guard checkUpdatesOnLaunch else { return }
        await checkForUpdate(mode: .automaticLaunch)
    }

    func showStartupOverlayManually() {
        showStartupOverlay = true
    }

    func dismissStartupOverlay() async {
        showStartupOverlay = false
        lastSeenWelcomeVersion = currentVersion
        save()

        guard checkUpdatesOnLaunch else { return }
        await checkForUpdate(mode: .automaticLaunch)
    }

    func debugResetFirstRun() async {
        lastSeenWelcomeVersion = ""
        save()
        showStartupOverlay = true
    }

    // MARK: - Update check

    func checkForUpdate(mode: UpdateCheckMode = .manual) async {
        guard updateState != .checking else { return }

        if mode == .manual {
            updateState = .checking
            brewUpgradeOutput = ""
        }

        do {
            let latest = try await resolveLatestVersion()
            let hasUpdate = Self.isVersionNewer(latest, than: currentVersion)

            switch mode {
            case .manual:
                updateState = hasUpdate ? .updateAvailable(newVersion: latest) : .upToDate
            case .automaticLaunch:
                if hasUpdate {
                    updateState = .updateAvailable(newVersion: latest)
                }
            }
        } catch {
            guard mode == .manual else { return }
            updateState = .error(message: userFacingUpdateError(error))
        }
    }

    private func resolveLatestVersion() async throws -> String {
        #if DEBUG
        if let debugUpdateScenario {
            switch debugUpdateScenario {
            case .latestVersion(let version):
                return version
            case .error(let message):
                throw NSError(domain: "apfel-chat.debug-update", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
            }
        }
        #endif

        let release = try await updateChecker.fetchLatestRelease(currentVersion: currentVersion)
        return release.version
    }

    private func userFacingUpdateError(_ error: Error) -> String {
        if let updateError = error as? UpdateCheckerError,
           let description = updateError.errorDescription {
            return description
        }
        return "Network error: \(error.localizedDescription)"
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
        process.arguments = ["-c", "(while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open '\(bundlePath)') &"]
        try? process.run()
        Thread.sleep(forTimeInterval: 0.15)
        exit(0)
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
        defaults.set(checkUpdatesOnLaunch, forKey: "ac_checkUpdatesOnLaunch")
        defaults.set(lastSeenWelcomeVersion, forKey: "ac_lastSeenWelcomeVersion")
        defaults.removeObject(forKey: "ac_showWelcomeOnNextStart")
        defaults.removeObject(forKey: "ac_hasSeenWelcomeOverlay")
        if let lastLaunchedVersion {
            defaults.set(lastLaunchedVersion, forKey: "ac_lastLaunchedVersion")
        }
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
        if defaults.object(forKey: "ac_checkUpdatesOnLaunch") != nil {
            checkUpdatesOnLaunch = defaults.bool(forKey: "ac_checkUpdatesOnLaunch")
        }
        if let lastSeen = defaults.string(forKey: "ac_lastSeenWelcomeVersion") {
            lastSeenWelcomeVersion = lastSeen
        } else if defaults.object(forKey: "ac_showWelcomeOnNextStart") != nil {
            if defaults.bool(forKey: "ac_showWelcomeOnNextStart") {
                lastSeenWelcomeVersion = ""
            } else if defaults.bool(forKey: "ac_hasSeenWelcomeOverlay") {
                lastSeenWelcomeVersion = defaults.string(forKey: "ac_lastLaunchedVersion") ?? currentVersion
            } else {
                lastSeenWelcomeVersion = ""
            }
        } else if defaults.object(forKey: "ac_hasSeenWelcomeOverlay") != nil {
            if defaults.bool(forKey: "ac_hasSeenWelcomeOverlay") {
                lastSeenWelcomeVersion = defaults.string(forKey: "ac_lastLaunchedVersion") ?? currentVersion
            } else {
                lastSeenWelcomeVersion = ""
            }
        }
        lastLaunchedVersion = defaults.string(forKey: "ac_lastLaunchedVersion")
    }

    private func recordLaunchVersion() {
        lastLaunchedVersion = currentVersion
        defaults.set(currentVersion, forKey: "ac_lastLaunchedVersion")
    }
}
