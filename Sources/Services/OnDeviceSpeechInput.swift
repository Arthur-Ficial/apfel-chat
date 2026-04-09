import Speech
import AVFoundation

@Observable
@MainActor
final class OnDeviceSpeechInput: SpeechInput {
    var isListening = false
    var transcript = ""
    var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var userStoppedSession = false

    init(locale: Locale = Locale(identifier: AppDefaults.ttsLanguage)) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestPermissions() async -> Bool {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized: break
        case .notDetermined:
            let granted = await withUnsafeContinuation { (c: UnsafeContinuation<Bool, Never>) in
                let handler: @Sendable (Bool) -> Void = { granted in c.resume(returning: granted) }
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: handler)
            }
            if !granted {
                errorMessage = "Microphone access needed. Enable in System Settings > Privacy & Security > Microphone."
                return false
            }
        default:
            errorMessage = "Microphone access needed. Enable in System Settings > Privacy & Security > Microphone."
            return false
        }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .authorized { return true }
        if speechStatus != .notDetermined {
            errorMessage = "Speech recognition needed. Enable in System Settings > Privacy & Security > Speech Recognition."
            return false
        }

        let authorized = await withUnsafeContinuation { (c: UnsafeContinuation<Bool, Never>) in
            let handler: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
                c.resume(returning: status == .authorized)
            }
            SFSpeechRecognizer.requestAuthorization(handler)
        }
        if !authorized { errorMessage = "Speech recognition not authorized." }
        return authorized
    }

    func startListening() {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        transcript = ""
        errorMessage = nil
        userStoppedSession = false

        do {
            let engine = AVAudioEngine()
            self.audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil {
                        if !self.userStoppedSession && self.transcript.isEmpty {
                            self.errorMessage = "Speech recognition failed"
                        }
                        self.cleanup()
                    }
                }
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "No microphone input available"
                return
            }

            nonisolated(unsafe) let audioRequest = request
            let tapHandler: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
                audioRequest.append(buffer)
            }
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapHandler)
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            cleanup()
        }
    }

    func stopListening() -> String {
        userStoppedSession = true
        cleanup()
        return transcript
    }

    private func cleanup() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}
