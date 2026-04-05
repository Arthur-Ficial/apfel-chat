import Foundation

@MainActor
final class ServerManager {
    enum State {
        case idle
        case starting
        case running(port: Int, process: Process?)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var serverProcess: Process?

    nonisolated static func findOhrBinary() -> String? {
        if let resolved = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map({ "\($0)/ohr" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return resolved
        }
        let fallbacks = ["/usr/local/bin/ohr", "/opt/homebrew/bin/ohr"]
        return fallbacks.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func findApfelBinary() -> String? {
        if let resolved = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map({ "\($0)/apfel" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return resolved
        }
        let fallbacks = ["/usr/local/bin/apfel", "/opt/homebrew/bin/apfel"]
        return fallbacks.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func isPortAvailable(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        var optval: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(MemoryLayout<Int32>.size))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    nonisolated static func findAvailablePort(startingAt: Int = 11440) -> Int {
        for port in startingAt..<(startingAt + 10) {
            if isPortAvailable(port) { return port }
        }
        return startingAt
    }

    nonisolated static func buildArguments(port: Int) -> [String] {
        ["--serve", "--port", "\(port)", "--cors"]
    }

    func tryExistingServer() async -> Int? {
        let ports = [11434, 11435] + Array(11440...11449)
        for port in ports {
            let url = URL(string: "http://127.0.0.1:\(port)/health")!
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    state = .running(port: port, process: nil)
                    return port
                }
            } catch { continue }
        }
        return nil
    }

    func start() async -> Int? {
        state = .starting
        if let port = await tryExistingServer() {
            printToStderr("apfel-chat: connected to existing server on port \(port)")
            return port
        }
        guard let apfelPath = Self.findApfelBinary() else {
            state = .failed("apfel not found. Install: brew install Arthur-Ficial/tap/apfel")
            printToStderr("apfel-chat: error: apfel not found in PATH")
            return nil
        }
        let port = Self.findAvailablePort()
        let args = Self.buildArguments(port: port)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: apfelPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.serverProcess = process
            printToStderr("apfel-chat: server starting on port \(port) (PID: \(process.processIdentifier))")
        } catch {
            state = .failed("Failed to start apfel: \(error.localizedDescription)")
            return nil
        }
        let ready = await waitForReady(port: port, timeout: 8.0)
        if ready {
            state = .running(port: port, process: process)
            printToStderr("apfel-chat: server ready on port \(port)")
            return port
        } else {
            process.terminate()
            state = .failed("Server failed to start within 8 seconds")
            return nil
        }
    }

    func stop() {
        if let process = serverProcess, process.isRunning {
            process.terminate()
            printToStderr("apfel-chat: server terminated")
        }
        serverProcess = nil
        state = .idle
    }

    private func waitForReady(port: Int, timeout: Double) async -> Bool {
        let start = Date()
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        while Date().timeIntervalSince(start) < timeout {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return true }
            } catch {}
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
}

func printToStderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
