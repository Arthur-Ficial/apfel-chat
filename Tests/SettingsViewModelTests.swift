import Testing
import Foundation
@testable import apfel_chat

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {

    @Test("Default values")
    func defaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm = SettingsViewModel(defaults: defaults)
        #expect(vm.temperature == nil)
        #expect(vm.maxTokens == nil)
        #expect(vm.seed == nil)
        #expect(vm.jsonMode == false)
        #expect(vm.baseURL == "http://127.0.0.1:11440")
        #expect(vm.modelName == "apple-foundationmodel")
        #expect(vm.ttsLanguage == "en-US")
        #expect(vm.autoSpeak == false)
    }

    @Test("toModelSettings converts correctly")
    func toModelSettings() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm = SettingsViewModel(defaults: defaults)
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
        let vm1 = SettingsViewModel(defaults: defaults)
        vm1.temperature = 0.5
        vm1.ttsLanguage = "de-DE"
        vm1.autoSpeak = true
        vm1.save()

        let vm2 = SettingsViewModel(defaults: defaults)
        #expect(vm2.temperature == 0.5)
        #expect(vm2.ttsLanguage == "de-DE")
        #expect(vm2.autoSpeak == true)
    }

    @Test("Default update state is idle")
    func defaultUpdateStateIsIdle() {
        let vm = SettingsViewModel(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
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
}
