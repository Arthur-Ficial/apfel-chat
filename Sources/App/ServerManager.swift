import Foundation
import os

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
    nonisolated private static let healthSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.25
        configuration.timeoutIntervalForResource = 0.5
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Finds an executable by name, checking PATH, bundle, and common install locations
    nonisolated static func findBinary(named name: String) -> String? {
        if let resolved = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map({ "\($0)/\(name)" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return resolved
        }
        if let execPath = Bundle.main.executablePath {
            let bundleDir = URL(fileURLWithPath: execPath).deletingLastPathComponent()
            let inMacOS = bundleDir.appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: inMacOS) { return inMacOS }
            let inHelpers = bundleDir.deletingLastPathComponent()
                .appendingPathComponent("Helpers/\(name)").path
            if FileManager.default.isExecutableFile(atPath: inHelpers) { return inHelpers }
        }
        let fallbacks = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(name)",
        ]
        return fallbacks.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func findOhrBinary() -> String? {
        findBinary(named: "ohr")
    }

    nonisolated static func findApfelBinary() -> String? {
        findBinary(named: "apfel")
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

    nonisolated static func findAvailablePort(startingAt: Int = AppDefaults.serverPortStart) -> Int {
        for port in startingAt..<(startingAt + 10) {
            if isPortAvailable(port) { return port }
        }
        return startingAt
    }

    nonisolated static func buildArguments(port: Int) -> [String] {
        let isPermissive = UserDefaults.standard.object(forKey: "ac_permissive") == nil
            || UserDefaults.standard.bool(forKey: "ac_permissive")
        var args = ["--serve", "--port", "\(port)", "--cors"]
        if isPermissive { args.append("--permissive") }
        return args
    }

    func tryExistingServer() async -> Int? {
        let ports = [11434, 11435] + Array(11440...11449)
        var foundPort: Int?

        await withTaskGroup(of: Int?.self) { group in
            for port in ports {
                group.addTask {
                    await Self.isHealthyServer(port: port) ? port : nil
                }
            }

            for await candidate in group {
                if let port = candidate {
                    foundPort = port
                    group.cancelAll()
                    break
                }
            }
        }

        if let foundPort {
            state = .running(port: foundPort, process: nil)
            return foundPort
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
        while Date().timeIntervalSince(start) < timeout {
            if await Self.isHealthyServer(port: port) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    nonisolated private static func isHealthyServer(port: Int) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        do {
            let (_, response) = try await healthSession.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

/// Returns true if running inside a .app bundle (Contents/MacOS/...)
func isRunningAsAppBundle() -> Bool {
    let path = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
    return path.contains(".app/Contents/MacOS/")
}

private let appLogger = Logger(subsystem: "com.fullstackoptimization.apfel-chat", category: "general")

func printToStderr(_ message: String) {
    if isRunningAsAppBundle() {
        appLogger.info("\(message)")
    } else {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
