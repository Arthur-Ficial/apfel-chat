import Foundation

protocol InstallLocating {
    var isHomebrewInstall: Bool { get }
}

struct DefaultInstallLocator: InstallLocating {
    var isHomebrewInstall: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/Caskroom/apfel-chat") ||
        FileManager.default.fileExists(atPath: "/usr/local/Caskroom/apfel-chat")
    }
}
