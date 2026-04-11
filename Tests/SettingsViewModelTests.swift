import Testing
import Foundation
@testable import apfel_chat

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {

    private struct StubInstallLocator: InstallLocating {
        let isHomebrewInstall: Bool
    }

    private final class MockUpdateChecker: UpdateChecking {
        var latestVersion: String = "1.0.0"
        var error: Error?
        private(set) var callCount = 0
        private(set) var lastRequestedVersion: String?

        func fetchLatestRelease(currentVersion: String) async throws -> LatestReleaseInfo {
            callCount += 1
            lastRequestedVersion = currentVersion
            if let error {
                throw error
            }
            return LatestReleaseInfo(version: latestVersion)
        }
    }

    private struct StubError: LocalizedError {
        var errorDescription: String? { "offline" }
    }

    @Test("Default values")
    func defaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        #expect(vm.temperature == nil)
        #expect(vm.maxTokens == nil)
        #expect(vm.seed == nil)
        #expect(vm.jsonMode == false)
        #expect(vm.baseURL == "http://127.0.0.1:11440")
        #expect(vm.modelName == "apple-foundationmodel")
        #expect(vm.ttsLanguage == "en-US")
        #expect(vm.autoSpeak == false)
        #expect(vm.checkUpdatesOnLaunch == true)
        #expect(vm.lastSeenWelcomeVersion == "")
        #expect(vm.showWelcomeOnNextStart == true)
    }

    @Test("toModelSettings converts correctly")
    func toModelSettings() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        vm.temperature = 0.7
        vm.maxTokens = 1000
        vm.jsonMode = true
        let settings = vm.toModelSettings()
        #expect(settings.temperature == 0.7)
        #expect(settings.maxTokens == 1000)
        #expect(settings.jsonMode == true)
    }

    @Test("Saves and restores from UserDefaults")
    func persistence() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let vm1 = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        vm1.temperature = 0.5
        vm1.ttsLanguage = "de-DE"
        vm1.autoSpeak = true
        vm1.checkUpdatesOnLaunch = false
        vm1.showWelcomeOnNextStart = false
        vm1.save()

        let vm2 = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        #expect(vm2.temperature == 0.5)
        #expect(vm2.ttsLanguage == "de-DE")
        #expect(vm2.autoSpeak == true)
        #expect(vm2.checkUpdatesOnLaunch == false)
        #expect(vm2.showWelcomeOnNextStart == false)
        #expect(vm2.lastSeenWelcomeVersion == "1.0.0")
    }

    @Test("Default update state is idle")
    func defaultUpdateStateIsIdle() {
        let vm = SettingsViewModel(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        #expect(vm.updateState == .idle)
    }

    @Test("isVersionNewer: patch update")
    func versionNewerPatch() {
        #expect(SettingsViewModel.isVersionNewer("1.1.6", than: "1.1.5") == true)
        #expect(SettingsViewModel.isVersionNewer("1.1.5", than: "1.1.5") == false)
        #expect(SettingsViewModel.isVersionNewer("1.1.4", than: "1.1.5") == false)
    }

    @Test("isVersionNewer: semver-aware minor (1.10.0 > 1.9.0)")
    func versionNewerMinorSemver() {
        #expect(SettingsViewModel.isVersionNewer("1.10.0", than: "1.9.0") == true)
        #expect(SettingsViewModel.isVersionNewer("1.9.0", than: "1.10.0") == false)
    }

    @Test("isVersionNewer: major bump")
    func versionNewerMajor() {
        #expect(SettingsViewModel.isVersionNewer("2.0.0", than: "1.99.99") == true)
        #expect(SettingsViewModel.isVersionNewer("1.0.0", than: "2.0.0") == false)
    }

    @Test("First launch shows startup overlay and delays update check")
    func firstLaunchShowsStartupOverlay() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let checker = MockUpdateChecker()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.prepareForAppLaunch()

        #expect(vm.showStartupOverlay == true)
        #expect(checker.callCount == 0)
        #expect(vm.lastLaunchedVersion == "1.0.0")
    }

    @Test("Dismissing startup overlay saves last seen welcome version")
    func dismissStartupOverlayPersistsState() async {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let checker = MockUpdateChecker()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.prepareForAppLaunch()
        vm.checkUpdatesOnLaunch = false
        await vm.dismissStartupOverlay()

        let restored = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        #expect(restored.hasSeenStartupOverlay == true)
        #expect(restored.checkUpdatesOnLaunch == false)
        #expect(restored.showStartupOverlay == false)
        #expect(restored.lastSeenWelcomeVersion == "1.0.0")
        #expect(checker.callCount == 0)
    }

    @Test("Launch update check is skipped when toggle is off")
    func launchCheckSkippedWhenDisabled() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("1.0.0", forKey: "ac_lastSeenWelcomeVersion")
        defaults.set(false, forKey: "ac_checkUpdatesOnLaunch")
        let checker = MockUpdateChecker()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.prepareForAppLaunch()

        #expect(vm.showStartupOverlay == false)
        #expect(checker.callCount == 0)
        #expect(vm.updateState == .idle)
    }

    @Test("Show welcome on next start reopens overlay once")
    func showWelcomeOnNextStartReopensOverlay() async {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let checker = MockUpdateChecker()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        vm.showWelcomeOnNextStart = false
        vm.save()

        let restoredBeforeLaunch = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        #expect(restoredBeforeLaunch.showWelcomeOnNextStart == false)

        restoredBeforeLaunch.showWelcomeOnNextStart = true
        restoredBeforeLaunch.save()

        let relaunchVM = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await relaunchVM.prepareForAppLaunch()

        #expect(relaunchVM.showStartupOverlay == true)
        #expect(relaunchVM.showWelcomeOnNextStart == true)
        #expect(checker.callCount == 0)

        await relaunchVM.dismissStartupOverlay()

        let restored = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        #expect(restored.showWelcomeOnNextStart == false)
        #expect(restored.lastSeenWelcomeVersion == "1.0.0")
    }

    @Test("Welcome stays hidden after update when last seen version is older")
    func hiddenAfterVersionChange() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("0.9.0", forKey: "ac_lastSeenWelcomeVersion")
        let checker = MockUpdateChecker()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.prepareForAppLaunch()

        #expect(vm.showStartupOverlay == false)
    }

    @Test("Launch update check stays quiet when offline")
    func launchCheckOfflineIsSilent() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("1.0.0", forKey: "ac_lastSeenWelcomeVersion")
        let checker = MockUpdateChecker()
        checker.error = StubError()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.prepareForAppLaunch()

        #expect(checker.callCount == 1)
        #expect(vm.updateState == .idle)
    }

    @Test("Launch update check only surfaces update available")
    func launchCheckShowsUpdateAvailableOnly() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("1.0.0", forKey: "ac_lastSeenWelcomeVersion")
        let checker = MockUpdateChecker()
        checker.latestVersion = "1.1.0"
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.prepareForAppLaunch()

        #expect(vm.updateState == .updateAvailable(newVersion: "1.1.0"))
    }

    @Test("Manual update check still shows errors")
    func manualUpdateCheckShowsErrors() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let checker = MockUpdateChecker()
        checker.error = StubError()
        let vm = SettingsViewModel(
            defaults: defaults,
            updateChecker: checker,
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )

        await vm.checkForUpdate(mode: .manual)

        switch vm.updateState {
        case .error(let message):
            #expect(message.contains("offline"))
        default:
            Issue.record("Expected manual update check to surface an error")
        }
    }
}
