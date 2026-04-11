import Testing
import Foundation
@testable import apfel_chat

@Suite("ChatControlServer")
@MainActor
struct ChatControlServerTests {

    private struct StubInstallLocator: InstallLocating {
        let isHomebrewInstall: Bool
    }

    private final class MockUpdateChecker: UpdateChecking {
        var latestVersion: String = "1.0.0"

        func fetchLatestRelease(currentVersion: String) async throws -> LatestReleaseInfo {
            LatestReleaseInfo(version: latestVersion)
        }
    }

    private func makeDependencies(defaults: UserDefaults) -> (ChatViewModel, ConversationListViewModel, SettingsViewModel) {
        let chatVM = ChatViewModel(
            chatService: MockChatService(),
            persistence: MockPersistence(),
            speechInput: MockSpeechInput(),
            speechOutput: MockSpeechOutput()
        )
        let listVM = ConversationListViewModel(persistence: MockPersistence())
        let settingsVM = SettingsViewModel(
            defaults: defaults,
            updateChecker: MockUpdateChecker(),
            currentVersionProvider: { "1.0.0" },
            installLocator: StubInstallLocator(isHomebrewInstall: false)
        )
        return (chatVM, listVM, settingsVM)
    }

    @Test("Settings endpoint includes launch update toggle")
    func settingsEndpointIncludesLaunchToggle() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("1.0.0", forKey: "ac_lastSeenWelcomeVersion")
        let (chatVM, listVM, settingsVM) = makeDependencies(defaults: defaults)

        let response = await ChatControlServer.dispatch(
            method: "GET",
            path: "/settings",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        let object = try #require(Self.decodeJSON(response))
        #expect(object["check_updates_on_launch"] as? Bool == true)
        #expect(object["show_welcome_on_next_start"] as? Bool == false)
    }

    @Test("Welcome endpoints show and dismiss overlay state")
    func welcomeEndpointsControlOverlay() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let (chatVM, listVM, settingsVM) = makeDependencies(defaults: defaults)

        await settingsVM.prepareForAppLaunch()

        let initial = await ChatControlServer.dispatch(
            method: "GET",
            path: "/welcome",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )
        let initialObject = try #require(Self.decodeJSON(initial))
        #expect(initialObject["visible"] as? Bool == true)
        #expect(initialObject["has_seen"] as? Bool == false)
        #expect(initialObject["last_seen_version"] as? String == "")

        _ = await ChatControlServer.dispatch(
            method: "POST",
            path: "/welcome/dismiss",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        let afterDismiss = await ChatControlServer.dispatch(
            method: "GET",
            path: "/welcome",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )
        let dismissedObject = try #require(Self.decodeJSON(afterDismiss))
        #expect(dismissedObject["visible"] as? Bool == false)
        #expect(dismissedObject["has_seen"] as? Bool == true)
        #expect(dismissedObject["last_seen_version"] as? String == "1.0.0")

        _ = await ChatControlServer.dispatch(
            method: "POST",
            path: "/welcome/show",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        let afterShow = await ChatControlServer.dispatch(
            method: "GET",
            path: "/welcome",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )
        let shownObject = try #require(Self.decodeJSON(afterShow))
        #expect(shownObject["visible"] as? Bool == true)
        #expect(shownObject["has_seen"] as? Bool == true)
    }

    #if DEBUG
    @Test("Debug reset first run clears welcome seen version")
    func debugResetFirstRun() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("1.0.0", forKey: "ac_lastSeenWelcomeVersion")
        let (chatVM, listVM, settingsVM) = makeDependencies(defaults: defaults)

        _ = await ChatControlServer.dispatch(
            method: "POST",
            path: "/debug/reset-first-run",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        #expect(settingsVM.showStartupOverlay == true)
        #expect(settingsVM.lastSeenWelcomeVersion == "")
    }

    @Test("Debug update scenario endpoint drives update status")
    func debugUpdateScenarioEndpoint() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let (chatVM, listVM, settingsVM) = makeDependencies(defaults: defaults)

        _ = await ChatControlServer.dispatch(
            method: "POST",
            path: "/debug/update-scenario",
            queryString: "",
            body: #"{"latest_version":"1.2.0"}"#,
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        _ = await ChatControlServer.dispatch(
            method: "POST",
            path: "/update/check",
            queryString: "",
            body: "",
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        #expect(settingsVM.updateState == .updateAvailable(newVersion: "1.2.0"))
    }
    #endif

    private static func decodeJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}
