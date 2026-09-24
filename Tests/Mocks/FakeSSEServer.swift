import Foundation

/// Minimal scripted HTTP/1.1 server for exercising the real `ApfelChatService`
/// streaming path over a loopback socket. One connection, one scripted response.
final class FakeSSEServer: @unchecked Sendable {
    enum Ending {
        /// Send every chunk, then `data: [DONE]`, then a clean chunked terminator.
        case done
        /// Send every chunk, then end the body cleanly WITHOUT `data: [DONE]`.
        case endWithoutDone
        /// Send every chunk, then keep the connection open until the client closes it.
        case hangUntilClientCloses
    }

    let port: UInt16
    private let listener: Int32
    private let chunks: [String]
    private let ending: Ending
    private let disconnectSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _receivedRequest: String = ""

    var receivedRequest: String {
        lock.lock(); defer { lock.unlock() }
        return _receivedRequest
    }

    init(chunks: [String], ending: Ending) throws {
        self.chunks = chunks
        self.ending = ending

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "FakeSSEServer", code: 1) }
        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else { close(fd); throw NSError(domain: "FakeSSEServer", code: 2) }

        var bound_addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound_addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        self.listener = fd
        self.port = UInt16(bigEndian: bound_addr.sin_port)

        Thread.detachNewThread { [self] in self.serve() }
    }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Waits until the client closed its side of the connection. Returns false on timeout.
    func waitForClientDisconnect(timeout: TimeInterval) -> Bool {
        disconnectSemaphore.wait(timeout: .now() + timeout) == .success
    }

    private func serve() {
        var clientAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(listener, $0, &len) }
        }
        guard client >= 0 else { return }
        defer { close(client); close(listener) }

        // Read the complete request (headers plus Content-Length body). URLSession may
        // deliver the head and the body in separate segments, so loop until complete.
        var raw = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while !Self.isCompleteRequest(raw) {
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else { break }
            raw.append(contentsOf: buffer[0..<n])
        }
        lock.lock()
        _receivedRequest = String(decoding: raw, as: UTF8.self)
        lock.unlock()

        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/event-stream\r\n"
        response += "Cache-Control: no-cache\r\n"
        response += "Transfer-Encoding: chunked\r\n"
        response += "Connection: keep-alive\r\n\r\n"
        write(client, response)

        for chunk in chunks {
            writeChunk(client, "data: \(chunk)\n\n")
        }

        switch ending {
        case .done:
            writeChunk(client, "data: [DONE]\n\n")
            write(client, "0\r\n\r\n")
        case .endWithoutDone:
            write(client, "0\r\n\r\n")
        case .hangUntilClientCloses:
            // Block until the peer closes: read returns 0 (FIN) or -1 (RST).
            // Positive reads would be stray request bytes, not a disconnect.
            var one = [UInt8](repeating: 0, count: 1)
            while read(client, &one, 1) > 0 {}
            disconnectSemaphore.signal()
        }
    }

    private static func isCompleteRequest(_ raw: [UInt8]) -> Bool {
        let text = String(decoding: raw, as: UTF8.self)
        guard let headerEnd = text.range(of: "\r\n\r\n") else { return false }
        let head = text[..<headerEnd.lowerBound].lowercased()
        var contentLength = 0
        for line in head.split(separator: "\r\n") where line.hasPrefix("content-length:") {
            contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return text[headerEnd.upperBound...].utf8.count >= contentLength
    }

    private func writeChunk(_ fd: Int32, _ payload: String) {
        let data = Array(payload.utf8)
        write(fd, String(data.count, radix: 16) + "\r\n")
        _ = data.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
        write(fd, "\r\n")
    }

    private func write(_ fd: Int32, _ text: String) {
        let data = Array(text.utf8)
        _ = data.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
    }
}
