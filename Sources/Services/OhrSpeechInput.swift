import Foundation

@Observable
@MainActor
final class OhrSpeechInput: SpeechInput {
    var isListening = false
    var transcript = ""
    var errorMessage: String?

    private let ohrPath: String
    private var process: Process?
    private var languageCode: String

    init(ohrPath: String, languageCode: String = "en-US") {
        self.ohrPath = ohrPath
        self.languageCode = languageCode
    }

    func requestPermissions() async -> Bool {
        // ohr handles its own permissions
        return true
    }

    func startListening() {
        guard !isListening else { return }
        transcript = ""
        errorMessage = nil

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ohrPath)
        proc.arguments = ["--mic", "--language", languageCode]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            self.process = proc
            isListening = true
            printToStderr("ohr: listening (\(languageCode))")

            // Read output in background
            let fileHandle = pipe.fileHandleForReading
            Task.detached { [weak self] in
                while let data = try? fileHandle.availableData, !data.isEmpty {
                    if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        await MainActor.run {
                            self?.transcript = text
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Failed to start ohr: \(error.localizedDescription)"
            isListening = false
        }
    }

    func stopListening() -> String {
        process?.terminate()
        process = nil
        isListening = false
        printToStderr("ohr: stopped, transcript: \"\(transcript)\"")
        return transcript
    }
}
