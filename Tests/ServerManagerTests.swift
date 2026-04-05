import Testing
import Foundation
@testable import apfel_chat

@Suite("Server Manager")
struct ServerManagerTests {

    @Test("findApfelBinary returns path when apfel exists")
    func findApfelInPath() {
        let path = ServerManager.findApfelBinary()
        #expect(path != nil)
    }

    @Test("isPortAvailable returns true for unused port")
    func portAvailable() {
        let available = ServerManager.isPortAvailable(59999)
        #expect(available == true)
    }

    @Test("findAvailablePort returns a port in range")
    func findPort() {
        let port = ServerManager.findAvailablePort(startingAt: 59990)
        #expect(port >= 59990)
        #expect(port < 60000)
    }

    @Test("buildArguments creates correct flags")
    func buildArgs() {
        let args = ServerManager.buildArguments(port: 11440)
        #expect(args.contains("--serve"))
        #expect(args.contains("--port"))
        #expect(args.contains("11440"))
        #expect(args.contains("--cors"))
        #expect(!args.contains("--debug"))
    }
}
