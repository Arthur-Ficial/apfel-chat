import Foundation
import AppKit

@MainActor
class ChatControlServer {
    let chatVM: ChatViewModel
    let listVM: ConversationListViewModel
    let settingsVM: SettingsViewModel
    private var serverTask: Task<Void, Never>?

    static nonisolated let port: UInt16 = AppDefaults.apiPort

    init(chatVM: ChatViewModel, listVM: ConversationListViewModel, settingsVM: SettingsViewModel) {
        self.chatVM = chatVM
        self.listVM = listVM
        self.settingsVM = settingsVM
    }

    func start() {
        let chat = chatVM
        let list = listVM
        let settings = settingsVM
        let p = Self.port
        serverTask = Task.detached {
            guard let listener = createControlListenerSocket(port: p) else {
                printToStderr("API: failed to start on port \(p)")
                return
            }
            printToStderr("API: http://127.0.0.1:\(p)")

            while true {
                guard let client = try? await acceptControlSocket(listener) else { continue }
                Task.detached {
                    await Self.handleConnection(client, chatVM: chat, listVM: list, settingsVM: settings)
                }
            }
        }
    }

    nonisolated private static func handleConnection(_ client: Int32, chatVM: ChatViewModel, listVM: ConversationListViewModel, settingsVM: SettingsViewModel) async {
        var buffer = [UInt8](repeating: 0, count: 16384)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { close(client); return }
        let request = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""

        let firstLine = request.split(separator: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { close(client); return }
        let method = String(parts[0])
        let fullPath = String(parts[1])

        // Parse path and query
        let pathComponents = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(pathComponents[0])
        let queryString = pathComponents.count > 1 ? String(pathComponents[1]) : ""

        let body: String
        if let bodyStart = request.range(of: "\r\n\r\n") {
            body = String(request[bodyStart.upperBound...])
        } else {
            body = ""
        }

        let response = await dispatch(
            method: method,
            path: path,
            queryString: queryString,
            body: body,
            chatVM: chatVM,
            listVM: listVM,
            settingsVM: settingsVM
        )

        let http = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: \(response.utf8.count)\r\n\r\n\(response)"
        _ = http.withCString { write(client, $0, Int(strlen($0))) }
        close(client)
    }

    static func dispatch(
        method: String,
        path: String,
        queryString: String,
        body: String,
        chatVM: ChatViewModel,
        listVM: ConversationListViewModel,
        settingsVM: SettingsViewModel
    ) async -> String {
        switch (method, path) {

        // === STATE ===
        case ("GET", "/state"):
            return await getState(chatVM, listVM: listVM)

        // === CONVERSATIONS ===
        case ("GET", "/conversations"):
            if let id = parseQuery(queryString)["id"] {
                return await getMessages(chatVM, listVM: listVM, conversationId: id)
            } else {
                return await listConversations(listVM)
            }
        case ("POST", "/conversations"):
            return await createConversation(listVM)
        case ("POST", "/conversations/rename"):
            return await renameConversation(body, listVM: listVM)
        case ("POST", "/conversations/delete"):
            return await deleteConversation(body, listVM: listVM)
        case ("POST", "/conversations/select"):
            return await selectConversation(body, chatVM: chatVM, listVM: listVM)

        // === CHAT ===
        case ("POST", "/send"):
            return await sendMessage(body, chatVM: chatVM)
        case ("POST", "/clear"):
            await MainActor.run { chatVM.clear() }
            return ok()
        case ("POST", "/system-prompt"):
            return await setSystemPrompt(body, chatVM: chatVM)

        // === SETTINGS ===
        case ("GET", "/settings"):
            return await getSettings(settingsVM)
        case ("POST", "/settings"):
            return await updateSettings(body, settingsVM: settingsVM)
        case ("POST", "/settings/show"):
            await MainActor.run { settingsVM.showSettings = true }
            return ok()
        case ("POST", "/settings/hide"):
            await MainActor.run { settingsVM.showSettings = false }
            return ok()

        // === STARTUP ===
        case ("GET", "/startup"):
            return await getStartupStatus(settingsVM)
        case ("GET", "/welcome"):
            return await getStartupStatus(settingsVM)
        case ("POST", "/startup/show"):
            await MainActor.run { settingsVM.showStartupOverlayManually() }
            return await getStartupStatus(settingsVM)
        case ("POST", "/welcome/show"):
            await MainActor.run { settingsVM.showStartupOverlayManually() }
            return await getStartupStatus(settingsVM)
        case ("POST", "/startup/dismiss"):
            await settingsVM.dismissStartupOverlay()
            return await getStartupStatus(settingsVM)
        case ("POST", "/welcome/dismiss"):
            await settingsVM.dismissStartupOverlay()
            return await getStartupStatus(settingsVM)

        // === INPUT ===
        case ("POST", "/input"):
            guard let obj = parseJSON(body), let text = obj["text"] as? String else {
                return err("Need {\"text\": \"...\"}")
            }
            await MainActor.run { chatVM.currentInput = text }
            return ok()
        case ("GET", "/input"):
            let text = await MainActor.run { chatVM.currentInput }
            return jsonDict(["text": text])

        // === MIC ===
        case ("POST", "/mic/toggle"):
            await chatVM.toggleListening()
            let listening = await MainActor.run { chatVM.speechInput?.isListening ?? false }
            return jsonDict(["status": "ok", "listening": listening])
        case ("GET", "/mic"):
            let listening = await MainActor.run { chatVM.speechInput?.isListening ?? false }
            let available = await MainActor.run { chatVM.speechInput != nil }
            return jsonDict(["listening": listening, "available": available])

        // === IMAGE ===
        case ("POST", "/attach"):
            await MainActor.run { chatVM.showFilePicker = true }
            return ok()
        case ("POST", "/image"):
            guard let obj = parseJSON(body), let path = obj["path"] as? String else {
                return err("Need {\"path\": \"/path/to/image.png\"}")
            }
            let url = URL(fileURLWithPath: path)
            await chatVM.handleImageDrop(urls: [url])
            let count = await MainActor.run { chatVM.messages.count }
            return jsonDict(["status": "ok", "messages_count": count])

        // === WINDOW ===
        case ("POST", "/window/focus"):
            await MainActor.run {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
            return ok()

        // === SPEECH ===
        case ("POST", "/speak"):
            return await speak(body, chatVM: chatVM)
        case ("POST", "/stop-speaking"):
            await MainActor.run { chatVM.speechOutput?.stop() }
            return ok()
        case ("GET", "/speech"):
            let speaking = await MainActor.run { chatVM.speechOutput?.isSpeaking ?? false }
            let autoSpeak = await MainActor.run { chatVM.autoSpeak }
            return jsonDict(["speaking": speaking, "auto_speak": autoSpeak])

        // === UPDATE ===
        case ("GET", "/update"):
            return await getUpdateStatus(settingsVM)
        case ("POST", "/update/check"):
            await settingsVM.checkForUpdate(mode: .manual)
            return await getUpdateStatus(settingsVM)
        case ("POST", "/update/install"):
            await MainActor.run { settingsVM.installUpdate() }
            return await getUpdateStatus(settingsVM)
        case ("POST", "/update/relaunch"):
            let response = jsonDict(["status": "relaunching"])
            Task { @MainActor in settingsVM.relaunch() }
            return response

        #if DEBUG
        case ("POST", "/debug/update-scenario"):
            return await setDebugUpdateScenario(body, settingsVM: settingsVM)
        case ("POST", "/debug/reset-first-run"):
            await settingsVM.debugResetFirstRun()
            return await getStartupStatus(settingsVM)
        #endif

        // === HELP ===
        default:
            return helpResponse()
        }
    }

    // MARK: - State

    private static func getState(_ chatVM: ChatViewModel, listVM: ConversationListViewModel) async -> String {
        await MainActor.run {
            jsonDict([
                "status": "ok",
                "conversation_count": listVM.conversations.count,
                "selected_conversation": listVM.selectedId ?? "",
                "messages_count": chatVM.messages.count,
                "is_streaming": chatVM.isStreaming,
                "current_input": chatVM.currentInput,
                "error_message": chatVM.errorMessage ?? "",
            ])
        }
    }

    // MARK: - Conversations

    private static func listConversations(_ listVM: ConversationListViewModel) async -> String {
        await MainActor.run {
            let convs = listVM.conversations.map { conv -> [String: Any] in
                ["id": conv.id, "title": conv.title, "updated_at": conv.updatedAt.timeIntervalSince1970]
            }
            return jsonDict(["conversations": convs, "count": convs.count])
        }
    }

    private static func createConversation(_ listVM: ConversationListViewModel) async -> String {
        await listVM.createConversation()
        return await MainActor.run {
            guard let conv = listVM.conversations.first else { return err("Failed to create") }
            return jsonDict(["status": "ok", "id": conv.id, "title": conv.title])
        }
    }

    private static func renameConversation(_ body: String, listVM: ConversationListViewModel) async -> String {
        guard let obj = parseJSON(body), let id = obj["id"] as? String, let title = obj["title"] as? String else {
            return err("Need {\"id\": \"...\", \"title\": \"...\"}")
        }
        await listVM.renameConversation(id: id, title: title)
        return ok()
    }

    private static func deleteConversation(_ body: String, listVM: ConversationListViewModel) async -> String {
        guard let obj = parseJSON(body), let id = obj["id"] as? String else {
            return err("Need {\"id\": \"...\"}")
        }
        await listVM.deleteConversation(id: id)
        return ok()
    }

    private static func selectConversation(_ body: String, chatVM: ChatViewModel, listVM: ConversationListViewModel) async -> String {
        guard let obj = parseJSON(body), let id = obj["id"] as? String else {
            return err("Need {\"id\": \"...\"}")
        }
        await MainActor.run {
            listVM.selectedId = id
            chatVM.conversationId = id
        }
        await chatVM.loadMessages()
        return await MainActor.run {
            jsonDict(["status": "ok", "conversation_id": id, "messages_count": chatVM.messages.count])
        }
    }

    private static func getMessages(_ chatVM: ChatViewModel, listVM: ConversationListViewModel, conversationId: String) async -> String {
        // Temporarily load messages for requested conversation
        let previousId = await MainActor.run { chatVM.conversationId }
        await MainActor.run { chatVM.conversationId = conversationId }
        await chatVM.loadMessages()
        let result = await MainActor.run {
            let msgs = chatVM.messages.map { msg -> [String: Any] in
                var m: [String: Any] = [
                    "id": msg.id, "role": msg.role.rawValue, "content": msg.content,
                ]
                if let tokens = msg.tokenCount { m["tokens"] = tokens }
                if let ms = msg.durationMs { m["duration_ms"] = ms }
                return m
            }
            return jsonDict(["messages": msgs, "count": msgs.count, "conversation_id": conversationId])
        }
        // Restore previous conversation
        if let prev = previousId {
            await MainActor.run { chatVM.conversationId = prev }
            await chatVM.loadMessages()
        }
        return result
    }

    // MARK: - Chat

    private static func sendMessage(_ body: String, chatVM: ChatViewModel) async -> String {
        guard let obj = parseJSON(body), let message = obj["message"] as? String else {
            return err("Need {\"message\": \"text\"}")
        }
        await MainActor.run { chatVM.currentInput = message }
        await chatVM.send()
        return await MainActor.run {
            guard let msg = chatVM.messages.last else { return ok() }
            return jsonDict([
                "status": "ok",
                "role": msg.role.rawValue,
                "content": msg.content,
                "tokens": msg.tokenCount ?? 0,
                "duration_ms": msg.durationMs ?? 0,
            ])
        }
    }

    private static func setSystemPrompt(_ body: String, chatVM: ChatViewModel) async -> String {
        guard let obj = parseJSON(body), let prompt = obj["prompt"] as? String else {
            return err("Need {\"prompt\": \"text\"}")
        }
        await MainActor.run { chatVM.systemPrompt = prompt }
        return ok()
    }

    // MARK: - Settings

    private static func getSettings(_ settingsVM: SettingsViewModel) async -> String {
        await MainActor.run {
            jsonDict([
                "temperature": settingsVM.temperature as Any,
                "max_tokens": settingsVM.maxTokens as Any,
                "seed": settingsVM.seed as Any,
                "json_mode": settingsVM.jsonMode,
                "base_url": settingsVM.baseURL,
                "model_name": settingsVM.modelName,
                "tts_language": settingsVM.ttsLanguage,
                "auto_speak": settingsVM.autoSpeak,
                "appearance": settingsVM.appearance,
                "check_updates_on_launch": settingsVM.checkUpdatesOnLaunch,
                "show_welcome_on_next_start": settingsVM.showWelcomeOnNextStart,
            ])
        }
    }

    private static func updateSettings(_ body: String, settingsVM: SettingsViewModel) async -> String {
        guard let obj = parseJSON(body) else { return err("Invalid JSON") }
        await MainActor.run {
            if let v = obj["temperature"] as? Double { settingsVM.temperature = v }
            if obj["max_tokens"] is NSNull { settingsVM.maxTokens = nil }
            else if let v = obj["max_tokens"] as? Int { settingsVM.maxTokens = v }
            if obj["seed"] is NSNull { settingsVM.seed = nil }
            else if let v = obj["seed"] as? Int { settingsVM.seed = v }
            if let v = obj["json_mode"] as? Bool { settingsVM.jsonMode = v }
            if let v = obj["base_url"] as? String { settingsVM.baseURL = v }
            if let v = obj["model_name"] as? String { settingsVM.modelName = v }
            if let v = obj["tts_language"] as? String { settingsVM.ttsLanguage = v }
            if let v = obj["auto_speak"] as? Bool { settingsVM.autoSpeak = v }
            if let v = obj["appearance"] as? String, ["system","light","dark"].contains(v) { settingsVM.appearance = v }
            if let v = obj["check_updates_on_launch"] as? Bool { settingsVM.checkUpdatesOnLaunch = v }
            if let v = obj["show_welcome_on_next_start"] as? Bool { settingsVM.showWelcomeOnNextStart = v }
            settingsVM.save()
        }
        return ok()
    }

    private static func getStartupStatus(_ settingsVM: SettingsViewModel) async -> String {
        await MainActor.run {
            jsonDict([
                "visible": settingsVM.showStartupOverlay,
                "has_seen": settingsVM.hasSeenStartupOverlay,
                "check_updates_on_launch": settingsVM.checkUpdatesOnLaunch,
                "show_welcome_on_next_start": settingsVM.showWelcomeOnNextStart,
                "current_version": settingsVM.currentVersion,
                "last_seen_version": settingsVM.lastSeenWelcomeVersion,
                "last_launched_version": settingsVM.lastLaunchedVersion as Any,
                "title": StartupWelcomeContent.title,
                "subtitle": StartupWelcomeContent.subtitle,
                "summary": StartupWelcomeContent.summary,
                "engine_summary": StartupWelcomeContent.engineSummary,
                "bullets": StartupWelcomeContent.bullets,
                "engine_url": StartupWelcomeContent.engineURL.absoluteString,
                "app_url": StartupWelcomeContent.appURL.absoluteString,
            ])
        }
    }

    // MARK: - Speech

    private static func speak(_ body: String, chatVM: ChatViewModel) async -> String {
        guard let obj = parseJSON(body), let text = obj["text"] as? String else {
            return err("Need {\"text\": \"...\"}")
        }
        let lang = obj["language"] as? String ?? AppDefaults.ttsLanguage
        await MainActor.run { chatVM.speechOutput?.speak(text, languageCode: lang) }
        return jsonDict(["status": "speaking", "text": text])
    }

    // MARK: - Update

    private static func getUpdateStatus(_ settingsVM: SettingsViewModel) async -> String {
        await MainActor.run {
            let state: String
            var latest: Any = NSNull()
            var updateAvailable = false

            switch settingsVM.updateState {
            case .idle:
                state = "idle"
            case .checking:
                state = "checking"
            case .upToDate:
                state = "up_to_date"
                latest = settingsVM.currentVersion
            case .updateAvailable(let v):
                state = "update_available"
                latest = v
                updateAvailable = true
            case .installing(let v):
                state = "installing"
                latest = v
                updateAvailable = true
            case .installed(let v):
                state = "installed"
                latest = v
            case .error(let m):
                return jsonDict([
                    "state": "error", "error": m,
                    "current_version": settingsVM.currentVersion,
                    "update_available": false,
                    "install_method": settingsVM.isHomebrewInstall ? "homebrew" : "direct",
                ])
            }

            return jsonDict([
                "state": state,
                "current_version": settingsVM.currentVersion,
                "latest_version": latest,
                "update_available": updateAvailable,
                "install_method": settingsVM.isHomebrewInstall ? "homebrew" : "direct",
            ])
        }
    }

    #if DEBUG
    private static func setDebugUpdateScenario(_ body: String, settingsVM: SettingsViewModel) async -> String {
        guard let obj = parseJSON(body) else { return err("Invalid JSON") }
        await MainActor.run {
            if obj["clear"] as? Bool == true {
                settingsVM.debugUpdateScenario = nil
                settingsVM.updateState = .idle
                return
            }
            if let latestVersion = obj["latest_version"] as? String {
                settingsVM.debugUpdateScenario = .latestVersion(latestVersion)
                settingsVM.updateState = .idle
                return
            }
            if let errorMessage = obj["error"] as? String {
                settingsVM.debugUpdateScenario = .error(errorMessage)
                settingsVM.updateState = .idle
                return
            }
        }
        return ok()
    }
    #endif

    // MARK: - Help

    nonisolated private static func helpResponse() -> String {
        var endpoints = [
            "GET  /                       Help (this response)",
            "GET  /state                  App state",
            "GET  /conversations           List all conversations",
            "GET  /conversations?id=X      Get messages for conversation X",
            "POST /conversations           Create new conversation",
            "POST /conversations/rename    Rename: {\"id\": \"...\", \"title\": \"...\"}",
            "POST /conversations/delete    Delete: {\"id\": \"...\"}",
            "POST /conversations/select    Select: {\"id\": \"...\"}",
            "POST /send                   Send message: {\"message\": \"text\"}",
            "POST /clear                  Clear chat",
            "POST /system-prompt          Set system prompt: {\"prompt\": \"text\"}",
            "GET  /settings               Get settings",
            "POST /settings               Update settings: {\"temperature\": 0.7, \"appearance\": \"system|light|dark\", ...}",
            "POST /settings/show          Open settings panel",
            "POST /settings/hide          Close settings panel",
            "GET  /startup                Get startup welcome screen state",
            "GET  /welcome                Alias for /startup",
            "POST /startup/show           Show startup welcome screen",
            "POST /welcome/show           Alias for /startup/show",
            "POST /startup/dismiss        Dismiss startup welcome screen",
            "POST /welcome/dismiss        Alias for /startup/dismiss",
            "POST /input                  Set input text: {\"text\": \"...\"}",
            "GET  /input                  Get current input text",
            "POST /mic/toggle             Toggle microphone listening",
            "GET  /mic                    Mic status",
            "POST /attach                 Open file picker",
            "POST /image                  Analyze image: {\"path\": \"/path/to/img\"}",
            "POST /window/focus           Bring window to front",
            "POST /speak                  Speak text: {\"text\": \"...\"}",
            "POST /stop-speaking          Stop TTS",
            "GET  /speech                 Speech status",
            "GET  /update                 Update status and latest version",
            "POST /update/check           Check GitHub for latest release",
            "POST /update/install         Install update (brew upgrade or opens download page)",
            "POST /update/relaunch        Relaunch app to apply installed update",
        ]
        #if DEBUG
        endpoints.append("POST /debug/update-scenario  Debug-only fake latest version or offline error")
        endpoints.append("POST /debug/reset-first-run  Debug-only clear welcome seen marker")
        #endif

        return jsonDict([
            "name": "apfel-chat control API",
            "usage": "Start with: apfel-chat --api",
            "port": 11441,
            "endpoints": endpoints
        ])
    }

    // MARK: - Helpers

    nonisolated private static func parseJSON(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    nonisolated private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { result[String(kv[0])] = String(kv[1]) }
        }
        return result
    }

    nonisolated private static func ok(_ extra: [String: Any] = [:]) -> String {
        var d: [String: Any] = ["status": "ok"]
        for (k, v) in extra { d[k] = v }
        return jsonDict(d)
    }

    nonisolated private static func err(_ message: String) -> String {
        jsonDict(["error": message])
    }

    nonisolated private static func jsonDict(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

// MARK: - Socket helpers

private func createControlListenerSocket(port: UInt16) -> Int32? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var opt: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bindResult == 0, listen(fd, 5) == 0 else { close(fd); return nil }
    return fd
}

private func acceptControlSocket(_ listener: Int32) async throws -> Int32 {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(listener, $0, &len) }
            }
            client >= 0 ? continuation.resume(returning: client) : continuation.resume(throwing: NSError(domain: "accept", code: Int(client)))
        }
    }
}
